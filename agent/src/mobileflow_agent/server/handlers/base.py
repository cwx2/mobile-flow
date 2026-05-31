"""Base class for all WebSocket message handlers.

Module: server/handlers/
Responsibility:
    Provides the common interface and utility methods shared by every handler.
    Each handler holds a reference to the WebSocket server and accesses shared
    services through property shortcuts.

Usage:
    class ChatHandler(BaseHandler):
        async def handle_chat_send(self, client_id, ws, msg): ...

Design decisions:
    - Handlers do not hold direct service references; they access services
      through the server indirection layer.  This allows the server to swap
      services at runtime (e.g. rebuilding FileService on project switch).
    - broadcast() iterates over all connected clients and is used for
      permission requests, terminal output, and similar fan-out scenarios.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from loguru import logger
from websockets.server import ServerConnection

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.payloads.chat import ChatErrorPayload
from mobileflow_protocol.types import MessageType

if TYPE_CHECKING:
    from ..websocket import WebSocketServer


class BaseHandler:
    """Base handler that holds a server reference for accessing shared services.

    Attributes:
        server: The owning WebSocketServer instance.
    """

    def __init__(self, server: WebSocketServer):
        self.server = server

    # ── Convenience accessors ──

    @property
    def config(self):
        """Shortcut to the agent configuration."""
        return self.server.config

    @property
    def event_bus(self):
        """Shortcut to the global event bus."""
        return self.server.event_bus

    @property
    def cli_manager(self):
        """Shortcut to the CLI manager service."""
        return self.server.cli_manager

    @property
    def file_service(self):
        """Shortcut to the file service."""
        return self.server.file_service

    @property
    def project_manager(self):
        """Shortcut to the project manager service."""
        return self.server.project_manager

    @property
    def terminal_manager(self):
        """Shortcut to the terminal manager."""
        return self.server.terminal_manager

    async def send(self, ws: ServerConnection, msg: Message):
        """Send a protocol message to a single client.

        Args:
            ws: The WebSocket connection to send to.
            msg: The protocol message to send.
        """
        await ws.send(msg.model_dump_json())

    async def send_error(self, ws: ServerConnection, error: str):
        """Send a CHAT_ERROR message to a single client.

        Args:
            ws: The WebSocket connection to send to.
            error: Human-readable error description.
        """
        await self.send(ws, Message.from_typed(
            type=MessageType.CHAT_ERROR,
            payload=ChatErrorPayload(error=error),
        ))

    async def broadcast(self, msg: Message):
        """Broadcast a message to all connected clients.

        Silently ignores send failures on individual connections so that
        one broken client does not prevent delivery to others.

        Args:
            msg: The protocol message to broadcast.
        """
        for ws in list(self.server._clients.values()):
            try:
                await self.send(ws, msg)
            except Exception:
                pass
