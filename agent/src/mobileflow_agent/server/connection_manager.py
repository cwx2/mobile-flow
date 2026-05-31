"""Server-side connection mode abstraction layer.

Module: server/
Responsibility:
    1. Manage the Agent's connection mode (LAN / Relay / Tunnel).
    2. LAN mode: start a WebSocket server (existing behaviour).
    3. Relay mode: connect as a client to a Relay Server with E2E encryption.
    4. Tunnel mode: start a TLS-enabled WebSocket server.

Called by:
    - server/websocket.py (replaces the raw ``websockets.serve`` call).

Design decisions:
    - LAN mode: Agent is the WebSocket server, App is the client.
    - Relay mode: both Agent and App are clients of the Relay Server.
    - Tunnel mode: Agent is the WebSocket server (with TLS), App is the client.
    - The abstraction is fully transparent to the handler layer above.
"""

from __future__ import annotations

import asyncio
import json
from enum import Enum
from typing import Any, Callable, Coroutine, Optional

import websockets
from loguru import logger
from websockets.server import ServerConnection

from ..crypto.crypto_module import CryptoModule


class ConnectionMode(str, Enum):
    """Supported connection modes between Agent and App."""
    LAN = "lan"
    RELAY = "relay"
    TUNNEL = "tunnel"


class ServerConnectionManager:
    """Unified connection manager for all three connection modes.

    Abstracts away the transport differences so that the handler layer
    can send and receive messages without caring about the underlying mode.

    Attributes:
        _mode: The currently active connection mode.
        _crypto: E2E encryption module (used in Relay mode).
        _relay_ws: WebSocket client connection for Relay mode.
        _clients: Active client connections (LAN / Tunnel mode).
    """

    def __init__(self):
        self._mode = ConnectionMode.LAN
        self._crypto: Optional[CryptoModule] = None
        # WebSocket client connection for Relay mode
        self._relay_ws: Optional[Any] = None
        # Message callback registered by WebSocketServer
        self._on_message: Optional[Callable] = None
        # Active client connections (LAN / Tunnel mode)
        self._clients: dict[str, ServerConnection] = {}
        # Per-client encryption state: None = plaintext (pre-pairing),
        # CryptoModule = encrypted (post-pairing). Managed by auth handler
        # via activate_encryption() after auth.pair succeeds.
        self._client_crypto: dict[str, CryptoModule | None] = {}

    @property
    def mode(self) -> ConnectionMode:
        """Return the currently active connection mode."""
        return self._mode

    def set_message_handler(
        self,
        handler: Callable[[str, Any, dict], Coroutine],
    ) -> None:
        """Register the message processing callback.

        This is a thin wrapper around ``WebSocketServer._route``.

        Args:
            handler: Async callable ``(client_id, ws, message_dict) -> None``.
        """
        self._on_message = handler

    # ── Per-client encryption management ──

    def activate_encryption(self, client_id: str, crypto: CryptoModule) -> None:
        """Switch a client from plaintext to encrypted mode.

        Called by the auth handler after auth.pair succeeds. From this point,
        all incoming messages from this client are decrypted before reaching
        _handle_connection, and all outgoing messages are encrypted by
        EncryptedConnection.send().

        Args:
            client_id: The client identifier to activate encryption for.
            crypto: CryptoModule initialised with the shared secret
                established during pairing.
        """
        self._client_crypto[client_id] = crypto
        logger.info(f"客户端加密已激活: client_id={client_id[:16]}")

    def decrypt_if_needed(self, client_id: str, raw: str) -> str:
        """Decrypt an incoming message if encryption is active for this client.

        Checks the per-client encryption state: if a CryptoModule is registered
        for this client_id, the raw ciphertext is decrypted and returned as a
        JSON string. If no encryption is active (pre-pairing phase), the raw
        string is returned unchanged.

        Args:
            client_id: The client identifier to look up encryption state for.
            raw: Raw WebSocket message string (ciphertext or plaintext JSON).

        Returns:
            Plaintext JSON string — either decrypted or passed through unchanged.

        Raises:
            nacl.exceptions.CryptoError: If decryption fails (wrong key or
                tampered ciphertext).
            json.JSONDecodeError: If the decrypted payload is not valid JSON.
        """
        crypto = self._client_crypto.get(client_id)
        if crypto is None:
            return raw
        # CryptoModule.decrypt() returns a dict; serialise back to JSON string
        # so the caller receives a uniform plaintext JSON string interface
        decrypted_dict = crypto.decrypt(raw)
        # logger.debug(f"消息已解密: client_id={client_id[:16]}")
        return json.dumps(decrypted_dict, ensure_ascii=False)

    # ── LAN mode (Agent is the server) ──

    async def start_lan(
        self,
        host: str,
        port: int,
        handler: Callable,
        max_size: int = 10 * 1024 * 1024,
        ping_interval: int | None = None,
        ping_timeout: int | None = None,
        close_timeout: int | None = None,
        process_request: Callable | None = None,
    ):
        """Start a plain WebSocket server in LAN mode.

        This is a direct wrapper around the existing ``websockets.serve`` logic
        and does not change any behaviour. Accepts the same WebSocket tuning
        parameters that were previously passed directly to ``websockets.serve``
        in ``WebSocketServer.start()``.

        Args:
            host: Network interface to bind to.
            port: TCP port to listen on.
            handler: Per-connection handler coroutine.
            max_size: Maximum incoming message size in bytes.
            ping_interval: WebSocket ping interval in seconds.
            ping_timeout: WebSocket ping timeout in seconds.
            close_timeout: WebSocket close handshake timeout in seconds.
            process_request: Optional HTTP request interceptor for serving
                the dashboard. Returns an HTTP Response for non-WebSocket
                requests, or None to proceed with the WebSocket handshake.
        """
        self._mode = ConnectionMode.LAN
        logger.info(f"📡 LAN 模式: ws://{host}:{port}")
        async with websockets.serve(
            handler, host, port,
            max_size=max_size,
            ping_interval=ping_interval,
            ping_timeout=ping_timeout,
            close_timeout=close_timeout,
            process_request=process_request,
        ):
            await asyncio.Future()

    # ── Relay mode (Agent is a client of the Relay Server) ──

    async def start_relay(
        self,
        relay_url: str,
        device_id: str,
        crypto: CryptoModule,
        on_raw_message: Callable[[str, dict], Coroutine],
        max_attempts: int = 10,
        initial_delay: float = 1.0,
        max_delay: float = 5.0,
    ):
        """Connect to a Relay Server as a client with E2E encryption.

        Maintains a persistent connection with exponential backoff reconnection.
        Derives client_id from the Relay envelope ``from`` field so multiple
        Apps can connect simultaneously with unique identifiers.

        Backoff schedule: initial_delay → 2× → 4× → capped at max_delay.
        After max_attempts consecutive failures the method logs an ERROR and
        stops reconnecting.

        Args:
            relay_url: The ``wss://`` URL of the Relay Server.
            device_id: This Agent's unique device identifier.
            crypto: E2E encryption module for message encrypt/decrypt.
            on_raw_message: Callback ``(client_id, decrypted_dict)`` invoked
                for each decrypted application message.
            max_attempts: Maximum consecutive reconnection attempts before
                giving up. Read from ``config.connection.relay_reconnect_max_attempts``.
            initial_delay: Initial backoff delay in seconds.
            max_delay: Maximum backoff delay cap in seconds.
        """
        self._mode = ConnectionMode.RELAY
        self._crypto = crypto
        ws_url = f"{relay_url}/ws/agent/{device_id}"
        logger.info(f"📡 Relay 模式: {ws_url}")

        # Prepare auth challenge
        auth_data = crypto.auth_challenge()
        logger.debug(f"Relay 认证: publicKey={auth_data.public_key[:16]}...")

        attempt = 0
        delay = initial_delay

        while True:
            try:
                async with websockets.connect(ws_url) as ws:
                    self._relay_ws = ws
                    logger.info("✅ Relay 连接成功")
                    # Reset backoff on successful connection
                    attempt = 0
                    delay = initial_delay

                    # Send authentication handshake
                    await ws.send(json.dumps({
                        "type": "auth",
                        "challenge": auth_data.challenge,
                        "public_key": auth_data.public_key,
                        "signature": auth_data.signature,
                    }))

                    async for raw in ws:
                        try:
                            envelope = json.loads(raw)
                            if envelope.get("t") == "encrypted":
                                # Derive client_id from envelope sender
                                client_id = envelope.get("from", "relay-client")
                                decrypted = crypto.decrypt(envelope["c"])
                                await on_raw_message(client_id, decrypted)
                            else:
                                # Relay control message (not application data)
                                logger.debug(f"Relay 控制消息: {envelope.get('type', 'unknown')}")
                        except Exception as e:
                            logger.error(f"Relay 消息处理错误: {e}")

            except websockets.ConnectionClosed:
                logger.warning(f"Relay 连接断开: attempt={attempt + 1}/{max_attempts}")
            except Exception as e:
                logger.error(f"Relay 连接错误: {e}")

            self._relay_ws = None
            attempt += 1

            if attempt >= max_attempts:
                logger.error(
                    f"Relay 重连失败: 已达最大重试次数 {max_attempts}，停止重连"
                )
                break

            logger.warning(
                f"Relay 重连: attempt={attempt}/{max_attempts}, "
                f"delay={delay:.1f}s"
            )
            await asyncio.sleep(delay)
            # Exponential backoff: double the delay, cap at max_delay
            delay = min(delay * 2, max_delay)

    async def relay_send(self, message: dict) -> None:
        """Send a message in Relay mode with automatic E2E encryption.

        If the relay connection is not active the message is silently dropped.

        Args:
            message: Plain-text message dict to encrypt and send.
        """
        if self._relay_ws is None or self._crypto is None:
            logger.warning("Relay 未连接，消息丢弃")
            return
        try:
            encrypted = self._crypto.encrypt(message)
            envelope = json.dumps({
                "t": "encrypted",
                "v": 1,
                "c": encrypted,
            })
            await self._relay_ws.send(envelope)
        except Exception as e:
            logger.error(f"Relay 发送错误: {e}")

    # ── Tunnel mode (Agent is the server, with TLS) ──

    async def start_tunnel(
        self,
        host: str,
        port: int,
        handler: Callable,
        bearer_token: Optional[str] = None,
        ssl_context: Optional[Any] = None,
        max_size: int = 10 * 1024 * 1024,
    ):
        """Start a TLS-enabled WebSocket server in Tunnel mode.

        Validates the Bearer Token in the HTTP upgrade request before
        allowing the WebSocket handshake to proceed. Returns HTTP 401
        if the token is missing or incorrect.

        Args:
            host: Network interface to bind to.
            port: TCP port to listen on.
            handler: Per-connection handler coroutine.
            bearer_token: Optional Bearer token for connection authentication.
            ssl_context: TLS/SSL context with certificate and key.
            max_size: Maximum incoming message size in bytes.
        """
        self._mode = ConnectionMode.TUNNEL
        self._tunnel_bearer_token = bearer_token
        logger.info(f"📡 Tunnel 模式: wss://{host}:{port}")

        # Bearer Token validation at HTTP upgrade level
        process_request = None
        if bearer_token:
            from http import HTTPStatus
            from websockets.http11 import Response

            def _check_bearer(connection, request):
                """Reject connections without a valid Bearer Token."""
                auth_header = request.headers.get("Authorization", "")
                if not auth_header.startswith("Bearer "):
                    logger.warning(f"Tunnel 认证失败: 缺少 Bearer Token, path={request.path}")
                    return Response(HTTPStatus.UNAUTHORIZED, "Unauthorized\n", request.headers)
                token = auth_header[len("Bearer "):]
                if token != bearer_token:
                    logger.warning(f"Tunnel 认证失败: Token 不匹配, path={request.path}")
                    return Response(HTTPStatus.FORBIDDEN, "Forbidden\n", request.headers)
                return None  # Allow the WebSocket handshake to proceed

            process_request = _check_bearer
            logger.info("Tunnel Bearer Token 验证已启用")

        async with websockets.serve(
            handler, host, port,
            ssl=ssl_context,
            max_size=max_size,
            process_request=process_request,
        ):
            await asyncio.Future()


class VirtualConnection:
    """Adapter presenting ConnectionProtocol-compatible send() for Relay mode.

    Implements ConnectionProtocol. When a handler calls conn.send(json_str),
    VirtualConnection encrypts the message via CryptoModule and forwards it
    through the Relay WS client connection wrapped in a Relay envelope.

    The envelope format ``{"t": "encrypted", "v": 1, "to": target_device_id, "c": ciphertext}``
    tells the Relay Server which App device should receive the message.

    Attributes:
        client_id: The Relay-derived client identifier (from envelope ``from`` field).
        _relay_ws: The WebSocket client connection to the Relay Server.
        _crypto: CryptoModule for E2E encryption.
        _target_device_id: The App's device_id for envelope routing.
    """

    def __init__(self, client_id: str, relay_ws: Any, crypto: CryptoModule,
                 target_device_id: str):
        self.client_id = client_id
        self._relay_ws = relay_ws
        self._crypto = crypto
        self._target_device_id = target_device_id

    async def send(self, data: str) -> None:
        """Encrypt and send a JSON message through the Relay connection.

        Parses the JSON string, encrypts it via CryptoModule (NaCl secretbox),
        wraps it in a Relay envelope with the target device_id, and sends it
        through the Relay WebSocket client connection.

        Matches ConnectionProtocol.send() so handlers can call conn.send()
        without knowing the transport mode.

        Args:
            data: Serialised JSON string to send.

        Raises:
            TypeError: If ``data`` is not valid JSON.
        """
        message = json.loads(data)
        encrypted = self._crypto.encrypt(message)
        envelope = json.dumps({
            "t": "encrypted",
            "v": 1,
            "to": self._target_device_id,
            "c": encrypted,
        })
        await self._relay_ws.send(envelope)


class EncryptedConnection:
    """Transport-layer adapter that transparently encrypts outgoing messages.

    Implements ConnectionProtocol. Used in LAN mode after pairing establishes
    a shared secret. Wraps a raw ServerConnection — handlers see the same
    send() interface, encryption is invisible to them.

    ServerConnectionManager creates this adapter after auth.pair succeeds
    and registers it in _clients so all subsequent handler calls go through
    the encrypted path.

    Attributes:
        _ws: The underlying raw ServerConnection.
        _crypto: CryptoModule initialised with the shared secret.
    """

    def __init__(self, ws: ServerConnection, crypto: CryptoModule):
        self._ws = ws
        self._crypto = crypto

    async def send(self, data: str) -> None:
        """Encrypt and send a JSON message.

        Parses the JSON string into a dict, encrypts it via CryptoModule
        (NaCl secretbox), and sends the Base64-encoded ciphertext through
        the underlying raw WebSocket connection.

        Args:
            data: Serialised JSON string to encrypt and send.

        Raises:
            TypeError: If ``data`` is not valid JSON.
        """
        msg_dict = json.loads(data)
        encrypted = self._crypto.encrypt(msg_dict)
        await self._ws.send(encrypted)
