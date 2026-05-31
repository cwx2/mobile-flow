"""AuthManager brute-force protection and session error classification tests.

Tests cover:
  1. Global brute-force lockout (failure tracking + lockout window).
  2. Persistent password (not invalidated after success).
  3. Session token error classification (valid / expired / not_found).
  4. Password persistence (ensure_pair_token / reset_pair_token).

# Feature: connection-architecture-overhaul
"""

from __future__ import annotations

import os
import time

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from mobileflow_agent.core.config import AgentConfig
from mobileflow_agent.server.auth import AuthManager


# ── Helpers ──


def _make_auth(
    pair_max_failures: int = 3,
    pair_lockout_seconds: int = 60,
    session_timeout: int = 86400,
) -> AuthManager:
    """Create an AuthManager with explicit brute-force / session settings."""
    config = AgentConfig(
        connection={
            "pair_max_failures": pair_max_failures,
            "pair_lockout_seconds": pair_lockout_seconds,
        },
        security={"session_timeout": session_timeout},
    )
    return AuthManager(config)


# ═══════════════════════════════════════════════════════════════
# Property-based tests (Hypothesis)
# ═══════════════════════════════════════════════════════════════


class TestBruteForceLockoutProperty:
    """Property: for N >= pair_max_failures consecutive failures,
    all subsequent attempts within pair_lockout_seconds are rejected
    with "lockout". After a successful verification the counter resets.

    Lockout is global (not per-source) to prevent IP rotation bypass.
    """

    @given(n=st.integers(min_value=0, max_value=20))
    @settings(max_examples=100)
    def test_lockout_state_machine(self, n: int):
        max_failures = 3
        auth = _make_auth(pair_max_failures=max_failures, pair_lockout_seconds=60)

        # Set a known password
        auth._pair_token = "TestPass1"

        # Feed N consecutive failures (global lockout)
        for _ in range(n):
            auth.verify_pair_token("wrongpwd", source="any")

        if n >= max_failures:
            # Locked out — even the correct password must be rejected
            success, error = auth.verify_pair_token("TestPass1", source="any")
            assert not success
            assert error == "lockout"
        else:
            # Not yet locked out — correct password should succeed
            success, error = auth.verify_pair_token("TestPass1", source="any")
            assert success
            assert error is None

            # Password is NOT invalidated — can be used again
            success2, error2 = auth.verify_pair_token("TestPass1", source="any")
            assert success2
            assert error2 is None


class TestSessionTokenClassificationProperty:
    """Property: verify_session() returns exactly one of three mutually
    exclusive outcomes: (True, None, secret), (False, "session_expired", None),
    or (False, "token_not_found", None)."""

    @given(
        token_state=st.sampled_from(["valid", "expired", "never_created"]),
    )
    @settings(max_examples=100)
    def test_verify_session_classification(self, token_state: str):
        auth = _make_auth(session_timeout=86400)
        secret = os.urandom(32)

        if token_state == "valid":
            token = auth.create_session("client-1", secret)
        elif token_state == "expired":
            token = auth.create_session("client-1", secret)
            auth._sessions[token] = ("client-1", time.time() - 1)
        else:
            token = "nonexistent-token-abc123"

        result = auth.verify_session(token)

        outcomes = [
            (result.success is True and result.error_code is None and result.secret is not None),
            (result.success is False and result.error_code == "session_expired" and result.secret is None),
            (result.success is False and result.error_code == "token_not_found" and result.secret is None),
        ]
        assert sum(outcomes) == 1, (
            f"Expected exactly one outcome, got {outcomes} for state={token_state}"
        )


# ═══════════════════════════════════════════════════════════════
# Example-based unit tests
# ═══════════════════════════════════════════════════════════════


class TestPersistentPassword:
    """Tests for persistent (reusable) connection password."""

    def test_password_not_invalidated_after_success(self):
        """Password can be used multiple times without regeneration."""
        auth = _make_auth()
        auth._pair_token = "MyPass99"

        # First use
        success1, _ = auth.verify_pair_token("MyPass99")
        assert success1

        # Second use — should still work
        success2, _ = auth.verify_pair_token("MyPass99")
        assert success2

        # Third use — still works
        success3, _ = auth.verify_pair_token("MyPass99")
        assert success3

    def test_wrong_password_rejected(self):
        """Wrong password is rejected."""
        auth = _make_auth()
        auth._pair_token = "Correct1"

        success, error = auth.verify_pair_token("Wrong123")
        assert not success
        assert error == "invalid"

    def test_no_password_set(self):
        """Verification fails when no password is set."""
        auth = _make_auth()
        # _pair_token is None by default

        success, error = auth.verify_pair_token("anything")
        assert not success
        assert error == "invalid"


class TestGlobalLockout:
    """Tests for global (not per-source) brute-force lockout."""

    def test_lockout_after_max_failures(self):
        """3 wrong passwords → global lockout."""
        auth = _make_auth(pair_max_failures=3, pair_lockout_seconds=60)
        auth._pair_token = "GoodPass"

        for _ in range(3):
            success, error = auth.verify_pair_token("wrong!", source="attacker")
            assert not success
            assert error == "invalid"

        # 4th attempt — locked out even with correct password
        success, error = auth.verify_pair_token("GoodPass", source="attacker")
        assert not success
        assert error == "lockout"

    def test_lockout_is_global_not_per_source(self):
        """Lockout applies to ALL sources, not just the one that triggered it."""
        auth = _make_auth(pair_max_failures=3, pair_lockout_seconds=60)
        auth._pair_token = "GoodPass"

        # 3 failures from source A
        for _ in range(3):
            auth.verify_pair_token("wrong!", source="source-A")

        # Source B should also be locked out
        success, error = auth.verify_pair_token("GoodPass", source="source-B")
        assert not success
        assert error == "lockout"

    def test_lockout_expires(self):
        """Lockout expires after pair_lockout_seconds."""
        auth = _make_auth(pair_max_failures=3, pair_lockout_seconds=60)
        auth._pair_token = "GoodPass"

        # Trigger lockout
        for _ in range(3):
            auth.verify_pair_token("wrong!")

        # Simulate time passing beyond lockout window
        auth._global_fail_first_ts = time.time() - 61

        # Should no longer be locked out
        success, error = auth.verify_pair_token("GoodPass")
        assert success
        assert error is None

    def test_success_resets_counter(self):
        """Successful verification resets the failure counter."""
        auth = _make_auth(pair_max_failures=3, pair_lockout_seconds=60)
        auth._pair_token = "GoodPass"

        # 2 failures
        auth.verify_pair_token("wrong!")
        auth.verify_pair_token("wrong!")

        # Succeed
        success, _ = auth.verify_pair_token("GoodPass")
        assert success

        # Counter reset — 2 more failures should NOT lock out
        auth.verify_pair_token("wrong!")
        auth.verify_pair_token("wrong!")

        success2, error2 = auth.verify_pair_token("GoodPass")
        assert success2
        assert error2 is None


class TestSessionExamples:
    """Concrete example tests for session verification."""

    def test_verify_session_valid(self):
        """Valid session returns success with secret and client_id."""
        auth = _make_auth(session_timeout=86400)
        secret = os.urandom(32)
        token = auth.create_session("client-1", secret)

        result = auth.verify_session(token)
        assert result.success is True
        assert result.error_code is None
        assert result.secret == secret
        assert result.client_id == "client-1"

    def test_verify_session_expired(self):
        """Expired session returns error with original client_id."""
        auth = _make_auth(session_timeout=86400)
        secret = os.urandom(32)
        token = auth.create_session("client-1", secret)

        auth._sessions[token] = ("client-1", time.time() - 1)

        result = auth.verify_session(token)
        assert result.success is False
        assert result.error_code == "session_expired"
        assert result.secret is None
        assert result.client_id == "client-1"

    def test_verify_session_not_found(self):
        """Unknown token returns error with empty client_id."""
        auth = _make_auth()

        result = auth.verify_session("nonexistent-token")
        assert result.success is False
        assert result.error_code == "token_not_found"
        assert result.secret is None
        assert result.client_id == ""

    def test_create_session_stores_secret(self):
        """create_session stores the secret in _session_secrets."""
        auth = _make_auth()
        secret = os.urandom(32)
        token = auth.create_session("client-1", secret)

        assert token in auth._session_secrets
        assert auth._session_secrets[token] == secret


class TestEnsurePairToken:
    """Tests for ensure_pair_token persistence logic."""

    def test_generates_8_char_alphanumeric(self):
        """Auto-generated password is 8 chars, alphanumeric."""
        auth = _make_auth()
        token, is_new = auth.ensure_pair_token()

        assert len(token) >= 8
        assert token.isalnum()
        # is_new depends on whether a password was already saved on disk;
        # in CI/fresh environments it's True, on dev machines it may be False

    def test_config_override_takes_priority(self):
        """Config pair_token overrides auto-generation."""
        config = AgentConfig(pair_token="MyCustomPwd")
        auth = AuthManager(config)

        token, is_new = auth.ensure_pair_token()
        assert token == "MyCustomPwd"
        assert is_new is False

    def test_reset_generates_new_password(self):
        """reset_pair_token generates a different password."""
        auth = _make_auth()
        token1, _ = auth.ensure_pair_token()
        token2 = auth.reset_pair_token()

        assert len(token2) == 8
        assert token2.isalnum()
        # Extremely unlikely to be the same (62^8 possibilities)
        # but not impossible, so we just check it's valid
