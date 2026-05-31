"""Scope remap chain test — verifies multi-reconnect scope recovery.

Reproduces the real bug: after the first reconnect, verify_session returns
the ORIGINAL client_id (from session creation), but the suspended scope
is stored under the REMAPPED client_id. Without updating the session's
client_id after remap, the second reconnect fails to find the scope.

Timeline of the bug:
  1. Client A connects → scope stored as _scopes["A"]
  2. Client A disconnects → scope moved to _suspended["A"]
  3. Client B reconnects → verify_session returns client_id="A"
     → _try_resume("A") succeeds → scope remapped to _scopes["B"]
     → _suspended is now empty
  4. Client B disconnects → scope moved to _suspended["B"]
  5. Client C reconnects → verify_session STILL returns client_id="A"
     → _try_resume("A") fails (not in _suspended, it's under "B")
     → scope NOT recovered ← BUG

Fix: after step 3, update auth_sessions so verify_session returns "B"
for the next reconnect. Then step 5 finds _suspended["B"] correctly.

# Feature: scope-remap-chain-fix
"""

from __future__ import annotations

import os
import time

import pytest

from mobileflow_agent.core.config import AgentConfig
from mobileflow_agent.server.auth import AuthManager, SessionVerifyResult


class TestSessionClientIdUpdate:
    """Verify update_session_client keeps session → client_id in sync."""

    def test_update_changes_client_id(self):
        """After update, verify_session returns the new client_id."""
        config = AgentConfig(security={"session_timeout": 3600})
        auth = AuthManager(config)
        secret = os.urandom(32)

        # Create session with original client_id
        token = auth.create_session("client-A", secret)
        result = auth.verify_session(token)
        assert result.client_id == "client-A"

        # Simulate remap after reconnect
        auth.update_session_client(token, "client-B")
        result = auth.verify_session(token)
        assert result.client_id == "client-B"

        # Second remap
        auth.update_session_client(token, "client-C")
        result = auth.verify_session(token)
        assert result.client_id == "client-C"

    def test_update_preserves_expiry(self):
        """update_session_client doesn't change the expiry time."""
        config = AgentConfig(security={"session_timeout": 3600})
        auth = AuthManager(config)
        secret = os.urandom(32)

        token = auth.create_session("client-A", secret)
        _, original_expiry = auth._sessions[token]

        auth.update_session_client(token, "client-B")
        _, new_expiry = auth._sessions[token]

        assert original_expiry == new_expiry

    def test_update_preserves_secret(self):
        """update_session_client doesn't affect the encryption secret."""
        config = AgentConfig(security={"session_timeout": 3600})
        auth = AuthManager(config)
        secret = os.urandom(32)

        token = auth.create_session("client-A", secret)
        auth.update_session_client(token, "client-B")

        result = auth.verify_session(token)
        assert result.secret == secret

    def test_update_nonexistent_token_is_noop(self):
        """Updating a non-existent token does nothing (no crash)."""
        config = AgentConfig(security={"session_timeout": 3600})
        auth = AuthManager(config)

        # Should not raise
        auth.update_session_client("nonexistent-token", "client-X")


class TestMultiReconnectChain:
    """Simulate the exact real-world scenario from the bug report:
    connect → disconnect → reconnect → disconnect → reconnect.

    Each reconnect must find the suspended scope from the previous
    disconnect, regardless of how many times the client_id has changed.
    """

    def test_three_reconnect_chain(self):
        """Session client_id tracks through 3 reconnect cycles."""
        config = AgentConfig(security={"session_timeout": 3600})
        auth = AuthManager(config)
        secret = os.urandom(32)

        # Initial connection: client-A
        token = auth.create_session("client-A", secret)

        # Reconnect 1: client-B connects, verify returns "client-A"
        result = auth.verify_session(token)
        assert result.success
        assert result.client_id == "client-A"
        # After scope remap, update session
        auth.update_session_client(token, "client-B")

        # Reconnect 2: client-C connects, verify should return "client-B"
        result = auth.verify_session(token)
        assert result.success
        assert result.client_id == "client-B"  # ← This was "client-A" before the fix
        auth.update_session_client(token, "client-C")

        # Reconnect 3: client-D connects, verify should return "client-C"
        result = auth.verify_session(token)
        assert result.success
        assert result.client_id == "client-C"
        auth.update_session_client(token, "client-D")

        # Final verify
        result = auth.verify_session(token)
        assert result.client_id == "client-D"
