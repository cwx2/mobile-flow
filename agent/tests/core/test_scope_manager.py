"""Unit tests for core/scope_manager.py — ScopeManager orchestrator.

Tests cover:
    - RegistrationResult dataclass
    - register_strategy() for all connection modes
    - register_client() — fresh scope creation and scope resume
    - unregister_client() — suspension with grace timer and immediate dispose
    - _enforce_capacity() — LRU eviction when over max
    - dispose_all() — graceful shutdown
    - _create_scope() — cleanup factory delegation
"""

from __future__ import annotations

import asyncio
import time
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from mobileflow_agent.core.client_scope import ClientScope
from mobileflow_agent.core.identity_resolver import (
    ClientIdentity,
    IdentityStrategy,
)
from mobileflow_agent.core.scope_manager import (
    RegistrationResult,
    ScopeManager,
)
from mobileflow_agent.core.scope_state import ScopeLifecycleState
from mobileflow_agent.server.connection_manager import ConnectionMode


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


class FakeStrategy(IdentityStrategy):
    """Test strategy that returns a fixed identity from credentials."""

    def __init__(self, target_mode: ConnectionMode):
        self._mode = target_mode

    @property
    def mode(self) -> ConnectionMode:
        return self._mode

    def resolve(self, credentials: dict):
        stable_id = credentials.get("stable_id")
        if not stable_id:
            return None
        return ClientIdentity(stable_id=stable_id, mode=self._mode)


@pytest.fixture
def mock_config():
    """Create a mock AgentConfig with required fields."""
    config = MagicMock()
    config.connection.disconnect_grace_period = 600
    config.scope.disconnect_grace_period = 600
    config.scope.max_suspended_scopes = 10
    config.scope.eviction_strategy = "lru"
    return config


@pytest.fixture
def mock_config_no_grace():
    """Config with grace period = 0 (immediate dispose)."""
    config = MagicMock()
    config.connection.disconnect_grace_period = 0
    config.scope.disconnect_grace_period = 0
    config.scope.max_suspended_scopes = 10
    config.scope.eviction_strategy = "lru"
    return config


@pytest.fixture
def mock_config_with_scope():
    """Config with scope.max_suspended_scopes set."""
    config = MagicMock()
    config.connection.disconnect_grace_period = 600
    config.scope.disconnect_grace_period = 600
    config.scope.max_suspended_scopes = 3
    config.scope.eviction_strategy = "lru"
    return config


@pytest.fixture
def mock_cli_manager():
    """Create a mock CLIManager."""
    cli = MagicMock()
    cli.remap_client = MagicMock()
    cli.cleanup_sessions = AsyncMock()
    return cli


@pytest.fixture
def scope_manager(mock_config, mock_cli_manager):
    """Create a ScopeManager with default config."""
    return ScopeManager(config=mock_config, cli_manager=mock_cli_manager)


@pytest.fixture
def scope_manager_no_grace(mock_config_no_grace, mock_cli_manager):
    """Create a ScopeManager with grace period = 0."""
    return ScopeManager(config=mock_config_no_grace, cli_manager=mock_cli_manager)


# ---------------------------------------------------------------------------
# RegistrationResult
# ---------------------------------------------------------------------------


class TestRegistrationResult:
    """Test the RegistrationResult dataclass."""

    def test_basic_creation(self):
        scope = ClientScope("test-client")
        result = RegistrationResult(scope=scope, resumed=False)
        assert result.scope is scope
        assert result.resumed is False
        assert result.old_client_id is None

    def test_resumed_with_old_client_id(self):
        scope = ClientScope("new-client")
        result = RegistrationResult(
            scope=scope, resumed=True, old_client_id="old-client"
        )
        assert result.resumed is True
        assert result.old_client_id == "old-client"


# ---------------------------------------------------------------------------
# register_strategy()
# ---------------------------------------------------------------------------


class TestRegisterStrategy:
    """Test strategy registration."""

    def test_register_lan_strategy(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.LAN)
        scope_manager.register_strategy(strategy)
        assert ConnectionMode.LAN in scope_manager._strategies

    def test_register_tunnel_strategy(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)
        assert ConnectionMode.TUNNEL in scope_manager._strategies

    def test_register_relay_strategy(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.RELAY)
        scope_manager.register_strategy(strategy)
        assert ConnectionMode.RELAY in scope_manager._strategies

    def test_register_replaces_existing(self, scope_manager):
        strategy1 = FakeStrategy(ConnectionMode.LAN)
        strategy2 = FakeStrategy(ConnectionMode.LAN)
        scope_manager.register_strategy(strategy1)
        scope_manager.register_strategy(strategy2)
        assert scope_manager._strategies[ConnectionMode.LAN] is strategy2


# ---------------------------------------------------------------------------
# register_client() — fresh scope creation
# ---------------------------------------------------------------------------


class TestRegisterClientFresh:
    """Test register_client when no suspended scope exists."""

    @pytest.mark.asyncio
    async def test_creates_fresh_scope(self, scope_manager):
        result = await scope_manager.register_client(
            "client-001", ConnectionMode.LAN
        )
        assert result.resumed is False
        assert result.old_client_id is None
        assert isinstance(result.scope, ClientScope)
        assert result.scope.client_id == "client-001"

    @pytest.mark.asyncio
    async def test_scope_in_active_map(self, scope_manager):
        await scope_manager.register_client("client-001", ConnectionMode.LAN)
        assert "client-001" in scope_manager._active_scopes
        assert scope_manager.active_count == 1

    @pytest.mark.asyncio
    async def test_with_credentials_but_no_suspended(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        result = await scope_manager.register_client(
            "client-001",
            ConnectionMode.TUNNEL,
            {"stable_id": "tunnel-identity-abc"},
        )
        assert result.resumed is False
        assert scope_manager.active_count == 1

    @pytest.mark.asyncio
    async def test_identity_stored_in_map(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        await scope_manager.register_client(
            "client-001",
            ConnectionMode.TUNNEL,
            {"stable_id": "tunnel-identity-abc"},
        )
        assert "client-001" in scope_manager._identity_map
        assert scope_manager._identity_map["client-001"].stable_id == "tunnel-identity-abc"

    @pytest.mark.asyncio
    async def test_no_strategy_registered(self, scope_manager):
        """Without a strategy, still creates a fresh scope."""
        result = await scope_manager.register_client(
            "client-001", ConnectionMode.TUNNEL, {"bearer_token": "abc"}
        )
        assert result.resumed is False
        assert scope_manager.active_count == 1

    @pytest.mark.asyncio
    async def test_cleanup_factory_called(self, mock_config, mock_cli_manager):
        """Cleanup factory is invoked during scope creation."""
        factory_called = []

        async def fake_factory(client_id, scope):
            factory_called.append((client_id, scope))

        sm = ScopeManager(
            config=mock_config,
            cli_manager=mock_cli_manager,
            cleanup_factory=fake_factory,
        )
        result = await sm.register_client("client-001", ConnectionMode.LAN)
        assert len(factory_called) == 1
        assert factory_called[0][0] == "client-001"
        assert factory_called[0][1] is result.scope


# ---------------------------------------------------------------------------
# register_client() — scope resume
# ---------------------------------------------------------------------------


class TestRegisterClientResume:
    """Test register_client when a suspended scope exists for the identity."""

    @pytest.mark.asyncio
    async def test_resume_returns_same_scope(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        # Register and unregister to create a suspended scope
        result1 = await scope_manager.register_client(
            "client-001",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        original_scope = result1.scope
        await scope_manager.unregister_client("client-001")

        # Reconnect with same identity
        result2 = await scope_manager.register_client(
            "client-002",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        assert result2.resumed is True
        assert result2.scope is original_scope
        assert result2.old_client_id == "client-001"

    @pytest.mark.asyncio
    async def test_resume_updates_client_id(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        await scope_manager.register_client(
            "client-001",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        await scope_manager.unregister_client("client-001")

        result = await scope_manager.register_client(
            "client-002",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        assert result.scope.client_id == "client-002"

    @pytest.mark.asyncio
    async def test_resume_remaps_cli(self, scope_manager, mock_cli_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        await scope_manager.register_client(
            "client-001",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        await scope_manager.unregister_client("client-001")

        await scope_manager.register_client(
            "client-002",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        mock_cli_manager.remap_client.assert_called_once_with(
            "client-001", "client-002"
        )

    @pytest.mark.asyncio
    async def test_resume_cancels_grace_timer(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        await scope_manager.register_client(
            "client-001",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        await scope_manager.unregister_client("client-001")

        # Verify timer was created
        assert scope_manager.suspended_count == 1

        # Resume — timer should be cancelled
        await scope_manager.register_client(
            "client-002",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        assert scope_manager.suspended_count == 0
        assert scope_manager.active_count == 1

    @pytest.mark.asyncio
    async def test_resume_clears_cancelled_event(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        result1 = await scope_manager.register_client(
            "client-001",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        await scope_manager.unregister_client("client-001")
        # After unregister, cancelled should be set
        assert result1.scope.cancelled.is_set()

        # Resume — cancelled should be cleared
        result2 = await scope_manager.register_client(
            "client-002",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        assert not result2.scope.cancelled.is_set()


# ---------------------------------------------------------------------------
# unregister_client()
# ---------------------------------------------------------------------------


class TestUnregisterClient:
    """Test client disconnection handling."""

    @pytest.mark.asyncio
    async def test_suspends_scope(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        await scope_manager.register_client(
            "client-001",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        await scope_manager.unregister_client("client-001")

        assert scope_manager.active_count == 0
        assert scope_manager.suspended_count == 1

    @pytest.mark.asyncio
    async def test_sets_cancelled_event(self, scope_manager):
        result = await scope_manager.register_client(
            "client-001", ConnectionMode.LAN
        )
        await scope_manager.unregister_client("client-001")
        assert result.scope.cancelled.is_set()

    @pytest.mark.asyncio
    async def test_immediate_dispose_when_grace_zero(self, scope_manager_no_grace):
        result = await scope_manager_no_grace.register_client(
            "client-001", ConnectionMode.LAN
        )
        await scope_manager_no_grace.unregister_client("client-001")

        assert scope_manager_no_grace.active_count == 0
        assert scope_manager_no_grace.suspended_count == 0
        # Scope should be disposed
        assert result.scope._disposed is True

    @pytest.mark.asyncio
    async def test_unknown_client_id_is_noop(self, scope_manager):
        """Unregistering a non-existent client_id does nothing."""
        await scope_manager.unregister_client("nonexistent")
        assert scope_manager.active_count == 0
        assert scope_manager.suspended_count == 0

    @pytest.mark.asyncio
    async def test_grace_timer_disposes_after_expiry(self, scope_manager, mock_config):
        """Grace timer fires and disposes the scope."""
        # Use a very short grace period for testing
        mock_config.scope.disconnect_grace_period = 0.05  # 50ms

        result = await scope_manager.register_client(
            "client-001", ConnectionMode.LAN
        )
        await scope_manager.unregister_client("client-001")

        # Wait for grace timer to fire
        await asyncio.sleep(0.1)

        assert scope_manager.suspended_count == 0
        assert result.scope._disposed is True


# ---------------------------------------------------------------------------
# _enforce_capacity()
# ---------------------------------------------------------------------------


class TestEnforceCapacity:
    """Test LRU eviction when suspended count exceeds max."""

    @pytest.mark.asyncio
    async def test_evicts_oldest_when_over_capacity(self, mock_config_with_scope, mock_cli_manager):
        sm = ScopeManager(config=mock_config_with_scope, cli_manager=mock_cli_manager)
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        sm.register_strategy(strategy)

        # Register and unregister 4 clients (max is 3)
        scopes = []
        for i in range(4):
            result = await sm.register_client(
                f"client-{i:03d}",
                ConnectionMode.TUNNEL,
                {"stable_id": f"identity-{i:03d}"},
            )
            scopes.append(result.scope)
            await sm.unregister_client(f"client-{i:03d}")
            # Small delay to ensure different suspended_at timestamps
            await asyncio.sleep(0.01)

        # Should have evicted the oldest, leaving max_count
        assert sm.suspended_count == 3
        # The first scope (oldest) should be disposed
        assert scopes[0]._disposed is True
        # The rest should still be suspended (not disposed)
        assert scopes[1]._disposed is False
        assert scopes[2]._disposed is False
        assert scopes[3]._disposed is False

    @pytest.mark.asyncio
    async def test_no_eviction_when_under_capacity(self, mock_config_with_scope, mock_cli_manager):
        sm = ScopeManager(config=mock_config_with_scope, cli_manager=mock_cli_manager)
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        sm.register_strategy(strategy)

        # Register and unregister 2 clients (max is 3)
        for i in range(2):
            await sm.register_client(
                f"client-{i:03d}",
                ConnectionMode.TUNNEL,
                {"stable_id": f"identity-{i:03d}"},
            )
            await sm.unregister_client(f"client-{i:03d}")

        assert sm.suspended_count == 2

    @pytest.mark.asyncio
    async def test_defaults_to_10_without_scope_config(self, scope_manager):
        """When config.scope doesn't exist, defaults to max=10."""
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        # Register and unregister 10 clients — all should fit
        for i in range(10):
            await scope_manager.register_client(
                f"client-{i:03d}",
                ConnectionMode.TUNNEL,
                {"stable_id": f"identity-{i:03d}"},
            )
            await scope_manager.unregister_client(f"client-{i:03d}")

        assert scope_manager.suspended_count == 10


# ---------------------------------------------------------------------------
# dispose_all()
# ---------------------------------------------------------------------------


class TestDisposeAll:
    """Test graceful shutdown."""

    @pytest.mark.asyncio
    async def test_disposes_active_scopes(self, scope_manager):
        result = await scope_manager.register_client(
            "client-001", ConnectionMode.LAN
        )
        await scope_manager.dispose_all()

        assert scope_manager.active_count == 0
        assert result.scope._disposed is True

    @pytest.mark.asyncio
    async def test_disposes_suspended_scopes(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        result = await scope_manager.register_client(
            "client-001",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        await scope_manager.unregister_client("client-001")
        await scope_manager.dispose_all()

        assert scope_manager.suspended_count == 0
        assert result.scope._disposed is True

    @pytest.mark.asyncio
    async def test_cancels_grace_timers(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        await scope_manager.register_client(
            "client-001",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        await scope_manager.unregister_client("client-001")

        # Get the grace timer task
        entry = scope_manager._suspended_scopes.get("identity-xyz")
        assert entry is not None
        timer_task = entry.grace_timer
        assert timer_task is not None

        await scope_manager.dispose_all()

        # Allow event loop to process the cancellation
        await asyncio.sleep(0)

        # Timer should be cancelled
        assert timer_task.cancelled() or timer_task.done()

    @pytest.mark.asyncio
    async def test_clears_all_maps(self, scope_manager):
        strategy = FakeStrategy(ConnectionMode.TUNNEL)
        scope_manager.register_strategy(strategy)

        await scope_manager.register_client(
            "client-001",
            ConnectionMode.TUNNEL,
            {"stable_id": "identity-xyz"},
        )
        await scope_manager.register_client(
            "client-002", ConnectionMode.LAN
        )
        await scope_manager.unregister_client("client-001")

        await scope_manager.dispose_all()

        assert scope_manager.active_count == 0
        assert scope_manager.suspended_count == 0
        assert len(scope_manager._identity_map) == 0


# ---------------------------------------------------------------------------
# Properties
# ---------------------------------------------------------------------------


class TestProperties:
    """Test active_count and suspended_count properties."""

    @pytest.mark.asyncio
    async def test_initial_counts_are_zero(self, scope_manager):
        assert scope_manager.active_count == 0
        assert scope_manager.suspended_count == 0

    @pytest.mark.asyncio
    async def test_counts_after_register(self, scope_manager):
        await scope_manager.register_client("client-001", ConnectionMode.LAN)
        assert scope_manager.active_count == 1
        assert scope_manager.suspended_count == 0

    @pytest.mark.asyncio
    async def test_counts_after_unregister(self, scope_manager):
        await scope_manager.register_client("client-001", ConnectionMode.LAN)
        await scope_manager.unregister_client("client-001")
        assert scope_manager.active_count == 0
        assert scope_manager.suspended_count == 1
