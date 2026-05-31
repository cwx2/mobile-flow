"""Client lifecycle scope — binds resources to a client connection.

Module: core/
Responsibility:
    Every resource created for a specific client (terminal session,
    background task, cancel event, etc.) registers a cleanup function
    here. When the client disconnects, dispose() runs all cleanups
    in reverse order (LIFO), guaranteeing no resource leaks.

    Background loops use ``scope.cancelled`` (asyncio.Event) to detect
    disconnection and exit gracefully, instead of each loop manually
    checking ``client_id in _clients``.

Design:
    Inspired by Erlang/OTP process links — when a parent process dies,
    all linked child processes receive an exit signal automatically.
    ClientScope simulates this in Python asyncio: dispose() is the
    "exit signal", and registered cleanup functions are the "trap_exit"
    handlers.

Used by:
    - server/websocket.py (creates scope on connect, disposes on disconnect)
    - server/handlers/terminal_handler.py (registers PTY + forward task)
    - services/cli_manager.py (registers provider cleanup)
    - server/handlers/file_handler.py (registers search cancel events)
"""

from __future__ import annotations

import asyncio
from typing import Any, Callable, Coroutine

from loguru import logger


class ClientScope:
    """Lifecycle scope for a single client connection.

    All resources bound to this client register cleanup functions via
    on_dispose(). When the client disconnects, dispose() executes all
    registered cleanups in reverse order (LIFO — last registered,
    first cleaned up).

    Background tasks check ``cancelled.is_set()`` or
    ``await cancelled.wait()`` to detect disconnection and exit gracefully.

    Attributes:
        client_id: The client's unique identifier.
        cancelled: Event that is set when the client disconnects.
            Background loops should check this to exit gracefully.
    """

    def __init__(self, client_id: str) -> None:
        self.client_id = client_id
        self.cancelled = asyncio.Event()
        self._cleanups: list[Callable[[], Coroutine[Any, Any, None] | None]] = []
        self._disposed = False

    @property
    def is_alive(self) -> bool:
        """True if the client is still connected."""
        return not self._disposed

    def reset(self) -> None:
        """Reset the scope for reuse after a client reconnects within the grace period.

        Clears the cancelled event so new background loops can check it.
        Only valid if dispose() has not yet run (i.e. the grace timer was
        cancelled before it fired).

        Note: existing background loops that already exited due to
        cancelled.is_set() will NOT automatically restart. Resources like
        terminal sessions need to be re-created by the user. Only the ACP
        provider (which runs independently) survives the suspend/resume cycle.
        """
        if self._disposed:
            logger.warning(
                f"[ClientScope] reset() 调用在已销毁的 scope 上（忽略）: "
                f"client={self.client_id[:8]}..."
            )
            return
        self.cancelled.clear()
        logger.debug(f"[ClientScope] 已重置: client={self.client_id[:8]}...")


    def on_dispose(self, fn: Callable[[], Coroutine[Any, Any, None] | None]) -> None:
        """Register a cleanup function to run on client disconnect.

        Functions are called in reverse registration order (LIFO).
        Both sync and async functions are supported.

        Args:
            fn: Zero-argument callable (sync or async) that cleans up
                a resource. Exceptions are caught and logged.
        """
        if self._disposed:
            logger.warning(
                f"[ClientScope] 注册清理函数到已销毁的 scope: "
                f"client={self.client_id[:8]}..."
            )
            return
        self._cleanups.append(fn)

    def track_task(self, task: asyncio.Task) -> asyncio.Task:
        """Track a background task — auto-cancel on dispose.

        Registers a cleanup that cancels the task and awaits its
        completion. Returns the task for chaining convenience.

        Args:
            task: The asyncio.Task to track.

        Returns:
            The same task (for chaining).
        """
        async def _cancel():
            if not task.done():
                task.cancel()
                try:
                    await task
                except (asyncio.CancelledError, Exception):
                    pass

        self.on_dispose(_cancel)
        return task

    async def dispose(self) -> None:
        """Run all registered cleanups in reverse order.

        Called exactly once when the client disconnects. Sets the
        cancelled event first so background loops can exit before
        their resources are torn down.

        Exceptions in individual cleanups are caught and logged —
        one failing cleanup does not prevent others from running.
        """
        if self._disposed:
            return
        self._disposed = True

        # Signal all background loops to exit
        self.cancelled.set()

        # Run cleanups in reverse order (LIFO)
        for fn in reversed(self._cleanups):
            try:
                result = fn()
                if asyncio.iscoroutine(result):
                    await result
            except Exception as e:
                logger.warning(
                    f"[ClientScope] 清理出错: client={self.client_id[:8]}..., "
                    f"error={e}"
                )

        self._cleanups.clear()
        logger.debug(
            f"[ClientScope] 已销毁: client={self.client_id[:8]}..."
        )
