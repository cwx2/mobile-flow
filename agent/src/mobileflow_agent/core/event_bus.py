"""
Async EventBus for decoupled inter-module communication.

Replaces lambda callback chains between WebSocket handlers and ACP providers.
Inspired by openclaw's Hook system.

Design principles:
  - Event-driven > callback passing (loose coupling)
  - Multiple handlers per event (fan-out)
  - Handlers can return results (request-response pattern for permissions)
  - Async handlers only (consistent with asyncio architecture)
  - One-shot handlers via ``once()`` (auto-removed after first trigger)
"""

from __future__ import annotations

import asyncio
from typing import Any, Callable, Coroutine

from loguru import logger


# handler 类型：接收 data dict，返回 dict 或 None
EventHandler = Callable[..., Coroutine[Any, Any, dict | None]]


class EventBus:
    """Async event bus for publish-subscribe communication.

    Usage::

        bus = EventBus()
        bus.on("permission.request", handle_permission)
        result = await bus.emit_and_wait("permission.request", data)

    All handlers must be async functions accepting a single dict argument.
    """

    def __init__(self):
        self._handlers: dict[str, list[EventHandler]] = {}
        self._once_handlers: dict[str, list[EventHandler]] = {}

    def on(self, event: str, handler: EventHandler):
        """Register a persistent event handler.

        Args:
            event: Event name (use constants from ``Events`` class).
            handler: Async function ``(data: dict) -> dict | None``.
        """
        self._handlers.setdefault(event, []).append(handler)
        logger.debug(f"EventBus: 注册 handler → {event}")

    def once(self, event: str, handler: EventHandler):
        """Register a one-shot event handler (auto-removed after first trigger).

        Args:
            event: Event name.
            handler: Async function, called once then discarded.
        """
        self._once_handlers.setdefault(event, []).append(handler)

    def off(self, event: str, handler: EventHandler | None = None):
        """Remove event handler(s).

        Args:
            event: Event name.
            handler: Specific handler to remove. If None, removes ALL handlers
                for this event (both persistent and one-shot).
        """
        if handler is None:
            self._handlers.pop(event, None)
            self._once_handlers.pop(event, None)
        else:
            handlers = self._handlers.get(event, [])
            if handler in handlers:
                handlers.remove(handler)

    async def emit(self, event: str, data: dict | None = None) -> list[dict]:
        """Fire an event, calling all handlers concurrently and collecting results.

        Persistent handlers are called first, then one-shot handlers (which are
        removed after execution). Errors in individual handlers are logged but
        don't prevent other handlers from running.

        Args:
            event: Event name to fire.
            data: Event payload dict. Defaults to empty dict.

        Returns:
            List of non-None return values from handlers.
        """
        data = data or {}
        results: list[dict] = []

        # 持久 handler
        for handler in self._handlers.get(event, []):
            try:
                result = await handler(data)
                if result:
                    results.append(result)
            except Exception as e:
                logger.error(f"EventBus handler 出错 [{event}]: {e}")

        # 一次性 handler（执行后移除）
        once = self._once_handlers.pop(event, [])
        for handler in once:
            try:
                result = await handler(data)
                if result:
                    results.append(result)
            except Exception as e:
                logger.error(f"EventBus once handler 出错 [{event}]: {e}")

        return results

    async def emit_and_wait(
        self, event: str, data: dict | None = None, timeout: float = 120
    ) -> dict | None:
        """Fire an event and wait for the first handler to return a result.

        Used for request-response patterns (e.g. permission request waiting
        for user approval on the phone).

        Args:
            event: Event name to fire.
            data: Event payload dict.
            timeout: Max seconds to wait for handler response. Defaults to 120.

        Returns:
            Handler result dict, or None on timeout/error/no handlers.
        """
        data = data or {}
        handlers = self._handlers.get(event, [])
        if not handlers:
            logger.warning(f"EventBus: 无 handler 处理 {event}")
            return None

        try:
            result = await asyncio.wait_for(handlers[0](data), timeout=timeout)
            return result
        except asyncio.TimeoutError:
            logger.warning(f"EventBus: {event} 超时 ({timeout}s)")
            return None
        except Exception as e:
            logger.error(f"EventBus emit_and_wait 出错 [{event}]: {e}")
            return None

    @property
    def event_names(self) -> list[str]:
        """List all event names that have at least one registered handler."""
        names = set(self._handlers.keys()) | set(self._once_handlers.keys())
        return sorted(names)
