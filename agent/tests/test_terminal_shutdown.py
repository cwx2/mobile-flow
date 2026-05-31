"""Terminal shutdown tests — verifies clean exit during Agent shutdown.

Simulates the real scenario: terminal is running with auto-restart enabled,
Agent receives shutdown signal, terminal forward task must exit cleanly
without attempting to restart the CLI.

Bug context:
    Before this fix, _forward_with_restart only checked scope.is_alive
    (which checks _disposed). During shutdown, scope.cancelled is set
    BEFORE dispose runs, but the restart loop didn't check cancelled.
    This caused the loop to attempt CLI restart after "Agent 已优雅关闭",
    producing "Task was destroyed but it is pending" errors.

# Feature: terminal-shutdown-cleanup
"""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, MagicMock

import pytest

from mobileflow_agent.core.client_scope import ClientScope
from mobileflow_agent.server.handlers.terminal_handler import TerminalHandler


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
# Basic scope check tests
# ═══════════════════════════════════════════════════════════════


class TestForwardExitsOnScopeCancelled:
    """Verify _forward_with_restart exits when scope.cancelled is set."""

    @pytest.mark.asyncio
    async def test_exits_when_scope_cancelled_before_start(self, handler, mock_server):
        """Forward loop exits immediately when scope.cancelled is already set."""
        client_id = "test-client-1"
        scope = ClientScope(client_id)
        mock_server._scopes = {client_id: scope}
        scope.cancelled.set()
        handler._generations[client_id] = 1

        session = MagicMock()
        session.read_output = AsyncMock(return_value=iter([]))
        ws = AsyncMock()

        await handler._forward_with_restart(
            client_id, ws, session, "test-cli", "/usr/bin/test",
            "native", 80, 24, generation=1,
        )

        mock_server.terminal_manager.create_session.assert_not_called()

    @pytest.mark.asyncio
    async def test_exits_when_scope_disposed(self, handler, mock_server):
        """Forward loop exits when scope is fully disposed."""
        client_id = "test-client-2"
        scope = ClientScope(client_id)
        mock_server._scopes = {client_id: scope}
        await scope.dispose()
        handler._generations[client_id] = 1

        session = MagicMock()
        session.read_output = AsyncMock(return_value=iter([]))
        ws = AsyncMock()

        await handler._forward_with_restart(
            client_id, ws, session, "test-cli", "/usr/bin/test",
            "native", 80, 24, generation=1,
        )

        mock_server.terminal_manager.create_session.assert_not_called()

    @pytest.mark.asyncio
    async def test_exits_when_scope_missing(self, handler, mock_server):
        """Forward loop exits when scope is removed from _scopes dict."""
        client_id = "test-client-3"
        mock_server._scopes = {}
        handler._generations[client_id] = 1

        session = MagicMock()
        session.read_output = AsyncMock(return_value=iter([]))
        ws = AsyncMock()

        await handler._forward_with_restart(
            client_id, ws, session, "test-cli", "/usr/bin/test",
            "native", 80, 24, generation=1,
        )

        mock_server.terminal_manager.create_session.assert_not_called()


# ═══════════════════════════════════════════════════════════════
# Realistic integration tests
# ═══════════════════════════════════════════════════════════════


class TestRealisticShutdownScenario:
    """Simulate the real user scenario that caused the bug:

    1. Terminal is running, forwarding CLI output to the App.
    2. CLI exits (output loop ends).
    3. Forward loop enters restart decision phase.
    4. Meanwhile, Agent shutdown starts → scope.cancelled.set().
    5. Forward loop must detect cancelled and exit WITHOUT restarting.

    Before the fix, step 5 would attempt restart because only
    scope.is_alive was checked (which is still True until dispose runs).
    """

    @pytest.mark.asyncio
    async def test_cli_exits_then_shutdown_cancels_restart(self, handler, mock_server):
        """CLI exits normally, then shutdown fires during restart backoff.

        Real scenario: user is in terminal, CLI crashes, forward loop
        starts the 1s restart backoff. During that 1s, user presses 'q'
        to quit Agent. The restart must be aborted.
        """
        client_id = "real-scenario-1"
        scope = ClientScope(client_id)
        mock_server._scopes = {client_id: scope}
        handler._generations[client_id] = 1

        output_chunks = [b"line 1\r\n", b"line 2\r\n"]
        chunks_yielded = 0

        # Simulate a session that outputs 2 chunks then exits (CLI crash)
        async def real_output():
            nonlocal chunks_yielded
            for chunk in output_chunks:
                chunks_yielded += 1
                yield chunk

        session = MagicMock()
        session.read_output = real_output

        ws = AsyncMock()

        # Simulate shutdown happening 0.1s after CLI exits.
        # The restart backoff is 1s, so shutdown fires during the sleep.
        async def simulate_shutdown():
            # Wait for output to finish + a bit of processing time
            while chunks_yielded < 2:
                await asyncio.sleep(0.01)
            await asyncio.sleep(0.05)
            # This is what scope.dispose() does first
            scope.cancelled.set()

        shutdown_task = asyncio.create_task(simulate_shutdown())

        await handler._forward_with_restart(
            client_id, ws, session, "test-cli", "/usr/bin/test",
            "native", 80, 24, generation=1,
        )

        await shutdown_task

        # Output was forwarded
        assert ws.send.call_count == 2

        # But NO restart was attempted
        mock_server.terminal_manager.create_session.assert_not_called()

    @pytest.mark.asyncio
    async def test_output_error_then_shutdown_prevents_restart(self, handler, mock_server):
        """Output forwarding throws error, then shutdown prevents restart.

        Real scenario: WebSocket closes (client disconnects), output
        forwarding raises ConnectionError. Before restart can happen,
        scope gets cancelled by the disconnect grace period logic.
        """
        client_id = "real-scenario-2"
        scope = ClientScope(client_id)
        mock_server._scopes = {client_id: scope}
        handler._generations[client_id] = 1

        # Session that outputs one chunk then raises error
        async def error_output():
            yield b"partial output\r\n"
            raise ConnectionError("WebSocket closed")

        session = MagicMock()
        session.read_output = error_output

        ws = AsyncMock()

        # Cancel scope shortly after the error
        async def cancel_after_error():
            await asyncio.sleep(0.05)
            scope.cancelled.set()

        cancel_task = asyncio.create_task(cancel_after_error())

        await handler._forward_with_restart(
            client_id, ws, session, "test-cli", "/usr/bin/test",
            "native", 80, 24, generation=1,
        )

        await cancel_task

        # One chunk was sent before the error
        assert ws.send.call_count == 1

        # No restart attempted
        mock_server.terminal_manager.create_session.assert_not_called()

    @pytest.mark.asyncio
    async def test_task_cancel_during_output_forwarding(self, handler, mock_server):
        """Task.cancel() interrupts the output forwarding loop.

        Real scenario: scope.dispose() calls task.cancel() while the
        forward loop is blocked on session.read_output(). The
        CancelledError must propagate cleanly without restart.
        """
        client_id = "real-scenario-3"
        scope = ClientScope(client_id)
        mock_server._scopes = {client_id: scope}
        handler._generations[client_id] = 1

        # Session that blocks forever (simulates a running CLI)
        async def blocking_output():
            yield b"initial output\r\n"
            # Block until cancelled
            await asyncio.sleep(999)
            yield b"never reached"

        session = MagicMock()
        session.read_output = blocking_output

        ws = AsyncMock()

        # Run forward in a task so we can cancel it
        task = asyncio.create_task(
            handler._forward_with_restart(
                client_id, ws, session, "test-cli", "/usr/bin/test",
                "native", 80, 24, generation=1,
            )
        )

        # Let it start and send the first chunk
        await asyncio.sleep(0.05)
        assert ws.send.call_count == 1

        # Cancel the task (simulates scope.dispose() → task.cancel())
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass  # Expected — CancelledError propagated cleanly

        # No restart attempted
        mock_server.terminal_manager.create_session.assert_not_called()


# ═══════════════════════════════════════════════════════════════
# ClientScope reset tests
# ═══════════════════════════════════════════════════════════════


class TestScopeResetForReconnect:
    """Verify ClientScope.reset() works correctly for reconnection."""

    @pytest.mark.asyncio
    async def test_reset_clears_cancelled(self):
        """reset() clears the cancelled event for scope reuse."""
        scope = ClientScope("test")
        scope.cancelled.set()
        assert scope.cancelled.is_set()

        scope.reset()
        assert not scope.cancelled.is_set()
        assert scope.is_alive

    @pytest.mark.asyncio
    async def test_reset_noop_after_dispose(self):
        """reset() does nothing if scope is already disposed."""
        scope = ClientScope("test")
        await scope.dispose()
        assert not scope.is_alive

        scope.reset()
        assert not scope.is_alive
