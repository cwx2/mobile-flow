"""Unit tests for UserConfigManager, ConnectionConfigValidator, and mask_token.

Tests cover:
- UserConfigManager: load, save, missing file, malformed JSON, round-trip
- ConnectionConfigValidator: valid configs, invalid paths, invalid URL, port range
- mask_token: various lengths, edge cases
"""

import json
import pytest
from pathlib import Path

from mobileflow_agent.services.user_config import (
    ConnectionConfigData,
    ConnectionConfigValidator,
    UserConfigManager,
    mask_token,
)


class TestMaskToken:
    """Tests for the mask_token utility function."""

    def test_empty_string(self):
        assert mask_token("") == ""

    def test_short_token_returned_as_is(self):
        assert mask_token("abc") == "abc"
        assert mask_token("abcd") == "abcd"

    def test_five_chars_masks_first(self):
        assert mask_token("12345") == "*2345"

    def test_long_token_masks_all_but_last_4(self):
        result = mask_token("my-secret-token-value")
        assert result.endswith("alue")
        assert result.startswith("*")
        assert len(result) == len("my-secret-token-value")

    def test_preserves_length(self):
        token = "abcdefghijklmnop"
        result = mask_token(token)
        assert len(result) == len(token)
        assert result[-4:] == "mnop"


class TestConnectionConfigValidator:
    """Tests for ConnectionConfigValidator.validate()."""

    def test_empty_config_is_valid(self):
        config = ConnectionConfigData()
        errors = ConnectionConfigValidator.validate(config)
        assert errors == {}

    def test_valid_relay_url(self):
        config = ConnectionConfigData(relay_url="wss://relay.example.com")
        errors = ConnectionConfigValidator.validate(config)
        assert errors == {}

    def test_valid_relay_url_ws(self):
        config = ConnectionConfigData(relay_url="ws://localhost:3005")
        errors = ConnectionConfigValidator.validate(config)
        assert errors == {}

    def test_invalid_relay_url_scheme(self):
        config = ConnectionConfigData(relay_url="http://example.com")
        errors = ConnectionConfigValidator.validate(config)
        assert "relay_url" in errors

    def test_invalid_relay_url_no_scheme(self):
        config = ConnectionConfigData(relay_url="example.com")
        errors = ConnectionConfigValidator.validate(config)
        assert "relay_url" in errors

    def test_nonexistent_cert_path(self, tmp_path):
        config = ConnectionConfigData(
            tunnel_tls_cert=str(tmp_path / "nonexistent.pem"),
            tunnel_tls_key=str(tmp_path / "nonexistent.key"),
            tunnel_bearer_token="test-token",
        )
        errors = ConnectionConfigValidator.validate(config)
        assert "tunnel_tls_cert" in errors
        assert "tunnel_tls_key" in errors

    def test_existing_cert_path(self, tmp_path):
        cert = tmp_path / "cert.pem"
        key = tmp_path / "key.pem"
        cert.write_text("cert content")
        key.write_text("key content")
        config = ConnectionConfigData(
            tunnel_tls_cert=str(cert),
            tunnel_tls_key=str(key),
            tunnel_bearer_token="test-token",
        )
        errors = ConnectionConfigValidator.validate(config)
        assert errors == {}

    def test_cert_without_token_is_error(self, tmp_path):
        cert = tmp_path / "cert.pem"
        key = tmp_path / "key.pem"
        cert.write_text("cert")
        key.write_text("key")
        config = ConnectionConfigData(
            tunnel_tls_cert=str(cert),
            tunnel_tls_key=str(key),
            tunnel_bearer_token="",  # empty
        )
        errors = ConnectionConfigValidator.validate(config)
        assert "tunnel_bearer_token" in errors

    def test_valid_port(self):
        config = ConnectionConfigData(tunnel_port=443)
        errors = ConnectionConfigValidator.validate(config)
        assert errors == {}


class TestUserConfigManager:
    """Tests for UserConfigManager load/save/get/set."""

    def test_load_missing_file(self, tmp_path):
        mgr = UserConfigManager(config_path=tmp_path / "nonexistent.json")
        data = mgr.load()
        assert data == {}

    def test_save_and_load_round_trip(self, tmp_path):
        path = tmp_path / "config.json"
        mgr = UserConfigManager(config_path=path)
        mgr.save({"tunnel_port": 9999, "relay_url": "wss://test.com"})
        data = mgr.load()
        assert data["tunnel_port"] == 9999
        assert data["relay_url"] == "wss://test.com"

    def test_save_creates_parent_dirs(self, tmp_path):
        path = tmp_path / "deep" / "nested" / "config.json"
        mgr = UserConfigManager(config_path=path)
        ok = mgr.save({"key": "value"})
        assert ok
        assert path.exists()

    def test_load_malformed_json(self, tmp_path):
        path = tmp_path / "bad.json"
        path.write_text("not valid json {{{")
        mgr = UserConfigManager(config_path=path)
        data = mgr.load()
        assert data == {}

    def test_get_connection_config_defaults(self, tmp_path):
        mgr = UserConfigManager(config_path=tmp_path / "empty.json")
        config = mgr.get_connection_config()
        assert config.tunnel_port == 9601
        assert config.relay_url == ""
        assert config.tunnel_tls_cert == ""

    def test_set_connection_config_persists(self, tmp_path):
        path = tmp_path / "config.json"
        mgr = UserConfigManager(config_path=path)
        config = ConnectionConfigData(
            tunnel_port=8443,
            relay_url="wss://my-relay.com",
            tunnel_bearer_token="secret123",
        )
        ok = mgr.set_connection_config(config)
        assert ok
        # Reload and verify
        loaded = mgr.get_connection_config()
        assert loaded.tunnel_port == 8443
        assert loaded.relay_url == "wss://my-relay.com"
        assert loaded.tunnel_bearer_token == "secret123"

    def test_set_preserves_other_fields(self, tmp_path):
        path = tmp_path / "config.json"
        mgr = UserConfigManager(config_path=path)
        # Save some unrelated data first
        mgr.save({"custom_field": "keep_me", "tunnel_port": 1234})
        # Update connection config
        config = ConnectionConfigData(tunnel_port=5555)
        mgr.set_connection_config(config)
        # Verify custom field is preserved
        data = mgr.load()
        assert data["custom_field"] == "keep_me"
        assert data["tunnel_port"] == 5555
