"""Test Panel handler for all test panel protocol messages.

Module: server/handlers/
Responsibility:
    Handle script.*, preview.*, api.*, screenshot.*, and visual_diff.*
    messages from the App. Routes commands to the appropriate service
    (CommandExecutor, PortProxy, HttpProxy, ScreenshotService,
    VisualDiffService) and streams results back to the client.

Supported message types:
    - script.run / script.stop: command execution
    - preview.start / preview.stop: dev server + port proxy
    - preview.file_changed: auto-refresh notification
    - api.request: HTTP proxy forwarding
    - screenshot.capture: headless browser capture
    - visual_diff.start / visual_diff.compare: before/after comparison
    - preview.detect / runtime.resolve: plugin queries

Called by:
    WebSocketServer message router.
"""

from __future__ import annotations

import asyncio
import socket

import aiohttp
from loguru import logger

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.payloads.test_panel import (
    ApiErrorPayload,
    ApiRequestPayload,
    ApiResponsePayload,
    PreviewOutputPayload,
    PreviewReadyPayload,
    PreviewStartPayload,
    PreviewStoppedPayload,
    ScreenshotCapturePayload,
    ScreenshotErrorPayload,
    ScreenshotResultPayload,
    ScriptDonePayload,
    ScriptOutputPayload,
    ScriptRunPayload,
    VisualDiffResultPayload,
    VisualDiffStartPayload,
)
from mobileflow_protocol.types import MessageType

from ...services.command_executor import CommandAlreadyRunningError, CommandExecutor
from ...services.http_proxy import HttpProxy
from ...services.port_detector import PortDetector
from ...services.port_proxy import PortProxy
from ...services.screenshot_service import ScreenshotService
from ...services.visual_diff_service import VisualDiffService
from .base import BaseHandler


class TestPanelHandler(BaseHandler):
    """Handles test panel protocol messages (script.*, api.*, preview.*, etc.).

    Implements all test panel message routing: script execution, preview
    management with PortProxy + PortDetector, API proxy forwarding,
    screenshot capture, and visual diff comparison.

    Each client gets its own CommandExecutor instance to enforce
    single-command-per-session semantics.

    Attributes:
        _executors: Per-client CommandExecutor instances.
        _port_proxy: Shared PortProxy instance for preview forwarding.
        _preview_executors: Per-client CommandExecutor for preview commands.
        _port_detector: Shared PortDetector for auto port detection.
        _http_proxy: Shared HttpProxy for API request forwarding.
        _screenshot_service: Shared ScreenshotService for captures.
        _visual_diff_service: Shared VisualDiffService for comparisons.
        _preview_active: Whether a preview session is currently active.
    """

    def __init__(self, server, port_proxy: PortProxy | None = None):
        super().__init__(server)
        self._executors: dict[str, CommandExecutor] = {}
        self._preview_executors: dict[str, CommandExecutor] = {}
        self._port_proxy = port_proxy or PortProxy(config=self.config)
        self._port_detector = PortDetector()
        self._http_proxy = HttpProxy()
        self._screenshot_service = ScreenshotService()
        self._visual_diff_service = VisualDiffService(self._screenshot_service)
        self._preview_active = False

    @property
    def port_proxy(self) -> PortProxy:
        """The shared PortProxy instance."""
        return self._port_proxy

    @property
    def preview_active(self) -> bool:
        """Whether a preview session is currently active."""
        return self._preview_active

    async def cleanup_client(self, client_id: str) -> None:
        """Stop all running subprocesses for a disconnected client.

        Called when a client scope is disposed (disconnect + grace period
        expired). Prevents zombie processes from accumulating.

        Args:
            client_id: Identifier of the disconnected client.
        """
        # Stop script executor
        executor = self._executors.pop(client_id, None)
        if executor and executor.is_running:
            logger.info(f"清理断连客户端的脚本进程: client={client_id[:8]}...")
            await executor.stop()

        # Stop preview executor
        preview_exec = self._preview_executors.pop(client_id, None)
        if preview_exec and preview_exec.is_running:
            logger.info(f"清理断连客户端的预览进程: client={client_id[:8]}...")
            await preview_exec.stop()

        # Deactivate port proxy if this client owned it
        if self._preview_active:
            self._preview_active = False
            await self._port_proxy.deactivate()

    def _get_executor(self, client_id: str) -> CommandExecutor:
        """Get or create a CommandExecutor for the given client.

        Each client has its own executor to enforce single-instance
        semantics independently per session.

        Args:
            client_id: Identifier of the requesting client.

        Returns:
            The CommandExecutor instance for this client.
        """
        if client_id not in self._executors:
            self._executors[client_id] = CommandExecutor(self.config)
        return self._executors[client_id]

    async def handle_script_run(self, client_id, ws, msg):
        """Handle script.run — execute a command and stream output.

        Validates the ScriptRunPayload, checks that no command is already
        running for this client, then starts the subprocess. Output is
        streamed back as script.output messages, and script.done is sent
        when the process terminates.

        If a command is already running, immediately sends script.done
        with status="error" instead of starting a new one.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ScriptRunPayload.
        """
        payload = msg.typed_payload(ScriptRunPayload)
        executor = self._get_executor(client_id)

        logger.info(
            f"script.run: client={client_id[:8]}..., "
            f"command={payload.command!r}, cwd={payload.working_directory}"
        )

        # Reject if a command is already running
        if executor.is_running:
            logger.warning(f"script.run 拒绝: 已有命令在运行, client={client_id[:8]}...")
            await self.send(ws, Message.from_typed(
                MessageType.SCRIPT_DONE,
                ScriptDonePayload(
                    exit_code=-1,
                    status="error",
                    error_message="A command is already running. Stop it first.",
                ),
            ))
            return

        # Define callbacks that send messages back to the client
        async def on_output(stream: str, data: str) -> None:
            """Forward subprocess output to the App as script.output."""
            await self.send(ws, Message.from_typed(
                MessageType.SCRIPT_OUTPUT,
                ScriptOutputPayload(stream=stream, data=data),
            ))

        async def on_done(exit_code: int, status: str) -> None:
            """Notify the App that the command has finished."""
            logger.info(
                f"script.done: client={client_id[:8]}..., "
                f"exit_code={exit_code}, status={status}"
            )
            await self.send(ws, Message.from_typed(
                MessageType.SCRIPT_DONE,
                ScriptDonePayload(exit_code=exit_code, status=status),
            ))

        # Start execution (runs in the current task context)
        try:
            await executor.run(
                command=payload.command,
                cwd=payload.working_directory,
                env=payload.env,
                on_output=on_output,
                on_done=on_done,
            )
        except CommandAlreadyRunningError:
            # Race condition: another script.run arrived between the check
            # and the actual start. Send error response.
            await self.send(ws, Message.from_typed(
                MessageType.SCRIPT_DONE,
                ScriptDonePayload(
                    exit_code=-1,
                    status="error",
                    error_message="A command is already running. Stop it first.",
                ),
            ))

    async def handle_script_stop(self, client_id, ws, msg):
        """Handle script.stop — stop the running command.

        Sends SIGTERM to the running subprocess. If it doesn't exit
        within 5 seconds, SIGKILL is sent. No-op if no command is running.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (ScriptStopPayload, mostly empty).
        """
        logger.info(f"script.stop: client={client_id[:8]}...")
        executor = self._get_executor(client_id)
        await executor.stop()

    # ── Preview handlers ──

    def _get_preview_executor(self, client_id: str) -> CommandExecutor:
        """Get or create a preview CommandExecutor for the given client.

        Separate from script executors so preview dev server and script
        runner can operate independently.

        Args:
            client_id: Identifier of the requesting client.

        Returns:
            The preview CommandExecutor instance for this client.
        """
        if client_id not in self._preview_executors:
            self._preview_executors[client_id] = CommandExecutor(self.config)
        return self._preview_executors[client_id]

    def _get_agent_lan_ip(self) -> str:
        """Determine the Agent's LAN-accessible IP address.

        Uses a UDP socket trick to find the local IP that can reach
        the internet (and thus the LAN). Falls back to 127.0.0.1.

        Returns:
            LAN IP address string.
        """
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
            return local_ip
        except Exception:
            return "127.0.0.1"

    async def handle_preview_start(self, client_id, ws, msg):
        """Handle preview.start — start dev server and/or activate port proxy.

        Two modes:
        1. Command provided: start subprocess via CommandExecutor, wait for
           port to start listening (via PortDetector), activate PortProxy,
           stream output, send preview.ready.
        2. Command is None ("Connect Only"): activate PortProxy only on the
           specified port, probe port availability, send preview.ready.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with PreviewStartPayload.
        """
        payload = msg.typed_payload(PreviewStartPayload)
        port = payload.port
        command = payload.command
        target_url = payload.target_url
        auto_detect = not target_url and port == 0

        logger.info(
            f"preview.start: client={client_id[:8]}..., "
            f"target_url={target_url!r}, port={'auto' if auto_detect else port}, command={command!r}"
        )

        # Update PortProxy with current agent address
        agent_ip = self._get_agent_lan_ip()
        agent_port = self.config.port
        self._port_proxy.set_agent_address(agent_ip, agent_port)

        if command is None and auto_detect:
            # Neither target URL, port, nor command — invalid request
            logger.warning("preview.start: 无目标地址且无命令，无法启动")
            await self.send(ws, Message.from_typed(
                MessageType.PREVIEW_STOPPED,
                PreviewStoppedPayload(
                    reason="crashed",
                    last_output="Either a target URL, port, or command is required.",
                ),
            ))
            return

        # Determine proxy target
        if target_url:
            # User provided full URL — use it directly
            await self._port_proxy.activate_url(target_url)
        elif port > 0:
            # User provided port — use localhost
            await self._port_proxy.activate(port)
        # else: auto-detect — will activate after port is found

        self._preview_active = True

        if command is None:
            # "Connect Only" mode — no subprocess, just proxy
            # Probe the port to verify it's listening
            detected = await self._port_detector.watch_process(
                pid=0, timeout=5.0, known_port=port
            )
            preview_url = f"http://{agent_ip}:{agent_port}/preview/"
            if detected is None:
                logger.warning(f"preview.start: 端口 {port} 未响应，仍发送 ready")
            logger.info(f"preview.ready (connect only): url={preview_url}")
            await self.send(ws, Message.from_typed(
                MessageType.PREVIEW_READY,
                PreviewReadyPayload(preview_url=preview_url),
            ))
            return

        # Start the dev server command
        executor = self._get_preview_executor(client_id)

        if executor.is_running:
            # Stop existing preview command first
            logger.info("preview.start: 停止已有的预览命令")
            await executor.stop()

        async def on_output(stream: str, data: str) -> None:
            """Forward dev server output to the App as preview.output."""
            await self.send(ws, Message.from_typed(
                MessageType.PREVIEW_OUTPUT,
                PreviewOutputPayload(stream=stream, data=data),
            ))

        async def on_done(exit_code: int, status: str) -> None:
            """Notify the App that the dev server has stopped."""
            reason = "user_stopped" if status == "killed" else "crashed"
            logger.info(
                f"preview.stopped: client={client_id[:8]}..., "
                f"exit_code={exit_code}, reason={reason}"
            )
            self._preview_active = False
            await self._port_proxy.deactivate()
            await self.send(ws, Message.from_typed(
                MessageType.PREVIEW_STOPPED,
                PreviewStoppedPayload(reason=reason),
            ))

        # Start the command (non-blocking via asyncio.create_task)
        preview_url = f"http://{agent_ip}:{agent_port}/preview/"

        # For auto-detect: use output-based port extraction as primary strategy
        # An asyncio.Event signals when port is found from output
        port_found_event = asyncio.Event()
        detected_port_holder: list[int] = []  # mutable container for closure

        # Wrap on_output to also scan for port in output text
        original_on_output = on_output

        async def on_output_with_detection(stream: str, data: str) -> None:
            """Forward output to App and scan for port number."""
            await original_on_output(stream, data)
            # Only scan if we're still looking for a port
            if auto_detect and not port_found_event.is_set():
                extracted = self._port_detector.extract_port_from_output(data)
                if extracted is not None:
                    logger.info(f"从输出中检测到端口: port={extracted}")
                    detected_port_holder.append(extracted)
                    port_found_event.set()

        async def _run_and_probe():
            """Start command and detect port from output or process sockets."""
            # Start the executor in a task
            exec_task = asyncio.create_task(executor.run(
                command=command,
                cwd=payload.working_directory,
                on_output=on_output_with_detection,
                on_done=on_done,
            ))

            # Wait briefly for the process to actually start
            for _ in range(20):
                if executor.pid is not None:
                    break
                await asyncio.sleep(0.1)

            real_pid = executor.pid or 0
            logger.debug(f"preview: 子进程 PID={real_pid}")

            if not auto_detect:
                if target_url:
                    # User provided full URL — wait until it responds
                    # Poll the target URL until it returns a response
                    logger.info(f"等待目标 URL 可达: {target_url}")
                    url_ready = False
                    while not url_ready:
                        if not executor.is_running:
                            return  # Process exited, on_done handles notification
                        try:
                            import ssl as _ssl
                            _ctx = _ssl.create_default_context()
                            _ctx.check_hostname = False
                            _ctx.verify_mode = _ssl.CERT_NONE
                            probe_url = f"{self._port_proxy._target_scheme}://localhost:{self._port_proxy._port}/"
                            async with self._port_proxy._session.get(
                                probe_url,
                                headers={"Host": self._port_proxy._target_host},
                                ssl=_ctx if self._port_proxy._target_scheme == "https" else None,
                                timeout=aiohttp.ClientTimeout(total=3),
                            ) as resp:
                                if resp.status > 0:
                                    url_ready = True
                        except Exception:
                            await asyncio.sleep(2)

                    logger.info(f"preview.ready: target={target_url}, url={preview_url}")
                    await self.send(ws, Message.from_typed(
                        MessageType.PREVIEW_READY,
                        PreviewReadyPayload(preview_url=preview_url),
                    ))
                else:
                    # Known port (no target_url) — wait for it to start listening
                    detected = await self._port_detector.watch_process(
                        pid=real_pid, timeout=600.0, known_port=port
                    )
                    if detected is not None:
                        logger.info(f"preview.ready: port={port}, url={preview_url}")
                        await self.send(ws, Message.from_typed(
                            MessageType.PREVIEW_READY,
                            PreviewReadyPayload(preview_url=preview_url),
                        ))
                    else:
                        if not executor.is_running:
                            return
            else:
                # Auto-detect: race between output parsing and process socket scan
                # Strategy 1: output parsing (via port_found_event, set by on_output)
                # Strategy 2: OS-level socket scan (netstat/ss filtered by PID)
                # No fixed timeout — keep scanning until port found or process exits

                async def _netstat_detect():
                    """Detect port via OS socket state. No timeout — runs until found or cancelled."""
                    # Poll indefinitely until port found or task cancelled
                    return await self._port_detector.watch_process(
                        pid=real_pid, timeout=600.0, known_port=None
                    )

                netstat_task = asyncio.create_task(_netstat_detect())

                # Wait until: output finds port, netstat finds port, or process exits
                while True:
                    if port_found_event.is_set():
                        break
                    if netstat_task.done():
                        break
                    if not executor.is_running:
                        break
                    await asyncio.sleep(0.5)

                # Determine which strategy found the port
                found_port = None
                if detected_port_holder:
                    found_port = detected_port_holder[0]
                    netstat_task.cancel()
                elif netstat_task.done() and not netstat_task.cancelled():
                    found_port = netstat_task.result()
                else:
                    netstat_task.cancel()

                if found_port:
                    await self._port_proxy.activate(found_port)
                    logger.info(f"preview.ready: port={found_port}, url={preview_url}")
                    await self.send(ws, Message.from_typed(
                        MessageType.PREVIEW_READY,
                        PreviewReadyPayload(preview_url=preview_url),
                    ))
                else:
                    if not executor.is_running:
                        return
                    # Process still running but no port found — shouldn't happen
                    logger.warning("preview.start: 进程运行中但未检测到端口")
                    self._preview_active = False
                    await self.send(ws, Message.from_typed(
                        MessageType.PREVIEW_STOPPED,
                        PreviewStoppedPayload(
                            reason="crashed",
                            last_output="Could not detect listening port. Try specifying the port manually.",
                        ),
                    ))
                    return
                # Process running but port not detected — send ready anyway
                # (user specified the port, it might just be slow)
                logger.warning(f"preview.start: 端口探测超时，仍发送 ready: port={port}")
                await self.send(ws, Message.from_typed(
                    MessageType.PREVIEW_READY,
                    PreviewReadyPayload(preview_url=preview_url),
                ))

            # Let the executor task continue running in background
            # (it will call on_done when the process exits)

        try:
            await _run_and_probe()
        except CommandAlreadyRunningError:
            self._preview_active = False
            await self._port_proxy.deactivate()
            await self.send(ws, Message.from_typed(
                MessageType.PREVIEW_STOPPED,
                PreviewStoppedPayload(
                    reason="crashed",
                    last_output="A preview command is already running.",
                ),
            ))

    async def handle_preview_stop(self, client_id, ws, msg):
        """Handle preview.stop — stop dev server and deactivate port proxy.

        Stops the running preview command (if any) and deactivates the
        PortProxy. Sends preview.stopped with reason "user_stopped".

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (PreviewStopPayload, empty).
        """
        logger.info(f"preview.stop: client={client_id[:8]}...")

        # Stop the preview command if running
        executor = self._get_preview_executor(client_id)
        if executor.is_running:
            await executor.stop()

        # Deactivate the port proxy
        self._preview_active = False
        await self._port_proxy.deactivate()

        # Send stopped confirmation
        await self.send(ws, Message.from_typed(
            MessageType.PREVIEW_STOPPED,
            PreviewStoppedPayload(reason="user_stopped"),
        ))

    # ── File change notification ──

    async def handle_file_changed(self, client_id, ws, msg):
        """Handle file change events — forward as preview.file_changed.

        When a preview session is active, file change events from the
        file watcher are forwarded to the App to trigger auto-refresh.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with file change info.
        """
        if not self._preview_active:
            return

        # Forward file change notification to the App
        from mobileflow_protocol.payloads.test_panel import PreviewFileChangedPayload

        await self.send(ws, Message.from_typed(
            MessageType.PREVIEW_FILE_CHANGED,
            PreviewFileChangedPayload(path=msg.payload.get("path", "")),
        ))

    # ── API Proxy handlers ──

    async def handle_api_request(self, client_id, ws, msg):
        """Handle api.request — forward HTTP request via HttpProxy.

        Validates the ApiRequestPayload, calls HttpProxy.forward(),
        and sends api.response or api.error back to the client.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ApiRequestPayload.
        """
        payload = msg.typed_payload(ApiRequestPayload)
        logger.info(
            f"api.request: client={client_id[:8]}..., "
            f"method={payload.method}, url={payload.url[:80]}"
        )

        result = await self._http_proxy.forward(
            url=payload.url,
            method=payload.method,
            headers=payload.headers,
            body=payload.body,
            follow_redirects=payload.follow_redirects,
        )

        if result.get("error"):
            await self.send(ws, Message.from_typed(
                MessageType.API_ERROR,
                ApiErrorPayload(
                    error_type=result["error_type"],
                    message=result["message"],
                    request_id=payload.request_id,
                ),
            ))
        else:
            await self.send(ws, Message.from_typed(
                MessageType.API_RESPONSE,
                ApiResponsePayload(
                    status_code=result["status_code"],
                    headers=result["headers"],
                    body=result["body"],
                    duration_ms=result["duration_ms"],
                    request_id=payload.request_id,
                ),
            ))

    # ── Screenshot handlers ──

    async def handle_screenshot_capture(self, client_id, ws, msg):
        """Handle screenshot.capture — capture a screenshot via Playwright.

        Validates the ScreenshotCapturePayload, calls ScreenshotService,
        and sends screenshot.result or screenshot.error.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ScreenshotCapturePayload.
        """
        payload = msg.typed_payload(ScreenshotCapturePayload)
        logger.info(
            f"screenshot.capture: client={client_id[:8]}..., "
            f"url={payload.url[:80]}, viewport={payload.viewport_width}x{payload.viewport_height}"
        )

        if not self._screenshot_service.is_available():
            await self.send(ws, Message.from_typed(
                MessageType.SCREENSHOT_ERROR,
                ScreenshotErrorPayload(
                    error_type="not_installed",
                    message=(
                        "Playwright is not installed. Install with: "
                        "pip install playwright && playwright install chromium"
                    ),
                ),
            ))
            return

        result = await self._screenshot_service.capture(
            url=payload.url,
            viewport_width=payload.viewport_width,
            viewport_height=payload.viewport_height,
            wait_until=payload.wait_until,
        )

        if result.get("error"):
            await self.send(ws, Message.from_typed(
                MessageType.SCREENSHOT_ERROR,
                ScreenshotErrorPayload(
                    error_type=result["error_type"],
                    message=result["message"],
                ),
            ))
        else:
            await self.send(ws, Message.from_typed(
                MessageType.SCREENSHOT_RESULT,
                ScreenshotResultPayload(
                    image_data=result["image_data"],
                    actual_width=result["actual_width"],
                    actual_height=result["actual_height"],
                    capture_time_ms=result["capture_time_ms"],
                ),
            ))

    # ── Visual Diff handlers ──

    async def handle_visual_diff_start(self, client_id, ws, msg):
        """Handle visual_diff.start — capture the 'before' baseline.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with VisualDiffStartPayload.
        """
        payload = msg.typed_payload(VisualDiffStartPayload)
        logger.info(
            f"visual_diff.start: client={client_id[:8]}..., "
            f"url={payload.url[:80]}"
        )

        if not self._screenshot_service.is_available():
            await self.send(ws, Message.from_typed(
                MessageType.SCREENSHOT_ERROR,
                ScreenshotErrorPayload(
                    error_type="not_installed",
                    message=(
                        "Playwright is not installed. Install with: "
                        "pip install playwright && playwright install chromium"
                    ),
                ),
            ))
            return

        await self._visual_diff_service.capture_before(
            url=payload.url,
            viewport_width=payload.viewport_width,
            viewport_height=payload.viewport_height,
        )

    async def handle_visual_diff_compare(self, client_id, ws, msg):
        """Handle visual_diff.compare — capture 'after' and compute diff.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (empty payload).
        """
        logger.info(f"visual_diff.compare: client={client_id[:8]}...")

        result = await self._visual_diff_service.capture_and_compare()

        if result.get("error"):
            await self.send(ws, Message.from_typed(
                MessageType.SCREENSHOT_ERROR,
                ScreenshotErrorPayload(
                    error_type=result.get("error_type", "unknown"),
                    message=result["message"],
                ),
            ))
        else:
            await self.send(ws, Message.from_typed(
                MessageType.VISUAL_DIFF_RESULT,
                VisualDiffResultPayload(
                    before_image=result["before_image"],
                    after_image=result["after_image"],
                    diff_image=result["diff_image"],
                    changed_percentage=result["changed_percentage"],
                    has_changes=result["has_changes"],
                ),
            ))

    # ── Plugin query handlers ──

    async def handle_preview_detect(self, client_id, ws, msg):
        """Handle preview.detect — query plugins for project type detection.

        Queries installed plugins with the 'preview' capability for
        project type detection and smart suggestions. Returns empty
        result if no plugin provides a suggestion.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (PreviewDetectPayload, empty).
        """
        logger.info(f"preview.detect: client={client_id[:8]}...")

        # TODO: Query plugin registry for 'preview' capability
        # For now, return empty result (no plugin installed)
        from mobileflow_protocol.payloads.test_panel import PreviewDetectResultPayload

        await self.send(ws, Message.from_typed(
            MessageType.PREVIEW_DETECT_RESULT,
            PreviewDetectResultPayload(
                project_type=None,
                suggested_command=None,
                suggested_port=None,
            ),
        ))

    async def handle_runtime_resolve(self, client_id, ws, msg):
        """Handle runtime.resolve — resolve file extension to command.

        Queries installed plugins with the 'runtime' capability for
        file extension → command mapping. Returns empty result if no
        plugin provides a mapping.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with file path.
        """
        file_path = msg.payload.get("path", "")
        logger.info(f"runtime.resolve: client={client_id[:8]}..., path={file_path}")

        # TODO: Query plugin registry for 'runtime' capability
        # For now, return empty result (no plugin installed)
        result_msg = Message(
            type=MessageType.RUNTIME_RESOLVE_RESULT,
            payload={"path": file_path, "command": None},
        )
        await self.send(ws, result_msg)
