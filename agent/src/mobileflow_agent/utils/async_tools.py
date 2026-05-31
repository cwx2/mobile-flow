"""Async concurrency primitives: Throttler, Debouncer, Sequencer.

Module: utils/
Responsibility:
    Building blocks for the cache layer's refresh scheduler.
    Controls how frequently async operations execute under load.

    - Throttler: "current + next" model — at most one task runs at a time,
      latest queued task replaces any previously queued one.
    - Debouncer: delays execution, resets timer on each call.
    - Sequencer: strict serial queue, tasks execute one after another.

Used by:
    - services/refresh_scheduler.py (debounce + throttle file change events)
    - services/git_state.py (throttle state refresh)
"""

from __future__ import annotations

import asyncio
from typing import Any, Callable, Coroutine, TypeVar

from loguru import logger

T = TypeVar("T")


class Throttler:
    """Async throttler — "current + next" model (lock-free).

    At most one task runs at a time. If a new task arrives while one is
    running, it replaces any previously queued task. When the current
    task finishes, the queued task (if any) runs next.

    The key insight is that it uses two Future slots (current + next)
    instead of a lock, so new callers can always set the next task
    without waiting for the current one to finish.

    Slot model::

        queue(A) → _current = A(), return _current
        queue(B) → _next = done(_current).then(→ queue(B)), return _next
        queue(C) → _next already set, return _next (C replaces B's factory)
        A finishes → _current = None
        _next fires → _next = None, queue(C) → _current = C(), return _current

    Example::

        throttler = Throttler()
        # These three concurrent calls result in only two executions:
        # A runs immediately, B is replaced by C, C runs after A finishes.
        await throttler.queue(A)
        await throttler.queue(B)  # queued, then replaced by C
        await throttler.queue(C)  # replaces B
    """

    def __init__(self) -> None:
        # The currently executing task's Future (None if idle)
        self._current: asyncio.Future[Any] | None = None
        # The next task to run after current finishes (None if no queue)
        self._next: asyncio.Future[Any] | None = None
        # The factory for the next task (replaced on each new queue() call)
        self._next_factory: Callable[[], Coroutine[Any, Any, Any]] | None = None

    async def queue(self, factory: Callable[[], Coroutine[Any, Any, T]]) -> T:
        """Queue a task for throttled execution.

        If no task is running, executes immediately.
        If a task is running and no next is queued, creates a next slot.
        If a task is running and next is already queued, replaces the
        factory (so the latest request always wins) and returns the
        existing next Future.

        Args:
            factory: Zero-argument async callable that produces the result.

        Returns:
            The result of the task that actually executes.
        """
        # If there's already a "next" queued, just replace the factory
        # and return the existing next Future
        if self._next is not None:
            self._next_factory = factory
            return await self._next

        # If there's a current task running, create a "next" slot
        if self._current is not None:
            self._next_factory = factory
            loop = asyncio.get_running_loop()
            self._next = loop.create_future()
            next_future = self._next

            # When current finishes, clear next and re-queue
            async def _on_current_done() -> None:
                try:
                    await self._current
                except Exception:
                    pass
                # Clear next slot
                self._next = None
                # Re-queue with the latest factory
                if self._next_factory is not None:
                    f = self._next_factory
                    self._next_factory = None
                    try:
                        result = await self.queue(f)
                        if not next_future.done():
                            next_future.set_result(result)
                    except Exception as e:
                        if not next_future.done():
                            next_future.set_exception(e)

            asyncio.ensure_future(_on_current_done())
            return await next_future

        # No current task — run immediately
        loop = asyncio.get_running_loop()
        self._current = loop.create_future()
        current_future = self._current

        try:
            result = await factory()
            if not current_future.done():
                current_future.set_result(result)
            return result
        except Exception as e:
            if not current_future.done():
                current_future.set_exception(e)
            raise
        finally:
            # Clear current slot so the next queued task can proceed
            self._current = None

    def cancel(self) -> None:
        """Cancel all pending tasks.

        Resolves any waiting Futures with CancelledError so callers
        awaiting queue() don't hang forever. Called during shutdown
        to allow the event loop to exit cleanly.
        """
        if self._next is not None and not self._next.done():
            self._next.cancel()
        if self._current is not None and not self._current.done():
            self._current.cancel()
        self._next = None
        self._current = None
        self._next_factory = None


class Debouncer:
    """Async debouncer — delays execution, resets on each call.

    Only the last call within the delay window actually executes.
    Uses asyncio.get_running_loop().call_later() for timer management.

    Example::

        debouncer = Debouncer(delay=1.0)
        # Rapid calls within 1 second — only the last one fires
        debouncer.trigger(refresh)
        debouncer.trigger(refresh)  # resets timer
        debouncer.trigger(refresh)  # resets timer, this one fires after 1s

    Args:
        delay: Seconds to wait after the last trigger before executing.
    """

    def __init__(self, delay: float) -> None:
        self._delay = delay
        self._handle: asyncio.TimerHandle | None = None
        self._callback: Callable[[], Any] | None = None

    def trigger(self, callback: Callable[[], Any]) -> None:
        """Schedule callback after delay. Resets timer if called again.

        Cancels any pending timer and starts a new one.

        Args:
            callback: Function to call. Can be sync or async (coroutine
                functions are automatically scheduled on the event loop).
        """
        self.cancel()
        self._callback = callback
        loop = asyncio.get_running_loop()
        self._handle = loop.call_later(self._delay, self._fire)

    def _fire(self) -> None:
        """Internal: execute the callback when the timer expires."""
        self._handle = None
        if self._callback is not None:
            cb = self._callback
            self._callback = None
            result = cb()
            if asyncio.iscoroutine(result):
                asyncio.ensure_future(result)

    def cancel(self) -> None:
        """Cancel any pending execution."""
        if self._handle is not None:
            self._handle.cancel()
            self._handle = None
        self._callback = None

    @property
    def is_pending(self) -> bool:
        """True if a callback is scheduled but hasn't fired yet."""
        return self._handle is not None


class Sequencer:
    """Async sequencer — strict serial execution queue.

    Tasks are queued and executed one after another. The next task
    starts only after the previous one completes (or fails).

    Implemented by chaining asyncio Futures: each new task waits for
    the previous Future to settle before executing.

    Example::

        seq = Sequencer()
        # These run strictly in order, never concurrently:
        await seq.queue(git_add)
        await seq.queue(git_commit)
        await seq.queue(git_push)
    """

    def __init__(self) -> None:
        # Lazy initialization — the first queue() call creates the initial Future.
        # This avoids calling get_event_loop() at import time, which is
        # deprecated in Python 3.10+ and may fail in Python 3.12+.
        self._current: asyncio.Future[Any] | None = None

    async def queue(self, task: Callable[[], Coroutine[Any, Any, T]]) -> T:
        """Queue a task for serial execution.

        Both success and failure of the previous task trigger the next.

        Args:
            task: Zero-argument async callable.

        Returns:
            The result of the task.
        """
        prev = self._current
        loop = asyncio.get_running_loop()
        future: asyncio.Future[T] = loop.create_future()
        self._current = future

        if prev is not None:
            # Wait for previous task (ignore its errors so the next task always runs)
            try:
                await asyncio.shield(prev)
            except Exception:
                pass

        try:
            result = await task()
            if not future.done():
                future.set_result(result)
            return result
        except Exception as e:
            if not future.done():
                future.set_exception(e)
            raise
