"""Unit tests for core/identity_resolver.py — identity resolution strategies.

Tests cover:
    - ClientIdentity dataclass (frozen, hashable, fields)
    - LANIdentityStrategy: valid token, invalid token, missing token, exception
    - TunnelIdentityStrategy: valid token, empty token, deterministic hash
    - RelayIdentityStrategy: valid device_id, empty device_id
    - All strategies return None on failure (never raise)
    - Property test: identity resolution is deterministic
"""

from __future__ import annotations

import hashlib
from unittest.mock import MagicMock, PropertyMock

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from mobileflow_agent.core.identity_resolver import (
    ClientIdentity,
    IdentityStrategy,
    LANIdentityStrategy,
    RelayIdentityStrategy,
    TunnelIdentityStrategy,
)
from mobileflow_agent.server.connection_manager import ConnectionMode


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_auth_manager():
    """Create a mock AuthManager with verify_session method."""
    auth = MagicMock()
    return auth


@pytest.fixture
def lan_strategy(mock_auth_manager):
    """Create a LANIdentityStrategy with mock AuthManager."""
    return LANIdentityStrategy(auth_manager=mock_auth_manager)


@pytest.fixture
def tunnel_strategy():
    """Create a TunnelIdentityStrategy."""
    return TunnelIdentityStrategy()


@pytest.fixture
def relay_strategy():
    """Create a RelayIdentityStrategy."""
    return RelayIdentityStrategy()


def _make_session_result(success: bool, client_id: str = "", error_code=None):
    """Helper to create a mock SessionVerifyResult."""
    result = MagicMock()
    result.success = success
    result.client_id = client_id
    result.error_code = error_code
    result.secret = b"fake-secret" if success else None
    return result


# ---------------------------------------------------------------------------
# ClientIdentity dataclass
# ---------------------------------------------------------------------------


class TestClientIdentity:
    """Test the ClientIdentity frozen dataclass."""

    def test_basic_creation(self):
        identity = ClientIdentity(stable_id="abc123", mode=ConnectionMode.LAN)
        assert identity.stable_id == "abc123"
        assert identity.mode == ConnectionMode.LAN
        assert identity.metadata is None

    def test_with_metadata(self):
        identity = ClientIdentity(
            stable_id="dev-001",
            mode=ConnectionMode.RELAY,
            metadata={"device_name": "iPhone 15"},
        )
        assert identity.metadata == {"device_name": "iPhone 15"}

    def test_frozen_immutable(self):
        """Frozen dataclass prevents attribute modification."""
        identity = ClientIdentity(stable_id="abc", mode=ConnectionMode.LAN)
        with pytest.raises(AttributeError):
            identity.stable_id = "xyz"  # type: ignore

    def test_equality(self):
        """Two identities with same fields are equal."""
        id1 = ClientIdentity(stable_id="abc", mode=ConnectionMode.TUNNEL)
        id2 = ClientIdentity(stable_id="abc", mode=ConnectionMode.TUNNEL)
        assert id1 == id2

    def test_inequality_different_stable_id(self):
        id1 = ClientIdentity(stable_id="abc", mode=ConnectionMode.LAN)
        id2 = ClientIdentity(stable_id="xyz", mode=ConnectionMode.LAN)
        assert id1 != id2

    def test_inequality_different_mode(self):
        id1 = ClientIdentity(stable_id="abc", mode=ConnectionMode.LAN)
        id2 = ClientIdentity(stable_id="abc", mode=ConnectionMode.TUNNEL)
        assert id1 != id2

    def test_hashable(self):
        """Frozen dataclass is hashable — can be used as dict key."""
        identity = ClientIdentity(stable_id="abc", mode=ConnectionMode.LAN)
        d = {identity: "value"}
        assert d[identity] == "value"


# ---------------------------------------------------------------------------
# LANIdentityStrategy
# ---------------------------------------------------------------------------


class TestLANIdentityStrategy:
    """Test LANIdentityStrategy using AuthManager.verify_session()."""

    def test_mode_property(self, lan_strategy):
        assert lan_strategy.mode == ConnectionMode.LAN

    def test_valid_session_token(self, lan_strategy, mock_auth_manager):
        """Valid session token resolves to original client_id."""
        mock_auth_manager.verify_session.return_value = _make_session_result(
            success=True, client_id="original-client-42"
        )
        result = lan_strategy.resolve({"session_token": "valid-token-abc"})

        assert result is not None
        assert result.stable_id == "original-client-42"
        assert result.mode == ConnectionMode.LAN
        mock_auth_manager.verify_session.assert_called_once_with("valid-token-abc")

    def test_invalid_session_token(self, lan_strategy, mock_auth_manager):
        """Invalid/expired session token returns None."""
        mock_auth_manager.verify_session.return_value = _make_session_result(
            success=False, error_code="token_not_found"
        )
        result = lan_strategy.resolve({"session_token": "bad-token"})
        assert result is None

    def test_expired_session_token(self, lan_strategy, mock_auth_manager):
        """Expired session token returns None."""
        mock_auth_manager.verify_session.return_value = _make_session_result(
            success=False, error_code="session_expired", client_id="old-client"
        )
        result = lan_strategy.resolve({"session_token": "expired-token"})
        assert result is None

    def test_empty_session_token(self, lan_strategy, mock_auth_manager):
        """Empty session token returns None without calling verify_session."""
        result = lan_strategy.resolve({"session_token": ""})
        assert result is None
        mock_auth_manager.verify_session.assert_not_called()

    def test_missing_session_token_key(self, lan_strategy, mock_auth_manager):
        """Missing session_token key returns None."""
        result = lan_strategy.resolve({})
        assert result is None
        mock_auth_manager.verify_session.assert_not_called()

    def test_verify_session_raises_exception(self, lan_strategy, mock_auth_manager):
        """Exception in verify_session returns None (never propagates)."""
        mock_auth_manager.verify_session.side_effect = RuntimeError("DB error")
        result = lan_strategy.resolve({"session_token": "some-token"})
        assert result is None

    def test_is_identity_strategy(self, lan_strategy):
        """LANIdentityStrategy implements IdentityStrategy ABC."""
        assert isinstance(lan_strategy, IdentityStrategy)


# ---------------------------------------------------------------------------
# TunnelIdentityStrategy
# ---------------------------------------------------------------------------


class TestTunnelIdentityStrategy:
    """Test TunnelIdentityStrategy using SHA-256 hash of bearer token."""

    def test_mode_property(self, tunnel_strategy):
        assert tunnel_strategy.mode == ConnectionMode.TUNNEL

    def test_valid_bearer_token(self, tunnel_strategy):
        """Valid bearer token produces SHA-256 hash as stable_id."""
        token = "my-secret-bearer-token"
        expected_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()

        result = tunnel_strategy.resolve({"bearer_token": token})

        assert result is not None
        assert result.stable_id == expected_hash
        assert result.mode == ConnectionMode.TUNNEL

    def test_empty_bearer_token(self, tunnel_strategy):
        """Empty bearer token returns None."""
        result = tunnel_strategy.resolve({"bearer_token": ""})
        assert result is None

    def test_missing_bearer_token_key(self, tunnel_strategy):
        """Missing bearer_token key returns None."""
        result = tunnel_strategy.resolve({})
        assert result is None

    def test_deterministic_hash(self, tunnel_strategy):
        """Same bearer token always produces the same stable_id."""
        token = "consistent-token-value"
        result1 = tunnel_strategy.resolve({"bearer_token": token})
        result2 = tunnel_strategy.resolve({"bearer_token": token})
        assert result1 == result2

    def test_different_tokens_different_ids(self, tunnel_strategy):
        """Different bearer tokens produce different stable_ids."""
        result1 = tunnel_strategy.resolve({"bearer_token": "token-a"})
        result2 = tunnel_strategy.resolve({"bearer_token": "token-b"})
        assert result1 is not None
        assert result2 is not None
        assert result1.stable_id != result2.stable_id

    def test_hash_is_64_hex_chars(self, tunnel_strategy):
        """SHA-256 hex digest is always 64 characters."""
        result = tunnel_strategy.resolve({"bearer_token": "any-token"})
        assert result is not None
        assert len(result.stable_id) == 64
        # All hex characters
        assert all(c in "0123456789abcdef" for c in result.stable_id)

    def test_is_identity_strategy(self, tunnel_strategy):
        """TunnelIdentityStrategy implements IdentityStrategy ABC."""
        assert isinstance(tunnel_strategy, IdentityStrategy)


# ---------------------------------------------------------------------------
# RelayIdentityStrategy
# ---------------------------------------------------------------------------


class TestRelayIdentityStrategy:
    """Test RelayIdentityStrategy using device_id as stable_id."""

    def test_mode_property(self, relay_strategy):
        assert relay_strategy.mode == ConnectionMode.RELAY

    def test_valid_device_id(self, relay_strategy):
        """Valid device_id is used directly as stable_id."""
        result = relay_strategy.resolve({"device_id": "device-abc-123"})

        assert result is not None
        assert result.stable_id == "device-abc-123"
        assert result.mode == ConnectionMode.RELAY

    def test_empty_device_id(self, relay_strategy):
        """Empty device_id returns None."""
        result = relay_strategy.resolve({"device_id": ""})
        assert result is None

    def test_missing_device_id_key(self, relay_strategy):
        """Missing device_id key returns None."""
        result = relay_strategy.resolve({})
        assert result is None

    def test_deterministic(self, relay_strategy):
        """Same device_id always produces the same identity."""
        result1 = relay_strategy.resolve({"device_id": "my-device"})
        result2 = relay_strategy.resolve({"device_id": "my-device"})
        assert result1 == result2

    def test_is_identity_strategy(self, relay_strategy):
        """RelayIdentityStrategy implements IdentityStrategy ABC."""
        assert isinstance(relay_strategy, IdentityStrategy)


# ---------------------------------------------------------------------------
# Property-based test: identity resolution is deterministic
# ---------------------------------------------------------------------------


class TestIdentityDeterminism:
    """Property test: same input always produces the same output.

    **Validates: Requirements CP-3, AC-2.4**
    """

    @given(token=st.text(min_size=1, max_size=200))
    @settings(max_examples=100)
    def test_tunnel_deterministic(self, token: str):
        """For any non-empty bearer token, resolve() is deterministic."""
        strategy = TunnelIdentityStrategy()
        result1 = strategy.resolve({"bearer_token": token})
        result2 = strategy.resolve({"bearer_token": token})
        assert result1 == result2

    @given(device_id=st.text(min_size=1, max_size=200))
    @settings(max_examples=100)
    def test_relay_deterministic(self, device_id: str):
        """For any non-empty device_id, resolve() is deterministic."""
        strategy = RelayIdentityStrategy()
        result1 = strategy.resolve({"device_id": device_id})
        result2 = strategy.resolve({"device_id": device_id})
        assert result1 == result2

    @given(token=st.text(min_size=1, max_size=200))
    @settings(max_examples=100)
    def test_lan_deterministic(self, token: str):
        """For any non-empty session token with successful verification,
        resolve() is deterministic."""
        auth = MagicMock()
        auth.verify_session.return_value = _make_session_result(
            success=True, client_id="stable-client-id"
        )
        strategy = LANIdentityStrategy(auth_manager=auth)
        result1 = strategy.resolve({"session_token": token})
        result2 = strategy.resolve({"session_token": token})
        assert result1 == result2
