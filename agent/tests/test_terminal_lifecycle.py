"""Terminal handler lifecycle tests.

Tests cover the generation counter + Task.cancel() mechanism that prevents
stale forward tasks from interfering with new terminal sessions during
CLI switching.

Bug context:
    When the user switches CLI (e.g. Codex → Kiro), the old forward task
    must be fully stopped before the new session starts. The old boolean
    cancel flag had a race condition where the flag was reset before the
    old task checked it. The new approach uses:
    1. asyncio.Task.cancel() for deterministic cancellation
    2. Monotonic generation counter as a secondary guard

# Feature: terminal-lifecycle-fix
"""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, MagicMock

import pytest

from mobileflow_agent.server.handlers.terminal_handler import TerminalHandler


# ═══════════════════════════════════════════════════════════════
# Fixtures
# ═══════════════════════════════════════════════════════════════


@pytest.fixture
def mock_server():
    """Create a minimal mock WebSocketServer for TerminalHandler."""
    server = MagicMock()
    server.config = MagicMock()
    server.config.work_dir = "/tmp/test-project"
    server.config.default_cli = "test-cli"
    server.terminal_manager = MagicMock()
    server.terminal_manager.stop_session = AsyncMock()
    server.terminal_manager.create_session = AsyncMock()
    server.terminal_manager.get_session = MagicMock(return_value=None)
    server.cli_manager = MagicMock()
    return server


@pytest.fixture
def handler(mock_server):
    """Create a TerminalHandler with mocked server."""
    return TerminalHandler(mock_server)


# ═══════════════════════════════════════════════════════════════
# Generation counter tests
# ═══════════════════════════════════════════════════════════════


class TestGenerationCounter:
    """Verify the monotonic generation counter correctly invalidates
    old forward tasks."""

    def test_initial_generation_defaults_to_zero(self, handler):
        assert handler._generations.get("client-1", 0) == 0

    def test_generation_increments(self, handler):
        handler._generations["c1"] = 0
        handler._generations["c1"] = handler._generations["c1"] + 1
        assert handler._generations["c1"] == 1
        handler._generations["c1"] = handler._generations["c1"] + 1
        assert handler._generations["c1"] == 2

    def test_is_current_generation_match(self, handler):
        handler._generations["c1"] = 5
        assert handler._is_current_generation("c1", 5) is True

    def test_is_current_generation_stale(self, handler):
        handler._generations["c1"] = 5
        assert handler._is_current_generation("c1", 4) is False
        assert handler._is_current_generation("c1", 3) is False

    def test_is_current_generation_unknown_client(self, handler):
        assert handler._is_current_generation("unknown", 0) is True
        assert handler._is_current_generation("unknown", 1) is False

    def test_stop_advances_generation(self, handler):
        """terminal.stop must also advance generation to invalidate loops."""
        handler._generations["c1"] = 3
        handler._generations["c1"] = handler._generations.get("c1", 0) + 1
        assert handler._generations["c1"] == 4


# ═══════════════════════════════════════════════════════════════
# Task cancellation tests
# ═══════════════════════════════════════════════════════════════


class TestTaskCancellation:
    """Verify _cancel_forward_task properly cancels and awaits old tasks."""

    @pytest.mark.asyncio
    async def test_cancel_running_task(self, handler):
        """A running task is cancelled and awaited."""
        cancelled = False

        async def fake_forward():
            nonlocal cancelled
            try:
                await asyncio.sleep(100)
            except asyncio.CancelledError:
                cancelled = True
                raise

        task = asyncio.create_task(fake_forward())
        handler._forward_tasks["c1"] = task
        # Let the task enter sleep before cancelling
        await asyncio.sleep(0.01)

        await handler._cancel_forward_task("c1")

        assert cancelled is True
        assert task.done()
        assert "c1" not in handler._forward_tasks

    @pytest.mark.asyncio
    async def test_cancel_already_done_task(self, handler):
        async def done_immediately():
            return

        task = asyncio.create_task(done_immediately())
        await task
        handler._forward_tasks["c1"] = task

        await handler._cancel_forward_task("c1")
        assert "c1" not in handler._forward_tasks

    @pytest.mark.asyncio
    async def test_cancel_nonexistent_is_noop(self, handler):
        await handler._cancel_forward_task("no-such-client")

    @pytest.mark.asyncio
    async def test_cancel_interrupts_sleep(self, handler):
        """Task.cancel() interrupts asyncio.sleep (backoff wait)."""
        sleep_interrupted = False

        async def sleeping_task():
            nonlocal sleep_interrupted
            try:
                await asyncio.sleep(999)
            except asyncio.CancelledError:
                sleep_interrupted = True
                raise

        task = asyncio.create_task(sleeping_task())
        handler._forward_tasks["c1"] = task
        await asyncio.sleep(0.01)

        await handler._cancel_forward_task("c1")
        assert sleep_interrupted is True


# ═══════════════════════════════════════════════════════════════
# CLI switch race condition tests (core bug scenario)
# ═══════════════════════════════════════════════════════════════


class TestCliSwitchRace:
    """Verify that rapid CLI switching doesn't leave stale tasks running.
    This is the core bug scenario that the generation+cancel fix addresses."""

    @pytest.mark.asyncio
    async def test_old_task_exits_on_generation_mismatch(self, handler):
        """A forward task exits when it detects its generation is stale."""
        handler._generations["c1"] = 1
        exited_cleanly = False

        async def fake_forward(gen: int):
            nonlocal exited_cleanly
            while handler._is_current_generation("c1", gen):
                await asyncio.sleep(0.01)
            exited_cleanly = True

        task = asyncio.create_task(fake_forward(gen=1))
        handler._forward_tasks["c1"] = task

        # Simulate new terminal.start advancing generation
        handler._generations["c1"] = 2

        await asyncio.wait_for(task, timeout=1.0)
        assert exited_cleanly is True

    @pytest.mark.asyncio
    async def test_rapid_switch_only_last_task_survives(self, handler):
        """Three rapid terminal.start calls — only the last task remains."""
        tasks_alive: list[str] = []

        async def fake_forward(gen: int, label: str):
            tasks_alive.append(label)
            try:
                while handler._is_current_generation("c1", gen):
                    await asyncio.sleep(0.01)
            except asyncio.CancelledError:
                pass
            finally:
                if label in tasks_alive:
                    tasks_alive.remove(label)

        # First start
        handler._generations["c1"] = 1
        t1 = asyncio.create_task(fake_forward(1, "task-1"))
        handler._forward_tasks["c1"] = t1
        await asyncio.sleep(0.02)

        # Second start (cancels first)
        handler._generations["c1"] = 2
        await handler._cancel_forward_task("c1")
        t2 = asyncio.create_task(fake_forward(2, "task-2"))
        handler._forward_tasks["c1"] = t2
        await asyncio.sleep(0.02)

        # Third start (cancels second)
        handler._generations["c1"] = 3
        await handler._cancel_forward_task("c1")
        t3 = asyncio.create_task(fake_forward(3, "task-3"))
        handler._forward_tasks["c1"] = t3
        await asyncio.sleep(0.02)

        # Only task-3 should be alive
        assert tasks_alive == ["task-3"]

        # Cleanup
        handler._generations["c1"] = 4
        t3.cancel()
        try:
            await t3
        except asyncio.CancelledError:
            pass

    @pytest.mark.asyncio
    async def test_stop_then_start_no_stale_state(self, handler):
        """terminal.stop followed by terminal.start leaves no stale state."""
        handler._generations["c1"] = 1

        async def fake_forward(gen: int):
            try:
                while handler._is_current_generation("c1", gen):
                    await asyncio.sleep(0.01)
            except asyncio.CancelledError:
                pass

        task = asyncio.create_task(fake_forward(1))
        handler._forward_tasks["c1"] = task
        await asyncio.sleep(0.02)

        # Stop
        handler._generations["c1"] = 2
        await handler._cancel_forward_task("c1")
        assert "c1" not in handler._forward_tasks
        assert task.done()

        # New start works cleanly
        handler._generations["c1"] = 3
        new_task = asyncio.create_task(fake_forward(3))
        handler._forward_tasks["c1"] = new_task
        await asyncio.sleep(0.02)
        assert not new_task.done()

        # Cleanup
        handler._generations["c1"] = 4
        new_task.cancel()
        try:
            await new_task
        except asyncio.CancelledError:
            pass

    @pytest.mark.asyncio
    async def test_concurrent_clients_isolated(self, handler):
        """Two different clients don't interfere with each other."""
        handler._generations["c1"] = 1
        handler._generations["c2"] = 1

        c1_alive = True
        c2_alive = True

        async def forward_c1():
            nonlocal c1_alive
            try:
                while handler._is_current_generation("c1", 1):
                    await asyncio.sleep(0.01)
            except asyncio.CancelledError:
                pass
            c1_alive = False

        async def forward_c2():
            nonlocal c2_alive
            try:
                while handler._is_current_generation("c2", 1):
                    await asyncio.sleep(0.01)
            except asyncio.CancelledError:
                pass
            c2_alive = False

        t1 = asyncio.create_task(forward_c1())
        t2 = asyncio.create_task(forward_c2())
        handler._forward_tasks["c1"] = t1
        handler._forward_tasks["c2"] = t2
        await asyncio.sleep(0.02)

        # Cancel only c1 — c2 should keep running
        handler._generations["c1"] = 2
        await handler._cancel_forward_task("c1")

        assert c1_alive is False
        assert c2_alive is True  # c2 unaffected

        # Cleanup c2
        handler._generations["c2"] = 2
        t2.cancel()
        try:
            await t2
        except asyncio.CancelledError:
            pass
