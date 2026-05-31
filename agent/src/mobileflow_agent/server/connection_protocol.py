"""Unified connection interface for all transport modes.

Defines the ConnectionProtocol that all connection adapters
(ServerConnection, EncryptedConnection, VirtualConnection) implement.
Handlers and the interceptor chain depend only on this interface.

Inspired by VS Code Remote's IChannel interface pattern.
"""

from __future__ import annotations

from typing import Protocol


class ConnectionProtocol(Protocol):
    """Unified connection interface for all transport modes.

    All connection adapters (ServerConnection, EncryptedConnection,
    VirtualConnection) implement this protocol structurally.
    Handlers and the interceptor chain only depend on this interface,
    never on concrete connection types.

    websockets.server.ServerConnection satisfies this automatically
    via duck typing — its existing send() method matches the signature.
    """

    async def send(self, data: str) -> None:
        """Send a serialised JSON message to the connected client.

        Args:
            data: JSON string to send.
        """
        ...
