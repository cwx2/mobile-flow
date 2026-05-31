"""Daemon HTTP control server for local inter-process communication.

Listens on ``127.0.0.1`` with a random port and exposes endpoints for
managing the daemon from the CLI or other local processes.

Endpoints:
    POST /stop    — gracefully shut down the daemon.
    GET  /status  — return current daemon status.
    GET  /devices — return the list of paired devices.

Reference: Happy ``daemon/controlServer.ts``.
"""

from __future__ import annotations

import json
from typing import Any, Callable, Coroutine, Optional

from aiohttp import web
from loguru import logger


class ControlServer:
    """Local HTTP control server for the daemon process.

    Attributes:
        port: The TCP port the server is listening on (0 until started).
    """

    def __init__(
        self,
        on_stop: Callable[[], Coroutine],
        get_status: Callable[[], dict[str, Any]],
        get_devices: Callable[[], list[dict[str, Any]]],
    ):
        self._on_stop = on_stop
        self._get_status = get_status
        self._get_devices = get_devices
        self._app = web.Application()
        self._runner: Optional[web.AppRunner] = None
        self._port: int = 0

        # Register routes
        self._app.router.add_post("/stop", self._handle_stop)
        self._app.router.add_get("/status", self._handle_status)
        self._app.router.add_get("/devices", self._handle_devices)

    @property
    def port(self) -> int:
        """The TCP port the server is listening on."""
        return self._port

    async def start(self) -> int:
        """Start the HTTP server on a random available port.

        Returns:
            The actual port number the server bound to.
        """
        self._runner = web.AppRunner(self._app)
        await self._runner.setup()
        site = web.TCPSite(self._runner, "127.0.0.1", 0)
        await site.start()
        # Retrieve the actual port assigned by the OS
        self._port = site._server.sockets[0].getsockname()[1]
        logger.debug(f"控制服务器启动: http://127.0.0.1:{self._port}")
        return self._port

    async def stop(self) -> None:
        """Stop the HTTP server and release resources."""
        if self._runner:
            await self._runner.cleanup()
            logger.debug("控制服务器已停止")

    async def _handle_stop(self, request: web.Request) -> web.Response:
        """POST /stop — request a graceful daemon shutdown."""
        logger.info("收到停止请求")
        await self._on_stop()
        return web.json_response({"status": "stopping"})

    async def _handle_status(self, request: web.Request) -> web.Response:
        """GET /status — return the current daemon status."""
        logger.debug("控制服务器: 收到 /status 请求")
        return web.json_response(self._get_status())

    async def _handle_devices(self, request: web.Request) -> web.Response:
        """GET /devices — return the list of paired devices."""
        return web.json_response(self._get_devices())
