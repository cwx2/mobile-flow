"""Hot-reload manager for connection modes.

Module: services/
Responsibility:
    Manage the lifecycle of Tunnel and Relay asyncio tasks, providing
    cancel-and-restart semantics for configuration changes from the Dashboard.

    LAN mode is never touched — it runs independently as the always-on
    baseline connection.

Called by:
    - server/dashboard_api.py (after config save triggers reload)
    - server/websocket.py (registers initial tasks on startup)
"""

from __future__ import annotations

import asyncio
from typing import Any, Callable, Coroutine, Literal, Optional, TYPE_CHECKING

from loguru import logger
from pydantic import BaseModel

if TYPE_CHECKING:
    from .user_config import ConnectionConfigData


class ModeStatus(BaseModel):
    """Status of a single connection mode.

    Attributes:
        status: Current state — "active", "inactive", or "error".
        error: Descriptive error message when status is "error".
        port: Listening port (for Tunnel when active).
        url: Server URL (for Relay when active).
        address: Listening address (for LAN, e.g. "0.0.0.0:9600").
    """

    status: Literal["active", "inactive", "error"] = "inactive"
    error: Optional[str] = None
    port: Optional[int] = None
    url: Optional[str] = None
    address: Optional[str] = None


class HotReloadManager:
    """Manages hot-reload of Tunnel and Relay connection modes.

    Holds references to the asyncio.Task for each mode. On reload:
    1. Cancel the existing task (if running)
    2. Wait for cancellation to complete (with timeout)
    3. Update AgentConfig with new values
    4. Start a new task with updated config

    LAN mode is never touched — it runs independently.

    Attributes:
        _ws_server: Reference to the WebSocketServer for accessing config
            and starting new connection tasks.
        _tunnel_task: The asyncio.Task running the Tunnel server.
        _relay_task: The asyncio.Task running the Relay client.
        _mode_status: Current status of each connection mode.
    """

    # Timeout for cancelling an existing task before force-killing
    _CANCEL_TIMEOUT = 5.0

    def __init__(self, ws_server: Any):
        self._ws_server = ws_server
        self._tunnel_task: Optional[asyncio.Task] = None
        self._relay_task: Optional[asyncio.Task] = None
        self._mode_status: dict[str, ModeStatus] = {
            "lan": ModeStatus(status="inactive"),
            "tunnel": ModeStatus(status="inactive"),
            "relay": ModeStatus(status="inactive"),
        }

    # ── Status management ──

    def set_lan_active(self, host: str, port: int) -> None:
        """Mark LAN mode as active with its listening address.

        Args:
            host: Listening host.
            port: Listening port.
        """
        self._mode_status["lan"] = ModeStatus(
            status="active", address=f"{host}:{port}"
        )

    def set_tunnel_active(self, port: int) -> None:
        """Mark Tunnel mode as active.

        Args:
            port: Tunnel listening port.
        """
        self._mode_status["tunnel"] = ModeStatus(status="active", port=port)

    def set_tunnel_inactive(self) -> None:
        """Mark Tunnel mode as inactive."""
        self._mode_status["tunnel"] = ModeStatus(status="inactive")

    def set_tunnel_error(self, error: str) -> None:
        """Mark Tunnel mode as errored.

        Args:
            error: Descriptive error message.
        """
        self._mode_status["tunnel"] = ModeStatus(status="error", error=error)

    def set_relay_active(self, url: str) -> None:
        """Mark Relay mode as active.

        Args:
            url: Relay Server URL.
        """
        self._mode_status["relay"] = ModeStatus(status="active", url=url)

    def set_relay_inactive(self) -> None:
        """Mark Relay mode as inactive."""
        self._mode_status["relay"] = ModeStatus(status="inactive")

    def set_relay_error(self, error: str) -> None:
        """Mark Relay mode as errored.

        Args:
            error: Descriptive error message.
        """
        self._mode_status["relay"] = ModeStatus(status="error", error=error)

    def get_status(self) -> dict[str, ModeStatus]:
        """Return current status of all three modes.

        Returns:
            Dict with keys "lan", "tunnel", "relay" mapping to ModeStatus.
        """
        return dict(self._mode_status)

    # ── Task registration ──

    def register_tunnel_task(self, task: asyncio.Task) -> None:
        """Register the initial Tunnel task created during startup.

        Args:
            task: The asyncio.Task running _start_tunnel_mode.
        """
        self._tunnel_task = task

    def register_relay_task(self, task: asyncio.Task) -> None:
        """Register the initial Relay task created during startup.

        Args:
            task: The asyncio.Task running _start_relay_mode.
        """
        self._relay_task = task

    # ── Hot reload ──

    async def reload_tunnel(self, start_fn: Callable[[], Coroutine]) -> None:
        """Stop existing Tunnel server and start a new one.

        Args:
            start_fn: Async function that starts the Tunnel server
                (e.g. ws_server._start_tunnel_mode). Should update
                config before calling this.
        """
        logger.info("🔄 Tunnel 热加载: 停止旧服务...")

        # Cancel existing task
        if self._tunnel_task and not self._tunnel_task.done():
            self._tunnel_task.cancel()
            try:
                await asyncio.wait_for(self._tunnel_task, timeout=self._CANCEL_TIMEOUT)
            except (asyncio.CancelledError, asyncio.TimeoutError):
                pass
            except Exception as e:
                logger.warning(f"Tunnel 任务取消异常: {e}")

        self._tunnel_task = None
        self.set_tunnel_inactive()

        # Start new task
        try:
            self._tunnel_task = asyncio.create_task(start_fn())
            # Give it a moment to start and report status
            await asyncio.sleep(0.5)
            logger.info("🔄 Tunnel 热加载完成")
        except Exception as e:
            error_msg = f"Tunnel 启动失败: {e}"
            logger.error(error_msg)
            self.set_tunnel_error(error_msg)

    async def reload_relay(self, start_fn: Callable[[], Coroutine]) -> None:
        """Disconnect existing Relay and connect to new URL.

        Args:
            start_fn: Async function that starts the Relay client
                (e.g. ws_server._start_relay_mode). Should update
                config before calling this.
        """
        logger.info("🔄 Relay 热加载: 断开旧连接...")

        # Cancel existing task
        if self._relay_task and not self._relay_task.done():
            self._relay_task.cancel()
            try:
                await asyncio.wait_for(self._relay_task, timeout=self._CANCEL_TIMEOUT)
            except (asyncio.CancelledError, asyncio.TimeoutError):
                pass
            except Exception as e:
                logger.warning(f"Relay 任务取消异常: {e}")

        self._relay_task = None
        self.set_relay_inactive()

        # Start new task
        try:
            self._relay_task = asyncio.create_task(start_fn())
            await asyncio.sleep(0.5)
            logger.info("🔄 Relay 热加载完成")
        except Exception as e:
            error_msg = f"Relay 启动失败: {e}"
            logger.error(error_msg)
            self.set_relay_error(error_msg)

    async def stop_tunnel(self) -> None:
        """Stop the Tunnel server without restarting (user cleared config)."""
        if self._tunnel_task and not self._tunnel_task.done():
            self._tunnel_task.cancel()
            try:
                await asyncio.wait_for(self._tunnel_task, timeout=self._CANCEL_TIMEOUT)
            except (asyncio.CancelledError, asyncio.TimeoutError):
                pass
        self._tunnel_task = None
        self.set_tunnel_inactive()
        logger.info("Tunnel 已停止")

    async def stop_relay(self) -> None:
        """Stop the Relay client without reconnecting (user cleared config)."""
        if self._relay_task and not self._relay_task.done():
            self._relay_task.cancel()
            try:
                await asyncio.wait_for(self._relay_task, timeout=self._CANCEL_TIMEOUT)
            except (asyncio.CancelledError, asyncio.TimeoutError):
                pass
        self._relay_task = None
        self.set_relay_inactive()
        logger.info("Relay 已停止")
