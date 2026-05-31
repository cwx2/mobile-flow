"""Message interceptor framework core.

Provides a chain-of-responsibility pattern for cross-cutting concerns
(auth, logging, rate limiting) around WebSocket message handlers.

Inspired by Django middleware and Express.js middleware chains.
Each interceptor has pre_handle (before), post_handle (after), and
on_error (exception) hooks. The chain sorts interceptors by order
and executes them in sequence.

Key design decisions:
  - Chain NEVER re-raises exceptions — message loop never crashes.
  - pre_handle can cancel requests by setting ctx.cancelled = True.
  - on_error runs INSTEAD of post_handle when handler raises.
  - Interceptors are sorted by order (lower = earlier for pre_handle).
"""

from __future__ import annotations

import time
from abc import ABC
from dataclasses import dataclass, field
from typing import Any, Callable, Coroutine

from loguru import logger

from mobileflow_protocol.envelope import Message
from ..connection_protocol import ConnectionProtocol


@dataclass
class MessageContext:
    """Context object passed through the interceptor chain.

    Carries all information about the current message being processed,
    plus a mutable metadata dict for interceptors to communicate.

    Attributes:
        client_id: WebSocket client identifier.
        ws: The client's WebSocket connection.
        msg: The parsed protocol message.
        handler_name: Registered name of the handler (e.g. "chat.send").
        requires_cli: Whether this handler requires an active CLI provider.
        requires_project: Whether this handler requires a selected project
            (non-empty work_dir).
        is_background: Whether this handler runs in a background task.
        metadata: Mutable dict for inter-interceptor communication
            (e.g. start_time for LogInterceptor, cli_name for AuthInterceptor).
        cancelled: If True, the chain skips the handler. post_handle still runs.
    """

    client_id: str
    ws: ConnectionProtocol  # Unified connection interface (ServerConnection, EncryptedConnection, etc.)
    msg: Message
    handler_name: str = ""
    requires_cli: bool = False
    requires_project: bool = False
    is_background: bool = False
    metadata: dict[str, Any] = field(default_factory=dict)
    cancelled: bool = False


class Interceptor(ABC):
    """Abstract base class for message interceptors.

    Interceptors are sorted by ``order`` (lower = earlier for pre_handle,
    reverse for post_handle and on_error).

    Subclasses override one or more of: pre_handle, post_handle, on_error.
    Set ``ctx.cancelled = True`` in pre_handle to skip the handler.

    Attributes:
        order: Sorting priority. Lower values run first in pre_handle,
            last in post_handle/on_error.
    """

    order: int = 0

    async def pre_handle(self, ctx: MessageContext) -> None:
        """Called before the handler executes.

        Can inspect/modify the context. Set ``ctx.cancelled = True``
        to skip the handler (post_handle still runs).

        Args:
            ctx: The message context for the current request.
        """

    async def post_handle(self, ctx: MessageContext) -> None:
        """Called after the handler completes successfully.

        Args:
            ctx: The message context for the current request.
        """

    async def on_error(self, ctx: MessageContext, error: Exception) -> None:
        """Called when the handler raises an exception.

        All interceptors' on_error methods run (not short-circuited).
        The chain catches all exceptions — the message loop never crashes.

        Args:
            ctx: The message context for the current request.
            error: The exception raised by the handler.
        """


class InterceptorChain:
    """Executes interceptors around a handler in the correct order.

    Execution flow::

        1. pre_handle: interceptors sorted by order ASC (low -> high).
           If any sets ctx.cancelled = True, remaining pre_handles skip.
        2. handler: called if ctx.cancelled is False.
        3. post_handle: interceptors sorted by order DESC (high -> low).
        4. on_error: if handler raises, runs INSTEAD of post_handle,
           interceptors sorted by order DESC.

    The chain NEVER re-raises exceptions. All errors are caught, on_error
    handlers are called, and execute() returns gracefully.

    Args:
        interceptors: Unordered list of Interceptor instances.
            Will be sorted by order (ascending) internally.
    """

    def __init__(self, interceptors: list[Interceptor]):
        self._interceptors = sorted(interceptors, key=lambda i: i.order)

    async def execute(
        self,
        ctx: MessageContext,
        handler: Callable[..., Coroutine],
    ) -> None:
        """Run the full interceptor chain around a handler.

        Args:
            ctx: The message context for the current request.
            handler: Async handler callable. Signature:
                ``async def handler(client_id, ws, msg) -> None``.
        """
        # Phase 1: pre_handle (order ASC)
        for interceptor in self._interceptors:
            try:
                await interceptor.pre_handle(ctx)
            except Exception as e:
                logger.error(
                    f"拦截器 pre_handle 出错: "
                    f"interceptor={interceptor.__class__.__name__}, "
                    f"handler={ctx.handler_name}, error={e}"
                )
                await self._run_on_error(ctx, e)
                return
            if ctx.cancelled:
                logger.debug(
                    f"拦截器取消请求: "
                    f"interceptor={interceptor.__class__.__name__}, "
                    f"handler={ctx.handler_name}"
                )
                break

        # Phase 2: handler (if not cancelled)
        if not ctx.cancelled:
            try:
                await handler(ctx.client_id, ctx.ws, ctx.msg)
            except Exception as e:
                await self._run_on_error(ctx, e)
                return

        # Phase 3: post_handle (order DESC)
        for interceptor in reversed(self._interceptors):
            try:
                await interceptor.post_handle(ctx)
            except Exception as e:
                logger.error(
                    f"拦截器 post_handle 出错: "
                    f"interceptor={interceptor.__class__.__name__}, "
                    f"handler={ctx.handler_name}, error={e}"
                )

    async def _run_on_error(
        self, ctx: MessageContext, error: Exception
    ) -> None:
        """Run all on_error handlers in reverse order.

        All on_error handlers run regardless of individual failures.
        Errors within on_error are logged but don't propagate.

        Args:
            ctx: The message context.
            error: The original exception.
        """
        for interceptor in reversed(self._interceptors):
            try:
                await interceptor.on_error(ctx, error)
            except Exception as e:
                logger.error(
                    f"拦截器 on_error 出错: "
                    f"interceptor={interceptor.__class__.__name__}, "
                    f"handler={ctx.handler_name}, error={e}"
                )
