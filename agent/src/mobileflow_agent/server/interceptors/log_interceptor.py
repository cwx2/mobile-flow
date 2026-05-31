"""Logging interceptor for request tracing.

Logs request start, completion time, and errors for every message
passing through the interceptor chain. Runs first (order=1) so it
captures timing for all other interceptors and the handler.
"""

from __future__ import annotations

import time

from loguru import logger

from .base import Interceptor, MessageContext


class LogInterceptor(Interceptor):
    """Interceptor that logs request lifecycle events.

    Attributes:
        order: 1 (runs first in pre_handle, last in post_handle/on_error).
    """

    order: int = 1

    async def pre_handle(self, ctx: MessageContext) -> None:
        """Log request start and record start time.

        Args:
            ctx: The message context.
        """
        ctx.metadata["_log_start_time"] = time.monotonic()
        # Skip noisy heartbeat logging
        if ctx.handler_name == "status.ping":
            return
        mode = ctx.metadata.get("_connection_mode", "unknown")
        logger.debug(
            f"请求开始: handler={ctx.handler_name}, "
            f"client={ctx.client_id[:8]}..., mode={mode}"
        )

    async def post_handle(self, ctx: MessageContext) -> None:
        """Log request completion with elapsed time.

        Args:
            ctx: The message context.
        """
        start = ctx.metadata.get("_log_start_time")
        elapsed = (time.monotonic() - start) * 1000 if start else 0
        # Skip noisy heartbeat logging
        if ctx.handler_name == "status.ping":
            return
        mode = ctx.metadata.get("_connection_mode", "unknown")
        if ctx.cancelled:
            logger.debug(
                f"请求被拦截: handler={ctx.handler_name}, "
                f"mode={mode}, 耗时={elapsed:.1f}ms"
            )
        else:
            logger.debug(
                f"请求完成: handler={ctx.handler_name}, "
                f"mode={mode}, 耗时={elapsed:.1f}ms"
            )

    async def on_error(self, ctx: MessageContext, error: Exception) -> None:
        """Log request error with elapsed time and exception details.

        Args:
            ctx: The message context.
            error: The exception raised by the handler.
        """
        start = ctx.metadata.get("_log_start_time")
        elapsed = (time.monotonic() - start) * 1000 if start else 0
        mode = ctx.metadata.get("_connection_mode", "unknown")
        logger.error(
            f"请求出错: handler={ctx.handler_name}, "
            f"mode={mode}, 耗时={elapsed:.1f}ms, "
            f"error_type={type(error).__name__}, "
            f"error={error}"
        )
