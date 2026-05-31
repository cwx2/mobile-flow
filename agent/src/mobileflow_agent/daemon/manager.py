"""Daemon main manager.

Responsibility:
    1. Start / stop the daemon process.
    2. Manage the exclusive lock, state file, and HTTP control server.
    3. Run the heartbeat loop (60 s interval).
    4. Connect to the Relay Server (if remote mode is configured).

Reference: Happy ``daemon/run.ts`` ``startDaemon``.
"""

from __future__ import annotations

import asyncio
import os
import signal
import time
from dataclasses import asdict
from typing import Any

from loguru import logger

from ..core.config import AgentConfig
from ..crypto.key_store import KeyStore
from ..utils.process import is_process_alive, kill_process_tree_sync
from .lock import DaemonLock
from .state import read_daemon_state, write_daemon_state, delete_daemon_state
from .control_server import ControlServer


class DaemonManager:
    """Main daemon lifecycle manager.

    Lifecycle (following Happy ``daemon/run.ts``):
        1. Check for an existing running daemon.
        2. Acquire the exclusive lock.
        3. Start the HTTP control server.
        4. Connect to the Relay Server (if configured).
        5. Write the state file.
        6. Start the heartbeat loop.
        7. Wait for a shutdown signal.

    Attributes:
        config: Agent configuration.
    """

    def __init__(self, config: AgentConfig):
        self.config = config
        self._lock = DaemonLock(config.data_dir)
        self._key_store = KeyStore(data_dir=config.data_dir)
        self._control: ControlServer | None = None
        self._shutdown_event = asyncio.Event()
        self._heartbeat_task: asyncio.Task | None = None

    async def start(self) -> None:
        """Start the daemon process.

        Checks for an existing instance, acquires the lock, starts the
        control server, writes the state file, and enters the heartbeat loop.
        """
        logger.info("🚀 Daemon 启动中...")

        # 1. Check for an existing running daemon
        existing = read_daemon_state(self.config.data_dir)
        if existing:
            pid = existing.get("pid")
            if pid and self._is_process_alive(pid):
                logger.warning(f"Daemon 已在运行 (PID: {pid})")
                return
            else:
                logger.info("发现残留状态文件，清理中...")
                delete_daemon_state(self.config.data_dir)

        # 2. Acquire the exclusive lock
        if not self._lock.acquire():
            logger.error("无法获取独占锁，可能有其他 daemon 运行")
            return

        try:
            # 3. Start the HTTP control server
            self._control = ControlServer(
                on_stop=self._request_shutdown,
                get_status=self._get_status,
                get_devices=self._get_devices,
            )
            http_port = await self._control.start()

            # 4. Write the state file
            write_daemon_state(self.config.data_dir, {
                "pid": os.getpid(),
                "http_port": http_port,
                "start_time": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "version": "0.1.0",
                "last_heartbeat": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "relay_connected": False,
                "paired_devices": len(self._key_store.list_devices()),
            })

            # 5. Register signal handlers for graceful shutdown
            loop = asyncio.get_event_loop()
            for sig in (signal.SIGINT, signal.SIGTERM):
                try:
                    loop.add_signal_handler(sig, self._shutdown_event.set)
                except NotImplementedError:
                    pass  # Windows does not support add_signal_handler

            # 6. Start the heartbeat loop
            self._heartbeat_task = asyncio.create_task(self._heartbeat_loop())

            logger.info(f"✅ Daemon 已启动 (PID: {os.getpid()}, HTTP: {http_port})")

            # 7. Wait for a shutdown signal
            await self._shutdown_event.wait()

        finally:
            await self._cleanup()

    async def stop(self) -> None:
        """Stop a running daemon by sending a request to its HTTP control server.

        Falls back to sending SIGTERM if the HTTP request fails.
        """
        import aiohttp

        state = read_daemon_state(self.config.data_dir)
        if not state:
            logger.info("Daemon 未运行")
            return

        http_port = state.get("http_port")
        if not http_port:
            logger.warning("状态文件中没有 HTTP 端口")
            return

        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"http://127.0.0.1:{http_port}/stop",
                    timeout=aiohttp.ClientTimeout(total=5),
                ) as resp:
                    if resp.status == 200:
                        logger.info("✅ 已发送停止请求")
                    else:
                        logger.warning(f"停止请求失败: {resp.status}")
        except Exception as e:
            logger.warning(f"HTTP 停止失败，尝试 kill: {e}")
            pid = state.get("pid")
            if pid:
                kill_process_tree_sync(pid)
                logger.info(f"已终止 PID {pid}")

    async def _request_shutdown(self) -> None:
        """Signal the daemon to shut down (called by the HTTP control server)."""
        self._shutdown_event.set()

    async def _cleanup(self) -> None:
        """Release all resources: cancel heartbeat, stop control server, remove state."""
        logger.info("🧹 Daemon 清理中...")

        if self._heartbeat_task:
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                pass

        if self._control:
            await self._control.stop()

        delete_daemon_state(self.config.data_dir)
        self._lock.release()
        logger.info("👋 Daemon 已停止")

    async def _heartbeat_loop(self) -> None:
        """Update the state file every 60 seconds to signal liveness."""
        while not self._shutdown_event.is_set():
            try:
                write_daemon_state(self.config.data_dir, {
                    "pid": os.getpid(),
                    "http_port": self._control.port if self._control else 0,
                    "start_time": time.strftime("%Y-%m-%dT%H:%M:%S"),
                    "version": "0.1.0",
                    "last_heartbeat": time.strftime("%Y-%m-%dT%H:%M:%S"),
                    "relay_connected": False,
                    "paired_devices": len(self._key_store.list_devices()),
                })
            except Exception as e:
                logger.warning(f"心跳写入失败: {e}")

            await asyncio.sleep(60)

    def _get_status(self) -> dict[str, Any]:
        """Return the current daemon status for the control server.

        Returns:
            Dict with pid, http_port, relay status, device count, and mode.
        """
        return {
            "pid": os.getpid(),
            "http_port": self._control.port if self._control else 0,
            "relay_connected": False,
            "paired_devices": len(self._key_store.list_devices()),
            "connection_mode": self.config.connection_mode,
        }

    def _get_devices(self) -> list[dict[str, Any]]:
        """Return the list of paired devices for the control server.

        Returns:
            List of device dicts.
        """
        return [asdict(d) for d in self._key_store.list_devices()]

    @staticmethod
    def _is_process_alive(pid: int) -> bool:
        """Check whether a process with the given PID is still running.

        Args:
            pid: Process ID to check.

        Returns:
            True if the process exists, False otherwise.
        """
        try:
            return is_process_alive(pid)
        except Exception:
            return False
