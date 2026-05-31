"""Tests for TestPanelHandler cleanup logic.

Covers:
- cleanup_client stops running script executors
- cleanup_client stops running preview executors
- cleanup_client deactivates port proxy
- cleanup_client is safe to call when nothing is running
"""

from unittest.mock import AsyncMock, MagicMock

import pytest

from mobileflow_agent.server.handlers.test_panel_handler import TestPanelHandler


@pytest.fixture
def handler():
    """Create a TestPanelHandler with mocked server."""
    server = MagicMock()
    server.config = MagicMock()
    server.config.work_dir = "/tmp/test"
    server.config.port = 9600
    server.plugin_registry = MagicMock()

    # TestPanelHandler inherits from BaseHandler which has config as a property
    # reading from self._server.config. We mock the server directly.
    h = MagicMock(spec=TestPanelHandler)
    h._executors = {}
    h._preview_executors = {}
    h._port_proxy = AsyncMock()
    h._port_detector = MagicMock()
    h._preview_active = False
    # Bind the real cleanup_client method to our mock
    h.cleanup_client = TestPanelHandler.cleanup_client.__get__(h, TestPanelHandler)
    return h


class TestCleanupClient:
    """Test cleanup_client method for zombie process prevention."""

    @pytest.mark.asyncio
    async def test_stops_running_script_executor(self, handler):
        """cleanup_client stops a running script executor."""
        mock_executor = AsyncMock()
        mock_executor.is_running = True
        handler._executors["client-123"] = mock_executor

        await handler.cleanup_client("client-123")

        mock_executor.stop.assert_called_once()
        assert "client-123" not in handler._executors

    @pytest.mark.asyncio
    async def test_stops_running_preview_executor(self, handler):
        """cleanup_client stops a running preview executor."""
        mock_executor = AsyncMock()
        mock_executor.is_running = True
        handler._preview_executors["client-123"] = mock_executor

        await handler.cleanup_client("client-123")

        mock_executor.stop.assert_called_once()
        assert "client-123" not in handler._preview_executors

    @pytest.mark.asyncio
    async def test_deactivates_port_proxy_when_preview_active(self, handler):
        """cleanup_client deactivates port proxy if preview was active."""
        handler._preview_active = True

        await handler.cleanup_client("client-123")

        handler._port_proxy.deactivate.assert_called_once()
        assert handler._preview_active is False

    @pytest.mark.asyncio
    async def test_skips_port_proxy_when_preview_inactive(self, handler):
        """cleanup_client does not touch port proxy if no preview was active."""
        handler._preview_active = False

        await handler.cleanup_client("client-123")

        handler._port_proxy.deactivate.assert_not_called()

    @pytest.mark.asyncio
    async def test_skips_stopped_executors(self, handler):
        """cleanup_client does not call stop on already-stopped executors."""
        mock_executor = AsyncMock()
        mock_executor.is_running = False
        handler._executors["client-123"] = mock_executor

        await handler.cleanup_client("client-123")

        mock_executor.stop.assert_not_called()

    @pytest.mark.asyncio
    async def test_safe_when_no_executors_exist(self, handler):
        """cleanup_client is safe to call when client has no executors."""
        await handler.cleanup_client("nonexistent-client")
        # Should not raise

    @pytest.mark.asyncio
    async def test_cleans_both_script_and_preview(self, handler):
        """cleanup_client stops both script and preview executors."""
        script_exec = AsyncMock()
        script_exec.is_running = True
        preview_exec = AsyncMock()
        preview_exec.is_running = True

        handler._executors["client-123"] = script_exec
        handler._preview_executors["client-123"] = preview_exec
        handler._preview_active = True

        await handler.cleanup_client("client-123")

        script_exec.stop.assert_called_once()
        preview_exec.stop.assert_called_once()
        handler._port_proxy.deactivate.assert_called_once()
