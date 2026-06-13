"""Disconnect grace period tests.

Tests cover:
  1. ClientScope.reset() — clears cancelled state for scope reuse.
  2. AuthManager.verify_session() — 4-tuple return with client_id.
  3. CLIManager.remap_client() — session state migration between client_ids.
  4. Grace period config — default value and override.

# Feature: disconnect-grace-period
"""

from __future__ import annotations

import asyncio
import os
import time

import pytest

from mobileflow_agent.core.client_scope import ClientScope
from mobileflow_agent.core.config import AgentConfig
from mobileflow_agent.server.auth import AuthManager


# ── Helpers ──


def _make_auth(session_timeout: int = 86400) -> AuthManager:
    """Create an AuthManager with explicit session timeout."""
    config = AgentConfig(
        security={"session_timeout": session_timeout},
    )
    return AuthManager(config)


# ═══════════════════════════════════════════════════════════════
# ClientScope.reset()
# ═══════════════════════════════════════════════════════════════


class TestClientScopeReset:
    """ClientScope.reset() clears the cancelled event so a suspended
    scope can be reused after a client reconnects."""

    def test_reset_clears_cancelled(self):
        scope = ClientScope("test-client")
        scope.cancelled.set()
        assert scope.cancelled.is_set()
        scope.reset()
        assert not scope.cancelled.is_set()

    def test_reset_keeps_alive(self):
        scope = ClientScope("test-client")
        scope.cancelled.set()
        scope.reset()
        assert scope.is_alive

    def test_reset_noop_after_dispose(self):
        """reset() is a no-op if dispose() has already run."""
        scope = ClientScope("test-client")
        # Simulate dispose by setting _disposed directly
        scope._disposed = True
        scope.cancelled.set()
        scope.reset()
        # cancelled should still be set — reset was a no-op
        assert scope.cancelled.is_set()

    def test_cleanups_survive_reset(self):
        """Cleanup functions registered before suspend survive reset."""
        scope = ClientScope("test-client")
        called = []
        scope.on_dispose(lambda: called.append("cleanup"))
        scope.cancelled.set()
        scope.reset()
        # Cleanups should still be registered
        assert len(scope._cleanups) == 1

    @pytest.mark.asyncio
    async def test_dispose_after_reset(self):
        """Cleanups run correctly after reset + dispose cycle."""
        scope = ClientScope("test-client")
        called = []
        scope.on_dispose(lambda: called.append("cleanup"))
        # Simulate suspend → resume → disconnect
        scope.cancelled.set()
        scope.reset()
        await scope.dispose()
        assert called == ["cleanup"]


# ═══════════════════════════════════════════════════════════════
# AuthManager.verify_session() — 4-tuple return
# ═══════════════════════════════════════════════════════════════


class TestVerifySessionClientId:
    """verify_session() returns the original client_id as the 4th element."""

    def test_valid_session_returns_client_id(self):
        auth = _make_auth()
        secret = os.urandom(32)
        token = auth.create_session("client-abc", secret)
        success, error, returned_secret, client_id = auth.verify_session(token)
        assert success is True
        assert client_id == "client-abc"

    def test_expired_session_returns_client_id(self):
        """Even expired sessions return the client_id for grace period lookup."""
        auth = _make_auth()
        secret = os.urandom(32)
        token = auth.create_session("client-xyz", secret)
        # Force expiry
        auth._sessions[token] = ("client-xyz", time.time() - 1)
        success, error, returned_secret, client_id = auth.verify_session(token)
        assert success is False
        assert error == "session_expired"
        assert client_id == "client-xyz"

    def test_not_found_returns_empty_client_id(self):
        auth = _make_auth()
        success, error, returned_secret, client_id = auth.verify_session("nonexistent")
        assert success is False
        assert error == "token_not_found"
        assert client_id == ""


# ═══════════════════════════════════════════════════════════════
# CLIManager.remap_client()
# ═══════════════════════════════════════════════════════════════


class TestRemapClient:
    """remap_client() migrates all session state from old to new client_id."""

    def _make_cli_manager(self):
        """Create a minimal CLIManager with mocked internals."""
        from unittest.mock import MagicMock
        config = AgentConfig()
        from mobileflow_agent.services.cli_manager import CLIManager
        mgr = CLIManager(config)
        return mgr

    def test_remap_sessions(self):
        mgr = self._make_cli_manager()
        mock_provider = object()
        old_key = ("old-client", "kiro")
        mgr._sessions[old_key] = mock_provider
        mgr._session_ids[old_key] = "session-123"
        mgr._history_cache[old_key] = [{"role": "user", "content": "hi"}]

        mgr.remap_client("old-client", "new-client")

        new_key = ("new-client", "kiro")
        assert new_key in mgr._sessions
        assert mgr._sessions[new_key] is mock_provider
        assert mgr._session_ids[new_key] == "session-123"
        assert mgr._history_cache[new_key] == [{"role": "user", "content": "hi"}]
        # Old keys should be gone
        assert old_key not in mgr._sessions
        assert old_key not in mgr._session_ids

    def test_remap_background_tasks(self):
        mgr = self._make_cli_manager()
        mock_task = object()
        mgr._background_tasks["old-client"] = [mock_task]

        mgr.remap_client("old-client", "new-client")

        assert "new-client" in mgr._background_tasks
        assert mgr._background_tasks["new-client"] == [mock_task]
        assert "old-client" not in mgr._background_tasks

    def test_remap_multiple_clis(self):
        """Remaps all CLIs for the same client_id."""
        mgr = self._make_cli_manager()
        mgr._sessions[("old", "kiro")] = "provider-kiro"
        mgr._sessions[("old", "claude")] = "provider-claude"
        mgr._sessions[("other", "kiro")] = "provider-other"

        mgr.remap_client("old", "new")

        assert ("new", "kiro") in mgr._sessions
        assert ("new", "claude") in mgr._sessions
        # Other client's sessions untouched
        assert ("other", "kiro") in mgr._sessions
        assert ("old", "kiro") not in mgr._sessions

    def test_remap_noop_when_no_sessions(self):
        """No crash when old_client_id has no sessions."""
        mgr = self._make_cli_manager()
        mgr.remap_client("nonexistent", "new-client")
        assert len(mgr._sessions) == 0


# ═══════════════════════════════════════════════════════════════
# Grace period config
# ═══════════════════════════════════════════════════════════════


class TestGracePeriodConfig:
    """disconnect_grace_period config is correctly loaded."""

    def test_default_value(self):
        config = AgentConfig()
        assert config.connection.disconnect_grace_period == -1

    def test_override(self):
        config = AgentConfig(connection={"disconnect_grace_period": 0})
        assert config.connection.disconnect_grace_period == 0

    def test_custom_value(self):
        config = AgentConfig(connection={"disconnect_grace_period": 1800})
        assert config.connection.disconnect_grace_period == 1800

    def test_never_expire(self):
        config = AgentConfig(connection={"disconnect_grace_period": -1})
        assert config.connection.disconnect_grace_period == -1
