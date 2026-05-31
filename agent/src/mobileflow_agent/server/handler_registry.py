"""Handler registration with metadata flags.

Replaces the plain dict + set approach in WebSocketServer.__init__.
Each handler is registered with flags that control dispatch behavior
(requires_cli, is_background) and interceptor behavior.

Uses a registration-based approach instead of decorators because
bound methods lose decorator attributes when stored in a dict.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Coroutine

from loguru import logger


@dataclass
class HandlerEntry:
    """A registered handler with its metadata.

    Attributes:
        handler: Async handler function. Signature:
            ``async def handler(client_id, ws, msg) -> None``.
        requires_cli: Whether this handler needs an active CLI provider.
            If True, AuthInterceptor checks auth state before dispatch.
        requires_project: Whether this handler needs a selected project
            (non-empty work_dir). If True, AuthInterceptor rejects the
            request before dispatch when no project is active.
        is_background: Whether this handler should run in asyncio.create_task.
            If True, _dispatch wraps the interceptor chain in a background task
            so it doesn't block the message loop.
    """

    handler: Callable[..., Coroutine]
    requires_cli: bool = False
    requires_project: bool = False
    is_background: bool = False


class HandlerRegistry:
    """Registry of message handlers with metadata.

    Provides registration and lookup by message type string.

    Usage::

        registry = HandlerRegistry()
        registry.register("chat.send", handle_chat_send,
                          requires_cli=True, is_background=True)
        entry = registry.get("chat.send")
    """

    def __init__(self):
        self._entries: dict[str, HandlerEntry] = {}

    def register(
        self,
        msg_type: str,
        handler: Callable[..., Coroutine],
        requires_cli: bool = False,
        requires_project: bool = False,
        is_background: bool = False,
    ) -> None:
        """Register a handler for a message type.

        Args:
            msg_type: The protocol message type string (e.g. "chat.send").
            handler: Async handler function.
            requires_cli: Whether this handler requires CLI auth.
            requires_project: Whether this handler requires a selected project.
            is_background: Whether to run in a background task.
        """
        self._entries[msg_type] = HandlerEntry(
            handler=handler,
            requires_cli=requires_cli,
            requires_project=requires_project,
            is_background=is_background,
        )

    def get(self, msg_type: str) -> HandlerEntry | None:
        """Look up a handler entry by message type.

        Args:
            msg_type: The message type string to look up.

        Returns:
            HandlerEntry if registered, None otherwise.
        """
        return self._entries.get(msg_type)

    def __contains__(self, msg_type: str) -> bool:
        return msg_type in self._entries

    def __len__(self) -> int:
        return len(self._entries)
