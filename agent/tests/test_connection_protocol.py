"""Connection protocol tests: LAN encryption, Relay E2E, mode dispatch, VirtualConnection.

Tests cover:
  1. LAN encryption round-trip (CryptoModule secretbox).
  2. Relay E2E encryption round-trip (VirtualConnection → envelope → decrypt).
  3. WebSocketServer.start() mode dispatch.
  4. VirtualConnection.send() envelope format.

# Feature: connection-architecture-overhaul
"""

from __future__ import annotations

import json
import os
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from mobileflow_agent.crypto.crypto_module import CryptoModule
from mobileflow_agent.server.connection_manager import (
    EncryptedConnection,
    ServerConnectionManager,
    VirtualConnection,
)


# ═══════════════════════════════════════════════════════════════
# Property-based tests (Hypothesis)
# ═══════════════════════════════════════════════════════════════


# Feature: connection-architecture-overhaul, Property 1: LAN encryption round-trip
class TestLANEncryptionRoundTripProperty:
    """Property: for any valid message dict, encrypt then decrypt produces
    the original."""

    @given(
        message=st.dictionaries(
            st.text(min_size=1, max_size=20),
            st.one_of(
                st.text(max_size=100),
                st.integers(),
                st.booleans(),
                st.none(),
            ),
            min_size=1,
            max_size=10,
        ),
    )
    @settings(max_examples=100)
    def test_encrypt_decrypt_roundtrip(self, message: dict):
        secret = os.urandom(32)
        crypto = CryptoModule(secret)

        encrypted = crypto.encrypt(message)
        decrypted = crypto.decrypt(encrypted)
        assert decrypted == message


# Feature: connection-architecture-overhaul, Property 2: Relay E2E encryption round-trip
class TestRelayE2ERoundTripProperty:
    """Property: VirtualConnection.send() encrypts into a Relay envelope,
    and decrypting the envelope's `c` field produces the original message."""

    @given(
        message=st.dictionaries(
            st.text(min_size=1, max_size=20),
            st.one_of(
                st.text(max_size=100),
                st.integers(),
                st.booleans(),
                st.none(),
            ),
            min_size=1,
            max_size=10,
        ),
    )
    @settings(max_examples=100)
    def test_relay_e2e_roundtrip(self, message: dict):
        secret = os.urandom(32)
        crypto = CryptoModule(secret)

        # Capture what VirtualConnection sends through the mock relay WS
        mock_relay_ws = AsyncMock()
        vc = VirtualConnection(
            client_id="app-device-001",
            relay_ws=mock_relay_ws,
            crypto=crypto,
            target_device_id="app-device-001",
        )

        # VirtualConnection.send() is async — run it synchronously
        # Use asyncio.run() which works reliably across Python 3.10-3.14
        import asyncio
        asyncio.run(vc.send(json.dumps(message)))

        # Extract the envelope sent to the mock WS
        mock_relay_ws.send.assert_called_once()
        envelope_str = mock_relay_ws.send.call_args[0][0]
        envelope = json.loads(envelope_str)

        # Decrypt the ciphertext field
        decrypted = crypto.decrypt(envelope["c"])
        assert decrypted == message


# ═══════════════════════════════════════════════════════════════
# Task 16.3: WebSocketServer.start() mode dispatch
# ═══════════════════════════════════════════════════════════════


class TestModeDispatch:
    """Test that WebSocketServer.start() dispatches to the correct
    ServerConnectionManager method based on config.connection_mode."""

    @pytest.mark.asyncio
    async def test_mode_lan_calls_start_lan(self):
        """mode=lan calls start_lan."""
        with patch(
            "mobileflow_agent.server.websocket.WebSocketServer.__init__",
            return_value=None,
        ):
            from mobileflow_agent.server.websocket import WebSocketServer

            server = WebSocketServer.__new__(WebSocketServer)
            # Wire up minimal attributes needed by start()
            server.config = MagicMock()
            server.config.connection_mode = "lan"
            server.config.host = "0.0.0.0"
            server.config.port = 9600
            server.config.websocket = MagicMock(
                max_message_size_mb=10,
                ping_interval=30,
                ping_timeout=60,
                close_timeout=10,
            )
            server.config.connection = MagicMock()
            server.auth = MagicMock()
            server.auth.ensure_pair_token = MagicMock(return_value=("123456", True))
            server._print_connect_info = MagicMock()
            server.plugin_registry = MagicMock()
            server.cli_manager = AsyncMock()
            server.cli_manager.registry.list_available = MagicMock(return_value=["kiro"])
            server.config.default_cli = "kiro"
            server._watch_files = AsyncMock()
            server._test_panel = MagicMock()

            mock_conn_mgr = AsyncMock()
            server._conn_manager = mock_conn_mgr

            await server.start()

            mock_conn_mgr.start_lan.assert_called_once()
            mock_conn_mgr.start_relay.assert_not_called()
            mock_conn_mgr.start_tunnel.assert_not_called()

    @pytest.mark.asyncio
    async def test_mode_relay_calls_start_relay(self):
        """mode=relay calls start_relay."""
        with patch(
            "mobileflow_agent.server.websocket.WebSocketServer.__init__",
            return_value=None,
        ):
            from mobileflow_agent.server.websocket import WebSocketServer

            server = WebSocketServer.__new__(WebSocketServer)
            server.config = MagicMock()
            server.config.connection_mode = "relay"
            server.config.relay_url = "wss://relay.example.com"
            server.config.ensure_device_id = MagicMock(return_value="a" * 32)
            server.config.connection = MagicMock(
                relay_reconnect_max_attempts=10,
                relay_reconnect_initial_delay=1.0,
                relay_reconnect_max_delay=5.0,
            )
            server.auth = MagicMock()
            server.auth.ensure_pair_token = MagicMock(return_value=("123456", True))
            server._print_connect_info = MagicMock()
            server.plugin_registry = MagicMock()
            server.cli_manager = AsyncMock()
            server.cli_manager.registry.list_available = MagicMock(return_value=["kiro"])
            server.config.default_cli = "kiro"
            server._watch_files = AsyncMock()

            mock_conn_mgr = AsyncMock()
            server._conn_manager = mock_conn_mgr

            await server.start()

            mock_conn_mgr.start_relay.assert_called_once()
            mock_conn_mgr.start_lan.assert_not_called()
            mock_conn_mgr.start_tunnel.assert_not_called()

    @pytest.mark.asyncio
    async def test_mode_tunnel_calls_start_tunnel(self):
        """mode=tunnel calls start_tunnel."""
        with patch(
            "mobileflow_agent.server.websocket.WebSocketServer.__init__",
            return_value=None,
        ):
            from mobileflow_agent.server.websocket import WebSocketServer

            server = WebSocketServer.__new__(WebSocketServer)
            server.config = MagicMock()
            server.config.connection_mode = "tunnel"
            server.config.host = "0.0.0.0"
            server.config.port = 9600
            server.config.tunnel_bearer_token = "test-token"
            server.config.tunnel_tls_cert = ""
            server.config.tunnel_tls_key = ""
            server.config.websocket = MagicMock(max_message_size_mb=10)
            server.auth = MagicMock()
            server.auth.ensure_pair_token = MagicMock(return_value=("123456", True))
            server._print_connect_info = MagicMock()
            server.plugin_registry = MagicMock()
            server.cli_manager = AsyncMock()
            server.cli_manager.registry.list_available = MagicMock(return_value=["kiro"])
            server.config.default_cli = "kiro"
            server._watch_files = AsyncMock()

            mock_conn_mgr = AsyncMock()
            server._conn_manager = mock_conn_mgr

            await server.start()

            mock_conn_mgr.start_tunnel.assert_called_once()
            mock_conn_mgr.start_lan.assert_not_called()
            mock_conn_mgr.start_relay.assert_not_called()

    @pytest.mark.asyncio
    async def test_mode_invalid_falls_back_to_lan(self):
        """mode=invalid falls back to start_lan."""
        with patch(
            "mobileflow_agent.server.websocket.WebSocketServer.__init__",
            return_value=None,
        ):
            from mobileflow_agent.server.websocket import WebSocketServer

            server = WebSocketServer.__new__(WebSocketServer)
            server.config = MagicMock()
            server.config.connection_mode = "invalid_mode"
            server.config.host = "0.0.0.0"
            server.config.port = 9600
            server.config.websocket = MagicMock(
                max_message_size_mb=10,
                ping_interval=30,
                ping_timeout=60,
                close_timeout=10,
            )
            server.auth = MagicMock()
            server.auth.ensure_pair_token = MagicMock(return_value=("123456", True))
            server._print_connect_info = MagicMock()
            server.plugin_registry = MagicMock()
            server.cli_manager = AsyncMock()
            server.cli_manager.registry.list_available = MagicMock(return_value=["kiro"])
            server.config.default_cli = "kiro"
            server._watch_files = AsyncMock()
            server._test_panel = MagicMock()

            mock_conn_mgr = AsyncMock()
            server._conn_manager = mock_conn_mgr

            await server.start()

            mock_conn_mgr.start_lan.assert_called_once()
            mock_conn_mgr.start_relay.assert_not_called()
            mock_conn_mgr.start_tunnel.assert_not_called()


# ═══════════════════════════════════════════════════════════════
# Task 16.4: VirtualConnection.send()
# ═══════════════════════════════════════════════════════════════


class TestVirtualConnectionSend:
    """Test that VirtualConnection.send() encrypts JSON and wraps in
    relay envelope format with t, v, to, c fields."""

    @pytest.mark.asyncio
    async def test_send_produces_correct_envelope(self):
        """send() encrypts JSON and wraps in relay envelope format."""
        secret = os.urandom(32)
        crypto = CryptoModule(secret)
        mock_ws = AsyncMock()

        vc = VirtualConnection(
            client_id="sender-001",
            relay_ws=mock_ws,
            crypto=crypto,
            target_device_id="target-app-device",
        )

        message = {"type": "chat.send", "payload": {"message": "hello"}}
        await vc.send(json.dumps(message))

        mock_ws.send.assert_called_once()
        envelope_str = mock_ws.send.call_args[0][0]
        envelope = json.loads(envelope_str)

        # Verify envelope structure
        assert envelope["t"] == "encrypted"
        assert envelope["v"] == 1
        assert envelope["to"] == "target-app-device"
        assert isinstance(envelope["c"], str)

        # Verify the ciphertext decrypts to the original message
        decrypted = crypto.decrypt(envelope["c"])
        assert decrypted == message

    @pytest.mark.asyncio
    async def test_send_envelope_has_all_required_fields(self):
        """Envelope must contain exactly t, v, to, c keys."""
        secret = os.urandom(32)
        crypto = CryptoModule(secret)
        mock_ws = AsyncMock()

        vc = VirtualConnection(
            client_id="sender",
            relay_ws=mock_ws,
            crypto=crypto,
            target_device_id="receiver",
        )

        await vc.send(json.dumps({"type": "status.ping", "payload": {}}))

        envelope = json.loads(mock_ws.send.call_args[0][0])
        assert set(envelope.keys()) == {"t", "v", "to", "c"}
