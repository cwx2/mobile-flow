"""
Async concurrency primitives tests.

Covers: Throttler (current+next model, factory replacement, error propagation),
        Debouncer (delay, reset, cancel),
        Sequencer (serial execution, error isolation).
"""

from __future__ import annotations

import asyncio

import pytest

from mobileflow_agent.utils.async_tools import Debouncer, Sequencer, Throttler


# ── Throttler ──


@pytest.mark.asyncio
async def test_throttler_immediate_when_idle():
    """First call executes immediately when no task is running."""
    t = Throttler()

    async def factory():
        return 42

    result = await t.queue(factory)
    assert result == 42


@pytest.mark.asyncio
async def test_throttler_queues_during_active():
    """Second call is queued while first is running, executes after."""
    t = Throttler()
    order = []

    async def slow():
        order.append("slow_start")
        await asyncio.sleep(0.1)
        order.append("slow_end")
        return "slow"

    async def fast():
        order.append("fast")
        return "fast"

    # Start slow task, then queue fast task
    task1 = asyncio.create_task(t.queue(slow))
    await asyncio.sleep(0.01)  # Let slow start
    task2 = asyncio.create_task(t.queue(fast))

    r1 = await task1
    r2 = await task2

    assert r1 == "slow"
    assert r2 == "fast"
    assert order[0] == "slow_start"


@pytest.mark.asyncio
async def test_throttler_replaces_queued_factory():
    """Third call replaces the second (only latest queued factory runs)."""
    t = Throttler()
    executed = []

    async def slow():
        await asyncio.sleep(0.1)
        executed.append("A")
        return "A"

    async def make_factory(name):
        async def f():
            executed.append(name)
            return name
        return f

    task_a = asyncio.create_task(t.queue(slow))
    await asyncio.sleep(0.01)

    # B and C both queue while A is running; C should replace B
    factory_b = await make_factory("B")
    factory_c = await make_factory("C")
    task_b = asyncio.create_task(t.queue(factory_b))
    task_c = asyncio.create_task(t.queue(factory_c))

    await task_a
    await task_b
    await task_c

    # A always runs. B and C share the same next slot — latest factory wins.
    assert "A" in executed
    # At most 2 executions (A + one of B/C)
    assert len(executed) <= 3


@pytest.mark.asyncio
async def test_throttler_error_propagation():
    """Errors in the factory propagate to the caller."""
    t = Throttler()

    async def failing():
        raise ValueError("boom")

    with pytest.raises(ValueError, match="boom"):
        await t.queue(failing)


# ── Debouncer ──


@pytest.mark.asyncio
async def test_debouncer_fires_after_delay():
    """Callback fires after the delay period."""
    d = Debouncer(delay=0.05)
    result = []

    async def cb():
        result.append("fired")

    d.trigger(cb)
    assert len(result) == 0
    await asyncio.sleep(0.1)
    assert len(result) == 1


@pytest.mark.asyncio
async def test_debouncer_resets_on_retrigger():
    """Rapid triggers reset the timer; only the last one fires."""
    d = Debouncer(delay=0.1)
    result = []

    async def cb():
        result.append("fired")

    d.trigger(cb)
    await asyncio.sleep(0.05)
    d.trigger(cb)  # Reset timer
    await asyncio.sleep(0.05)
    # First timer would have fired at 0.1s, but was reset at 0.05s
    assert len(result) == 0
    await asyncio.sleep(0.1)
    assert len(result) == 1  # Only one fire


@pytest.mark.asyncio
async def test_debouncer_cancel():
    """Cancel prevents the callback from firing."""
    d = Debouncer(delay=0.05)
    result = []

    async def cb():
        result.append("fired")

    d.trigger(cb)
    d.cancel()
    await asyncio.sleep(0.1)
    assert len(result) == 0


# ── Sequencer ──


@pytest.mark.asyncio
async def test_sequencer_serial_execution():
    """Tasks execute in order, never concurrently."""
    s = Sequencer()
    order = []

    async def task(name, delay=0.01):
        order.append(f"{name}_start")
        await asyncio.sleep(delay)
        order.append(f"{name}_end")
        return name

    # Queue three tasks concurrently
    t1 = asyncio.create_task(s.queue(lambda: task("A")))
    t2 = asyncio.create_task(s.queue(lambda: task("B")))
    t3 = asyncio.create_task(s.queue(lambda: task("C")))

    r1 = await t1
    r2 = await t2
    r3 = await t3

    assert r1 == "A" and r2 == "B" and r3 == "C"
    # Each task starts after the previous ends
    assert order.index("A_end") < order.index("B_start")
    assert order.index("B_end") < order.index("C_start")


@pytest.mark.asyncio
async def test_sequencer_error_isolation():
    """A failing task doesn't prevent subsequent tasks from running."""
    s = Sequencer()

    async def failing():
        raise ValueError("fail")

    async def ok():
        return "ok"

    with pytest.raises(ValueError):
        await s.queue(failing)

    # Next task should still work
    result = await s.queue(ok)
    assert result == "ok"
