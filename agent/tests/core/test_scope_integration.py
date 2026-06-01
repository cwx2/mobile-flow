"""Integration tests for scope management — end-to-end lifecycle scenarios.

Tests verify the full pipeline: identity resolution → scope resume/create →
grace period → capacity eviction. Uses real identity strategies (not mocks)
to validate the complete flow.

Validates requirements: FR-1 through FR-6, CP-2, CP-5.
"""

from __future__ import annotations

import asyncio
import hashlib
from unittest.mock import MagicMock

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from mobileflow_agent.core.identity_resolver import (
    LANIdentityStrategy,
    TunnelIdentityStrategy,
    RelayIdentityStrategy,
)
from mobileflow_agent.core.scope_manager import ScopeManager
from mobileflow_agent.server.connection_manager import ConnectionMode


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_cli_manager():
    """Mock CLIManager with remap_client and cleanup_sessions."""
    cli = MagicMock()
    cli.remap_client = MagicMock()
    cli.cleanup_sessions = MagicMock()
    return cli


@pytest.fixture
def mock_auth_manager():
    """Mock AuthManager that verifies session tokens deterministically.

    Maps session_token → client_id by using the token itself as the
    original client_id (simulates a successful verify_session call).
    """
    auth = MagicMock()

    def _verify_session(token: str):
        result = MagicMock()
        result.success = True
        result.client_id = f"original-{token}"
        result.error_code = None
        return result

    auth.verify_session = _verify_session
    return auth


def _make_config(grace_period: float = 600, max_suspended: int = 10):
    """Create a mock AgentConfig with scope settings."""
    config = MagicMock()
    config.scope.disconnect_grace_period = grace_period
    config.scope.max_suspended_scopes = max_suspended
    config.scope.eviction_strategy = "lru"
    return config


# ---------------------------------------------------------------------------
# 6.1 Tunnel client disconnect → reconnect with same bearer → scope resumed
# ---------------------------------------------------------------------------


class TestTunnelReconnect:
    """Validates: FR-1 (AC-1.3), FR-4 (AC-4.2, AC-4.3), CP-5."""

    async def test_tunnel_disconnect_reconnect_resumes_scope(
        self, mock_cli_manager
    ):
        """Tunnel client disconnects and reconnects with same bearer token → scope resumed."""
        config = _make_config(grace_period=600)
        sm = ScopeManager(config=config, cli_manager=mock_cli_manager)
        sm.register_strategy(TunnelIdentityStrategy())

        # Step 1: Register first client with bearer token
        result1 = await sm.register_client(
            "client-1", ConnectionMode.TUNNEL, {"bearer_token": "my-token"}
        )
        original_scope = result1.scope
        assert result1.resumed is False

        # Step 2: Disconnect (scope suspended)
        await sm.unregister_client("client-1")
        assert sm.suspended_count == 1
        assert sm.active_count == 0

        # Step 3: Reconnect with same bearer token, different client_id
        result2 = await sm.register_client(
            "client-2", ConnectionMode.TUNNEL, {"bearer_token": "my-token"}
        )

        # Assertions: scope resumed, same instance, old_client_id tracked
        assert result2.resumed is True
        assert result2.scope is original_scope
        assert result2.old_client_id == "client-1"
        assert result2.scope.client_id == "client-2"
        assert sm.active_count == 1
        assert sm.suspended_count == 0

    async def test_tunnel_different_bearer_creates_new_scope(
        self, mock_cli_manager
    ):
        """Different bearer token creates a new scope (no resume)."""
        config = _make_config(grace_period=600)
        sm = ScopeManager(config=config, cli_manager=mock_cli_manager)
        sm.register_strategy(TunnelIdentityStrategy())

        result1 = await sm.register_client(
            "client-1", ConnectionMode.TUNNEL, {"bearer_token": "token-A"}
        )
        await sm.unregister_client("client-1")

        result2 = await sm.register_client(
            "client-2", ConnectionMode.TUNNEL, {"bearer_token": "token-B"}
        )

        assert result2.resumed is False
        assert result2.scope is not result1.scope


# ---------------------------------------------------------------------------
# 6.2 LAN client auth.pair → disconnect → auth.connect → scope resumed
# ---------------------------------------------------------------------------


class TestLANReconnect:
    """Validates: FR-1 (AC-1.2), FR-2 (AC-2.1), FR-4 (AC-4.2, AC-4.4), CP-5."""

    async def test_lan_auth_pair_disconnect_auth_connect_resumes_scope(
        self, mock_cli_manager, mock_auth_manager
    ):
        """LAN client: auth.pair → disconnect → auth.connect → scope resumed."""
        config = _make_config(grace_period=600)
        sm = ScopeManager(config=config, cli_manager=mock_cli_manager)
        sm.register_strategy(LANIdentityStrategy(mock_auth_manager))

        # Step 1: First client registers with session token (auth.pair)
        result1 = await sm.register_client(
            "client-1", ConnectionMode.LAN, {"session_token": "token-abc"}
        )
        original_scope = result1.scope
        assert result1.resumed is False

        # Step 2: Client disconnects (scope suspended)
        await sm.unregister_client("client-1")
        assert sm.suspended_count == 1

        # Step 3: New client reconnects with same session token (auth.connect)
        result2 = await sm.register_client(
            "client-2", ConnectionMode.LAN, {"session_token": "token-abc"}
        )

        # Assertions: scope resumed with same instance
        assert result2.resumed is True
        assert result2.scope is original_scope
        assert result2.scope.client_id == "client-2"
        assert result2.old_client_id == "client-1"

        # CLI sessions remapped
        mock_cli_manager.remap_client.assert_called_once_with(
            "client-1", "client-2"
        )

    async def test_lan_different_session_token_creates_new_scope(
        self, mock_cli_manager, mock_auth_manager
    ):
        """Different session token (different identity) creates a new scope."""
        config = _make_config(grace_period=600)
        sm = ScopeManager(config=config, cli_manager=mock_cli_manager)
        sm.register_strategy(LANIdentityStrategy(mock_auth_manager))

        result1 = await sm.register_client(
            "client-1", ConnectionMode.LAN, {"session_token": "token-abc"}
        )
        await sm.unregister_client("client-1")

        # Different token → different identity → new scope
        result2 = await sm.register_client(
            "client-2", ConnectionMode.LAN, {"session_token": "token-xyz"}
        )

        assert result2.resumed is False
        assert result2.scope is not result1.scope


# ---------------------------------------------------------------------------
# 6.3 Capacity eviction — suspend N+1 scopes, verify oldest is disposed
# ---------------------------------------------------------------------------


class TestCapacityEviction:
    """Validates: FR-5 (AC-5.1 through AC-5.5), CP-2."""

    async def test_capacity_eviction_disposes_oldest(self, mock_cli_manager):
        """Suspending N+1 scopes evicts the oldest one."""
        max_suspended = 3
        config = _make_config(grace_period=600, max_suspended=max_suspended)
        sm = ScopeManager(config=config, cli_manager=mock_cli_manager)
        sm.register_strategy(TunnelIdentityStrategy())

        # Register and unregister 4 clients with different identities
        scopes = []
        for i in range(4):
            result = await sm.register_client(
                f"client-{i}",
                ConnectionMode.TUNNEL,
                {"bearer_token": f"token-{i}"},
            )
            scopes.append(result.scope)
            await sm.unregister_client(f"client-{i}")
            # Small delay to ensure different suspended_at timestamps
            await asyncio.sleep(0.01)

        # Capacity enforced: only max_suspended remain
        assert sm.suspended_count == max_suspended

        # First scope (oldest) should be disposed
        assert scopes[0]._disposed is True

        # Remaining scopes should still be alive (not disposed)
        for scope in scopes[1:]:
            assert scope._disposed is False

    async def test_capacity_eviction_multiple_over_limit(self, mock_cli_manager):
        """Suspending many scopes over limit evicts all excess."""
        max_suspended = 2
        config = _make_config(grace_period=600, max_suspended=max_suspended)
        sm = ScopeManager(config=config, cli_manager=mock_cli_manager)
        sm.register_strategy(RelayIdentityStrategy())

        scopes = []
        for i in range(5):
            result = await sm.register_client(
                f"client-{i}",
                ConnectionMode.RELAY,
                {"device_id": f"device-{i}"},
            )
            scopes.append(result.scope)
            await sm.unregister_client(f"client-{i}")
            await asyncio.sleep(0.01)

        assert sm.suspended_count == max_suspended

        # First 3 scopes (oldest) should be disposed
        for scope in scopes[:3]:
            assert scope._disposed is True

        # Last 2 should still be alive
        for scope in scopes[3:]:
            assert scope._disposed is False


# ---------------------------------------------------------------------------
# 6.4 Grace period expiry — disconnect, wait > grace period, verify disposed
# ---------------------------------------------------------------------------


class TestGracePeriodExpiry:
    """Validates: FR-6 (AC-6.1 through AC-6.5)."""

    async def test_grace_period_expiry_disposes_scope(self, mock_cli_manager):
        """After grace period expires, scope is disposed."""
        # Use a very short grace period for fast test (50ms)
        config = _make_config(grace_period=0.05)
        sm = ScopeManager(config=config, cli_manager=mock_cli_manager)
        sm.register_strategy(TunnelIdentityStrategy())

        result = await sm.register_client(
            "client-1", ConnectionMode.TUNNEL, {"bearer_token": "my-token"}
        )
        scope = result.scope

        # Disconnect — starts grace timer
        await sm.unregister_client("client-1")
        assert sm.suspended_count == 1
        assert scope._disposed is False

        # Wait for grace period to expire (100ms > 50ms grace)
        await asyncio.sleep(0.15)

        # Scope should now be disposed
        assert sm.suspended_count == 0
        assert scope._disposed is True

    async def test_grace_period_zero_disposes_immediately(self, mock_cli_manager):
        """Setting grace_period=0 disposes scope immediately on disconnect."""
        config = _make_config(grace_period=0)
        sm = ScopeManager(config=config, cli_manager=mock_cli_manager)
        sm.register_strategy(TunnelIdentityStrategy())

        result = await sm.register_client(
            "client-1", ConnectionMode.TUNNEL, {"bearer_token": "my-token"}
        )
        scope = result.scope

        await sm.unregister_client("client-1")

        # Immediately disposed, never suspended
        assert sm.suspended_count == 0
        assert scope._disposed is True

    async def test_reconnect_before_grace_expiry_cancels_timer(
        self, mock_cli_manager
    ):
        """Reconnecting before grace period expires cancels the timer."""
        config = _make_config(grace_period=0.5)
        sm = ScopeManager(config=config, cli_manager=mock_cli_manager)
        sm.register_strategy(TunnelIdentityStrategy())

        result1 = await sm.register_client(
            "client-1", ConnectionMode.TUNNEL, {"bearer_token": "my-token"}
        )
        scope = result1.scope

        await sm.unregister_client("client-1")
        assert sm.suspended_count == 1

        # Reconnect quickly (before 500ms grace expires)
        result2 = await sm.register_client(
            "client-2", ConnectionMode.TUNNEL, {"bearer_token": "my-token"}
        )
        assert result2.resumed is True
        assert result2.scope is scope

        # Wait past the original grace period — scope should NOT be disposed
        await asyncio.sleep(0.6)
        assert scope._disposed is False
        assert sm.active_count == 1


# ---------------------------------------------------------------------------
# 6.5 Property test: capacity invariant
# ---------------------------------------------------------------------------


class TestCapacityInvariantProperty:
    """Validates: CP-2 — suspended_count <= max_suspended_scopes for any operation sequence.

    **Validates: Requirements FR-5, CP-2**
    """

    @given(
        operations=st.lists(
            st.tuples(
                st.sampled_from(["register", "unregister"]),
                st.integers(min_value=0, max_value=19),
            ),
            min_size=1,
            max_size=50,
        )
    )
    @settings(max_examples=200)
    async def test_capacity_invariant_property(self, operations):
        """For any sequence of register/unregister, suspended_count <= max_suspended_scopes."""
        max_suspended = 5
        config = _make_config(grace_period=600, max_suspended=max_suspended)
        cli_manager = MagicMock()
        cli_manager.remap_client = MagicMock()
        cli_manager.cleanup_sessions = MagicMock()

        sm = ScopeManager(config=config, cli_manager=cli_manager)
        sm.register_strategy(TunnelIdentityStrategy())

        # Track which client_ids are currently active (registered but not unregistered)
        active_clients: set[int] = set()

        for op, client_idx in operations:
            client_id = f"client-{client_idx}"
            bearer_token = f"token-{client_idx}"

            if op == "register" and client_idx not in active_clients:
                await sm.register_client(
                    client_id,
                    ConnectionMode.TUNNEL,
                    {"bearer_token": bearer_token},
                )
                active_clients.add(client_idx)
            elif op == "unregister" and client_idx in active_clients:
                await sm.unregister_client(client_id)
                active_clients.discard(client_idx)

            # Invariant: suspended count never exceeds max
            assert sm.suspended_count <= max_suspended, (
                f"Invariant violated: suspended_count={sm.suspended_count} > "
                f"max_suspended_scopes={max_suspended} after {op}({client_id})"
            )
