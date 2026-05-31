"""
EventBus tests.

Covers: on + emit, multiple handlers, different events, emit_and_wait, no handlers.
"""

from __future__ import annotations

import pytest

from mobileflow_agent.core.event_bus import EventBus


@pytest.mark.asyncio
async def test_emit_received():
    bus = EventBus()
    received = []
    async def handler(data): received.append(data)
    bus.on("test", handler)
    await bus.emit("test", {"msg": "hello"})
    assert len(received) == 1 and received[0]["msg"] == "hello"


@pytest.mark.asyncio
async def test_multiple_handlers():
    bus = EventBus()
    r1, r2 = [], []
    async def h1(data): r1.append(data)
    async def h2(data): r2.append(data)
    bus.on("test", h1)
    bus.on("test", h2)
    await bus.emit("test", {"msg": "world"})
    assert len(r1) == 1 and len(r2) == 1


@pytest.mark.asyncio
async def test_different_event_not_called():
    bus = EventBus()
    received = []
    async def handler(data): received.append(data)
    bus.on("test", handler)
    await bus.emit("other", {"x": 1})
    assert len(received) == 0


@pytest.mark.asyncio
async def test_emit_and_wait():
    bus = EventBus()
    async def reply_handler(data): return {"answer": 42}
    bus.on("ask", reply_handler)
    result = await bus.emit_and_wait("ask", {"q": "?"}, timeout=5)
    assert result is not None and result.get("answer") == 42


@pytest.mark.asyncio
async def test_emit_no_handlers():
    bus = EventBus()
    await bus.emit("nobody_listens", {})  # should not crash
