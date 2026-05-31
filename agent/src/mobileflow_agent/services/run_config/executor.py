"""Run Configuration execution engine.

Orchestrates the full lifecycle of running configurations:
validation → before-run tasks → process start → health check → running → stop.

Uses existing services:
    - CommandExecutor: subprocess lifecycle (spawn, stream, kill)
    - PortProxy: reverse proxy for preview-type configurations
    - utils/process.py: process tree management (kill_process_tree)

Each configuration gets its own CommandExecutor instance to allow
independent lifecycle management. The executor enforces singleton
policy (stop existing before starting new when allow_parallel=false).

State machine:
    idle → before_run → starting → running → stopping → stopped
    Any state can transition to stopped on failure.
"""

from __future__ import annotations

import asyncio
import os
import ssl
from collections import deque
from typing import Awaitable, Callable
from urllib.parse import urlparse

import aiohttp
from loguru import logger

from ...core.config import AgentConfig
from ..command_executor import CommandExecutor
from ..port_proxy import PortProxy
from .models import RunConfigState, RunConfigType, RunConfiguration

# Type alias for the state-changed callback.
# Signature: async (config_id, state, **kwargs) -> None
# kwargs may include: exit_code, error_message, preview_url
OnStateChanged = Callable[..., Awaitable[None]]

# Type alias for the output callback.
# Signature: async (stream_name, text) -> None
OnOutput = Callable[[str, str], Awaitable[None]]

# Type alias for the global output callback (includes config_id).
# Signature: async (config_id, stream_name, text) -> None
OnGlobalOutput = Callable[[str, str, str], Awaitable[None]]

# Health check polling interval in seconds
_HEALTH_CHECK_INTERVAL = 2.0

# Maximum output lines buffered per config for Dashboard HTTP polling
_MAX_OUTPUT_BUFFER = 1000


class RunConfigurationExecutor:
    """Execution engine for run configurations.

    Manages the full lifecycle of running configurations. Uses
    CommandExecutor for subprocess management and PortProxy for
    preview proxy activation. Enforces singleton policy.

    Each configuration gets its own CommandExecutor instance to
    allow independent lifecycle management.

    State changes are broadcast via a global listener (observer pattern)
    so that ALL clients (App via WebSocket, Dashboard via HTTP) receive
    updates regardless of who triggered the action.

    Attributes:
        _config: Agent configuration (provides work_dir, port, etc.).
        _port_proxy: Shared PortProxy instance for preview forwarding.
        _executors: Per-config CommandExecutor instances.
        _states: Per-config current lifecycle state.
        _configs: Configs currently being executed (for restart).
        _tasks: Per-config asyncio tasks for background execution.
        _global_state_listener: Optional global callback for ALL state changes.
        _global_output_listener: Optional global callback for ALL output (with config_id).
    """

    def __init__(self, config: AgentConfig, port_proxy: PortProxy) -> None:
        """Initialize the executor with agent config and port proxy.

        Args:
            config: Agent configuration providing work_dir and other settings.
            port_proxy: Shared PortProxy instance for preview-type configs.
        """
        self._config = config
        self._port_proxy = port_proxy
        self._executors: dict[str, CommandExecutor] = {}
        self._states: dict[str, RunConfigState] = {}
        self._configs: dict[str, RunConfiguration] = {}
        self._tasks: dict[str, asyncio.Task] = {}
        self._global_state_listener: OnStateChanged | None = None
        self._global_output_listener: OnGlobalOutput | None = None
        # Per-config output ring buffer for Dashboard HTTP polling
        self._output_buffers: dict[str, deque] = {}
        self._output_counters: dict[str, int] = {}
        logger.debug("RunConfigurationExecutor 初始化完成")

    def set_global_listeners(
        self,
        on_state_changed: OnStateChanged | None = None,
        on_output: OnGlobalOutput | None = None,
    ) -> None:
        """Register global listeners for ALL state changes and output.

        These listeners are called for every state transition and output
        line, regardless of which client triggered the execution. This
        enables broadcasting to all WebSocket clients.

        Args:
            on_state_changed: Async callback for any state transition.
            on_output: Async callback for any process output (config_id, stream, text).
        """
        self._global_state_listener = on_state_changed
        self._global_output_listener = on_output

    async def start(
        self,
        config: RunConfiguration,
        on_output: OnOutput | None = None,
        on_state_changed: OnStateChanged | None = None,
    ) -> None:
        """Start execution of a run configuration.

        Full lifecycle: validate → enforce singleton → before-run tasks →
        start main command → health check (preview) → running.

        State transitions are reported via:
        1. The per-call on_state_changed callback (if provided)
        2. The global state listener (always, if registered)

        Args:
            config: The run configuration to execute.
            on_output: Optional per-call callback for process output.
            on_state_changed: Optional per-call callback for state transitions.
        """
        config_id = config.id
        logger.info(
            f"启动运行配置: name={config.name!r}, type={config.type.value}, "
            f"id={config_id[:16]}..."
        )

        # Validate configuration before doing anything
        error = self._validate_config(config)
        if error:
            logger.warning(f"配置验证失败: id={config_id[:16]}..., error={error}")
            self._states[config_id] = RunConfigState.STOPPED
            await self._notify_state(config_id, RunConfigState.STOPPED, on_state_changed, error_message=error)
            return

        # Enforce singleton policy: stop existing if allow_parallel=false
        if not config.allow_parallel and config_id in self._states:
            current_state = self._states[config_id]
            if current_state not in (RunConfigState.IDLE, RunConfigState.STOPPED):
                logger.info(
                    f"单例策略: 停止已有实例 id={config_id[:16]}..., "
                    f"state={current_state.value}"
                )
                await self.stop(config_id)

        # Store config for restart support
        self._configs[config_id] = config

        # Wrap callbacks to include global listeners
        async def _combined_output(stream: str, text: str) -> None:
            # Write to per-config ring buffer for Dashboard HTTP polling
            buf = self._output_buffers.setdefault(config_id, deque(maxlen=_MAX_OUTPUT_BUFFER))
            idx = self._output_counters.get(config_id, 0)
            buf.append({"index": idx, "stream": stream, "text": text})
            self._output_counters[config_id] = idx + 1

            if on_output:
                await on_output(stream, text)
            if self._global_output_listener:
                try:
                    await self._global_output_listener(config_id, stream, text)
                except Exception:
                    pass

        async def _combined_state(cid: str, state, **kwargs) -> None:
            if on_state_changed:
                await on_state_changed(cid, state, **kwargs)
            if self._global_state_listener:
                try:
                    await self._global_state_listener(cid, state, **kwargs)
                except Exception:
                    pass

        # Create a background task for the full execution lifecycle
        task = asyncio.create_task(
            self._execute(config, _combined_output, _combined_state)
        )
        self._tasks[config_id] = task

    async def stop(self, config_id: str) -> None:
        """Stop a running configuration by killing its process tree.

        Transitions to stopping state, kills the process, then transitions
        to stopped. Deactivates preview proxy if applicable.
        Notifies global state listener.

        Safe to call on already-stopped or non-existent configurations.

        Args:
            config_id: ID of the configuration to stop.
        """
        logger.info(f"停止运行配置: id={config_id[:16]}...")

        current_state = self._states.get(config_id)
        if current_state in (None, RunConfigState.IDLE, RunConfigState.STOPPED):
            logger.debug(f"配置未在运行中，跳过停止: id={config_id[:16]}...")
            return

        # Cancel the background execution task if still running
        task = self._tasks.get(config_id)
        if task and not task.done():
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

        # Kill the executor's subprocess
        executor = self._executors.get(config_id)
        if executor and executor.is_running:
            await executor.stop()

        # Deactivate preview proxy if this was a preview config
        config = self._configs.get(config_id)
        if config and config.type == RunConfigType.PREVIEW:
            await self._deactivate_preview()

        self._states[config_id] = RunConfigState.STOPPED
        logger.info(f"运行配置已停止: id={config_id[:16]}...")

        # Notify global listener
        await self._notify_state(config_id, RunConfigState.STOPPED, None)

    async def restart(
        self,
        config_id: str,
        on_output: OnOutput | None = None,
        on_state_changed: OnStateChanged | None = None,
    ) -> None:
        """Restart a configuration: stop then start.

        Stops the existing instance (if running), waits for termination,
        then starts a new execution from the beginning (including
        before-run tasks).

        Args:
            config_id: ID of the configuration to restart.
            on_output: Optional async callback for process output.
            on_state_changed: Optional async callback for state transitions.
        """
        logger.info(f"重启运行配置: id={config_id[:16]}...")

        config = self._configs.get(config_id)
        if config is None:
            logger.warning(f"重启失败，未找到配置: id={config_id}")
            await self._notify_state(
                config_id, RunConfigState.STOPPED, on_state_changed,
                error_message=f"Configuration not found: {config_id}",
            )
            return

        await self.stop(config_id)
        await self.start(config, on_output=on_output, on_state_changed=on_state_changed)

    def get_state(self, config_id: str) -> RunConfigState:
        """Return the current lifecycle state of a configuration.

        Args:
            config_id: ID of the configuration to query.

        Returns:
            Current RunConfigState, defaults to IDLE if not tracked.
        """
        return self._states.get(config_id, RunConfigState.IDLE)

    def get_all_states(self) -> dict[str, RunConfigState]:
        """Return states for all non-idle configurations.

        Returns:
            Dict mapping config_id to RunConfigState for all configs
            that are not in IDLE state.
        """
        return {
            cid: state
            for cid, state in self._states.items()
            if state != RunConfigState.IDLE
        }

    def get_output(self, config_id: str, since: int = 0) -> list[dict]:
        """Return buffered output lines with index >= since.

        Used by the Dashboard HTTP API for polling-based output streaming.
        Each line is a dict with keys: index, stream, text.

        Args:
            config_id: ID of the configuration to get output for.
            since: Only return lines with index >= this value.

        Returns:
            List of output line dicts, ordered by index.
        """
        buf = self._output_buffers.get(config_id, deque())
        return [line for line in buf if line["index"] >= since]

    def clear_output(self, config_id: str) -> None:
        """Clear the output buffer for a configuration.

        Called when the user clicks Clear in the Dashboard output panel.

        Args:
            config_id: ID of the configuration to clear output for.
        """
        self._output_buffers.pop(config_id, None)
        self._output_counters.pop(config_id, None)

    async def cleanup(self) -> None:
        """Stop all running configurations.

        Called on Agent shutdown to ensure all child processes are
        terminated cleanly. Stops each running config and cancels
        background tasks.
        """
        logger.info(f"清理所有运行配置: {len(self._states)} 个跟踪中")

        running_ids = [
            cid for cid, state in self._states.items()
            if state not in (RunConfigState.IDLE, RunConfigState.STOPPED)
        ]

        for config_id in running_ids:
            try:
                await self.stop(config_id)
            except Exception as e:
                logger.warning(f"清理配置时出错: id={config_id[:16]}..., error={e}")

        # Cancel any remaining background tasks
        for task in self._tasks.values():
            if not task.done():
                task.cancel()

        self._executors.clear()
        self._states.clear()
        self._configs.clear()
        self._tasks.clear()
        logger.info("所有运行配置已清理")

    # ──────────────────────────────────────────────────────────────────
    # Private implementation
    # ──────────────────────────────────────────────────────────────────

    async def _notify_state(
        self,
        config_id: str,
        state: RunConfigState,
        per_call_callback: OnStateChanged | None,
        **kwargs,
    ) -> None:
        """Notify both per-call and global listeners of a state change.

        Args:
            config_id: Configuration ID.
            state: New state.
            per_call_callback: Optional per-call callback from start().
            **kwargs: Additional context (exit_code, error_message, preview_url).
        """
        if per_call_callback:
            try:
                await per_call_callback(config_id, state, **kwargs)
            except Exception:
                pass
        if self._global_state_listener:
            try:
                await self._global_state_listener(config_id, state, **kwargs)
            except Exception:
                pass

    def _validate_config(self, config: RunConfiguration) -> str | None:
        """Validate a configuration before execution.

        Checks:
        1. Command is not empty
        2. Working directory exists (if specified)
        3. Preview URL is valid (if preview type)

        Args:
            config: The configuration to validate.

        Returns:
            Error message string if validation fails, None if valid.
        """
        # Command is required for execution
        if not config.command or not config.command.strip():
            return "Command is required"

        # Working directory must exist if specified
        if config.working_directory:
            from pathlib import Path
            work_dir = config.working_directory
            # Resolve relative paths against project root
            if not Path(work_dir).is_absolute():
                base = self._config.work_dir or os.getcwd()
                work_dir = str(Path(base) / work_dir)
            if not Path(work_dir).is_dir():
                return f"Working directory does not exist: {config.working_directory}"

        # Preview URL validation
        if config.type == RunConfigType.PREVIEW and config.preview:
            url = config.preview.url
            parsed = urlparse(url)
            if not parsed.scheme:
                return f"Invalid preview URL: must include scheme and host ({url})"
            if not parsed.hostname:
                return f"Invalid preview URL: must include scheme and host ({url})"

        return None

    async def _execute(
        self,
        config: RunConfiguration,
        on_output: OnOutput,
        on_state_changed: OnStateChanged,
    ) -> None:
        """Full execution lifecycle for a configuration.

        Runs as a background asyncio task. Handles the complete flow:
        before-run tasks → main command → health check → running.

        Args:
            config: The configuration to execute.
            on_output: Async callback for process output.
            on_state_changed: Async callback for state transitions.
        """
        config_id = config.id

        try:
            # Phase 1: Before-run tasks
            enabled_tasks = [t for t in config.before_run_tasks if t.enabled]
            if enabled_tasks:
                self._states[config_id] = RunConfigState.BEFORE_RUN
                await on_state_changed(config_id, RunConfigState.BEFORE_RUN)
                logger.debug(
                    f"执行前置任务: id={config_id[:16]}..., "
                    f"count={len(enabled_tasks)}"
                )

                success = await self._run_before_tasks(
                    config, enabled_tasks, on_output, on_state_changed
                )
                if not success:
                    return  # Already transitioned to STOPPED

            # Phase 2: Start main command
            self._states[config_id] = RunConfigState.STARTING
            await on_state_changed(config_id, RunConfigState.STARTING)
            logger.debug(f"启动主命令: id={config_id[:16]}..., cmd={config.command!r}")

            # Create a dedicated CommandExecutor for this config
            executor = CommandExecutor(self._config)
            self._executors[config_id] = executor

            # Resolve working directory
            cwd = config.working_directory

            # Build environment variables
            env: dict[str, str] | None = None
            if config.environment_variables:
                env = dict(config.environment_variables)

            # Track whether the process has exited
            process_exited = asyncio.Event()
            exit_info: dict = {}

            async def _on_output(stream: str, text: str) -> None:
                """Forward main command output."""
                await on_output(stream, text)

            async def _on_done(exit_code: int, status: str) -> None:
                """Handle main command completion."""
                exit_info["exit_code"] = exit_code
                exit_info["status"] = status
                process_exited.set()

            # Start the main command (runs in background via CommandExecutor)
            run_task = asyncio.create_task(
                executor.run(
                    command=config.command,
                    cwd=cwd,
                    env=env,
                    on_output=_on_output,
                    on_done=_on_done,
                )
            )

            # Phase 3: Health check for preview type, or immediate transition
            if config.type == RunConfigType.PREVIEW and config.preview:
                # Poll target URL until it responds (no fixed timeout —
                # keep polling while process is alive)
                target_url = config.preview.url
                logger.debug(
                    f"开始健康检查: id={config_id[:16]}..., url={target_url}"
                )

                healthy = await self._wait_for_health(
                    target_url, config.preview.host_header, process_exited
                )

                if healthy:
                    # Activate preview proxy
                    await self._activate_preview(config)
                    self._states[config_id] = RunConfigState.RUNNING
                    # Build the proxy URL that the phone can reach
                    # (agent LAN IP + port + /preview/ path)
                    preview_url = self._build_preview_url()
                    logger.info(
                        f"预览配置已就绪: id={config_id[:16]}..., "
                        f"target={target_url}, proxy_url={preview_url}"
                    )
                    await on_state_changed(
                        config_id, RunConfigState.RUNNING, preview_url=preview_url
                    )
                elif process_exited.is_set():
                    # Process exited before health check passed
                    ec = exit_info.get("exit_code", -1)
                    self._states[config_id] = RunConfigState.STOPPED
                    await on_state_changed(
                        config_id, RunConfigState.STOPPED,
                        exit_code=ec,
                        error_message=f"Process exited before server became ready (exit code: {ec})",
                    )
                    logger.warning(
                        f"进程在健康检查前退出: id={config_id[:16]}..., exit_code={ec}"
                    )
                    return
            else:
                # Non-preview: transition to running immediately
                self._states[config_id] = RunConfigState.RUNNING
                await on_state_changed(config_id, RunConfigState.RUNNING)
                logger.info(f"配置已进入运行状态: id={config_id[:16]}...")

            # Phase 4: Wait for process to exit
            await run_task

            # Process has exited — transition to stopped
            ec = exit_info.get("exit_code", -1)

            # Deactivate preview proxy on stop
            if config.type == RunConfigType.PREVIEW:
                await self._deactivate_preview()

            self._states[config_id] = RunConfigState.STOPPED
            await on_state_changed(
                config_id, RunConfigState.STOPPED, exit_code=ec
            )
            logger.info(
                f"配置执行完成: id={config_id[:16]}..., exit_code={ec}"
            )

        except asyncio.CancelledError:
            # Task was cancelled (e.g. by stop() or cleanup())
            logger.debug(f"执行任务被取消: id={config_id[:16]}...")
            self._states[config_id] = RunConfigState.STOPPED
            raise

        except Exception as e:
            logger.error(f"配置执行异常: id={config_id[:16]}..., error={e}")
            self._states[config_id] = RunConfigState.STOPPED
            try:
                await on_state_changed(
                    config_id, RunConfigState.STOPPED,
                    error_message=f"Execution error: {e}",
                )
            except Exception:
                pass

    async def _run_before_tasks(
        self,
        config: RunConfiguration,
        tasks: list,
        on_output: OnOutput,
        on_state_changed: OnStateChanged,
    ) -> bool:
        """Execute before-run tasks sequentially.

        Runs each enabled task in order. Streams output with [Before N/M]
        prefix. Cancels on first non-zero exit code.

        Args:
            config: Parent configuration (for working directory fallback).
            tasks: List of enabled BeforeRunTask objects.
            on_output: Async callback for task output.
            on_state_changed: Async callback for state transitions.

        Returns:
            True if all tasks succeeded, False if any failed.
        """
        config_id = config.id
        total = len(tasks)

        for i, task in enumerate(tasks, start=1):
            prefix = f"[Before {i}/{total}]"
            logger.debug(
                f"执行前置任务 {i}/{total}: id={config_id[:16]}..., "
                f"cmd={task.command!r}"
            )

            # Use a temporary CommandExecutor for each before-run task
            task_executor = CommandExecutor(self._config)

            # Resolve working directory: task-specific > config-level > project root
            cwd = task.working_directory or config.working_directory

            # Track exit code
            task_exit_code: int | None = None
            done_event = asyncio.Event()

            async def _on_task_output(stream: str, text: str) -> None:
                """Forward before-run task output with prefix."""
                await on_output(stream, f"{prefix} {text}")

            async def _on_task_done(exit_code: int, status: str) -> None:
                """Record before-run task exit code."""
                nonlocal task_exit_code
                task_exit_code = exit_code
                done_event.set()

            await task_executor.run(
                command=task.command,
                cwd=cwd,
                on_output=_on_task_output,
                on_done=_on_task_done,
            )

            # Check exit code
            if task_exit_code is None:
                task_exit_code = 0

            if task_exit_code != 0:
                error_msg = (
                    f"Before-run task {i}/{total} failed with exit code {task_exit_code}: "
                    f"{task.command!r}"
                )
                logger.warning(
                    f"前置任务失败: id={config_id[:16]}..., "
                    f"task={i}/{total}, exit_code={task_exit_code}"
                )
                self._states[config_id] = RunConfigState.STOPPED
                await on_state_changed(
                    config_id, RunConfigState.STOPPED,
                    exit_code=task_exit_code,
                    error_message=error_msg,
                )
                return False

        logger.debug(f"所有前置任务完成: id={config_id[:16]}...")
        return True

    async def _wait_for_health(
        self,
        target_url: str,
        host_header: str | None,
        process_exited: asyncio.Event,
    ) -> bool:
        """Poll target URL until it responds or process exits.

        No fixed timeout — keeps polling while the process is alive.
        This allows slow-starting servers (e.g. Next.js compilation)
        to take as long as they need.

        Args:
            target_url: The URL to probe (e.g. "http://localhost:3000").
            host_header: Optional Host header override for the probe.
            process_exited: Event that is set when the process exits.

        Returns:
            True if the URL responded successfully, False if the process
            exited before the URL became responsive.
        """
        parsed = urlparse(target_url)
        scheme = parsed.scheme or "http"
        host = parsed.hostname or "localhost"
        port = parsed.port or (443 if scheme == "https" else 80)

        # Determine probe strategy:
        # - If target URL uses localhost/127.0.0.1 → probe localhost directly
        # - If target URL uses a custom hostname (e.g. de4.nmm.com) → probe
        #   localhost with Host header (dev server usually binds 0.0.0.0)
        # - If host_header is explicitly set → always use it as Host header
        is_localhost = host in ("localhost", "127.0.0.1", "0.0.0.0")
        probe_url = f"{scheme}://localhost:{port}/"
        probe_host = host_header or (f"{host}:{port}" if not is_localhost else f"localhost:{port}")

        # SSL context for HTTPS targets (skip cert verification for dev servers)
        ssl_ctx: ssl.SSLContext | bool | None = None
        if scheme == "https":
            ssl_ctx = ssl.create_default_context()
            ssl_ctx.check_hostname = False
            ssl_ctx.verify_mode = ssl.CERT_NONE

        # Read health check settings from config (fall back to module defaults)
        probe_timeout = self._config.preview.health_check_probe_timeout
        poll_interval = self._config.preview.health_check_interval
        warning_threshold = self._config.preview.health_check_warning_threshold

        timeout = aiohttp.ClientTimeout(total=probe_timeout)
        logger.info(
            f"健康检查开始: probe_url={probe_url}, host={probe_host}, "
            f"scheme={scheme}, ssl={'yes' if ssl_ctx else 'no'}, "
            f"probe_timeout={probe_timeout}s, interval={poll_interval}s"
        )

        async with aiohttp.ClientSession(timeout=timeout) as session:
            poll_count = 0
            while not process_exited.is_set():
                poll_count += 1
                try:
                    async with session.get(
                        probe_url,
                        headers={"Host": probe_host},
                        ssl=ssl_ctx,
                    ) as resp:
                        # Any response (even 4xx/5xx) means server is up
                        logger.info(
                            f"健康检查成功: url={probe_url}, status={resp.status}, "
                            f"polls={poll_count}"
                        )
                        return True
                except (aiohttp.ClientError, asyncio.TimeoutError, OSError) as e:
                    # Server not ready yet, wait and retry
                    if poll_count <= 3 or poll_count % 10 == 0:
                        logger.debug(
                            f"健康检查失败 (第{poll_count}次): {type(e).__name__}: {e}"
                        )
                    # Warn after N polls that server is still not ready
                    if poll_count == warning_threshold:
                        logger.warning(
                            f"健康检查已等待{warning_threshold}次仍未就绪: url={probe_url}, "
                            f"host={probe_host}, 最后错误={type(e).__name__}: {e}"
                        )
                    pass

                # Wait before next poll, but also check if process exited
                try:
                    await asyncio.wait_for(
                        process_exited.wait(),
                        timeout=poll_interval,
                    )
                    # Process exited while waiting
                    return False
                except asyncio.TimeoutError:
                    # Timeout expired, process still alive — poll again
                    continue

        # Process exited before health check passed
        return False

    async def _activate_preview(self, config: RunConfiguration) -> None:
        """Activate the preview proxy for a preview-type configuration.

        Calls PortProxy.activate_url with the configuration's preview URL.
        Also sets the Agent's LAN address for URL rewriting in responses.

        Args:
            config: The preview configuration that reached running state.
        """
        if not config.preview:
            return

        url = config.preview.url
        logger.debug(f"激活预览代理: url={url}")

        # Set the Agent's LAN address for URL rewriting
        import socket
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            agent_host = s.getsockname()[0]
            s.close()
        except Exception as e:
            agent_host = "127.0.0.1"
            logger.warning(
                f"LAN IP 检测失败，回退到 127.0.0.1（手机可能无法访问）: error={e}"
            )
        self._port_proxy.set_agent_address(agent_host, self._config.port)

        try:
            await self._port_proxy.activate_url(url)
            logger.info(f"预览代理已激活: url={url}, agent={agent_host}:{self._config.port}")
        except Exception as e:
            logger.error(f"预览代理激活失败: url={url}, error={e}")
            raise

    def _build_preview_url(self) -> str:
        """Build the externally-accessible preview URL for the phone.

        Returns the Agent's root URL. When PortProxy is active, the Agent
        routes all non-API requests to the dev server transparently —
        no /preview/ prefix needed. This lets the frontend app run as if
        it were accessed directly (Vue Router paths work, API relative
        paths work, etc.).

        Returns:
            URL like "http://192.168.1.100:9600/"
        """
        import socket
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            host = s.getsockname()[0]
            s.close()
        except Exception:
            host = "127.0.0.1"

        url = f"http://{host}:{self._config.port}/"
        logger.debug(f"构建预览 URL: host={host}, port={self._config.port}, url={url}")
        return url

    async def _deactivate_preview(self) -> None:
        """Deactivate the preview proxy.

        Called when a preview configuration stops. No-op if proxy
        is not currently active.
        """
        if self._port_proxy.is_active:
            logger.debug("停用预览代理")
            await self._port_proxy.deactivate()
