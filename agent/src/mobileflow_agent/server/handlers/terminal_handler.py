"""Terminal PTY handler with automatic CLI restart.

Module: server/handlers/
Responsibility:
    Handle terminal.start, terminal.input, terminal.resize, and terminal.stop
    messages.  Resolves the CLI command and execution environment from the
    ProviderRegistry, and implements smart restart on CLI exit (up to 3 retries
    with exponential backoff, reset after 30 s of stable running).

Lifecycle management:
    Each client has at most one active forward task. When a new terminal.start
    arrives, the old task is cancelled via asyncio.Task.cancel() and awaited
    before the new session begins. A monotonic generation counter provides a
    secondary guard: the forward loop checks its own generation against the
    current generation on every iteration, exiting immediately if they diverge.

    This two-layer approach (Task.cancel + generation check) eliminates the
    race condition that existed with the old boolean cancel flag, where the
    flag could be reset before the old task checked it.

Called by:
    WebSocketServer message router.
"""

from __future__ import annotations

import asyncio
import base64
import time

from loguru import logger

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.payloads.terminal import (
    TerminalOutputPayload,
    TerminalStartedPayload,
    TerminalStartPayload,
    TerminalInputPayload,
    TerminalResizePayload,
)
from mobileflow_protocol.types import MessageType

from ...utils.i18n import t
from .base import BaseHandler

# Restart policy constants
_MAX_RESTARTS = 3
_RESTART_DELAYS = [1, 2, 4]  # Increasing backoff intervals (seconds)
_STABLE_THRESHOLD = 30  # Seconds of uptime before the restart counter resets
_INSTANT_EXIT_THRESHOLD = 2  # Seconds — exits faster than this are "instant crashes"
_MAX_INSTANT_EXITS = 2  # Stop restarting after this many consecutive instant crashes


class TerminalHandler(BaseHandler):
    """Manages interactive terminal sessions over WebSocket.

    Supports starting a PTY session for a given CLI, forwarding I/O between
    the App and the PTY, and automatically restarting the CLI on unexpected
    exit with exponential backoff.

    Uses asyncio.Task lifecycle management instead of boolean flags:
    - _forward_tasks: stores the active forward task per client, so it can
      be cancelled deterministically on CLI switch or terminal stop.
    - _generations: monotonic counter per client. Each forward task captures
      its generation at creation time and exits if the generation has advanced
      (meaning a newer terminal.start has taken over).

    Attributes:
        _forward_tasks: Per-client asyncio.Task for the output forward loop.
        _generations: Per-client monotonic generation counter.
    """

    def __init__(self, server):
        super().__init__(server)
        self._forward_tasks: dict[str, asyncio.Task] = {}
        self._generations: dict[str, int] = {}

    async def _cancel_forward_task(self, client_id: str) -> None:
        """Cancel and await the existing forward task for a client.

        Uses asyncio.Task.cancel() which raises CancelledError inside the
        task (even during asyncio.sleep), then awaits the task to ensure
        it has fully stopped before returning. This guarantees no old task
        is running when a new session starts.

        Args:
            client_id: Identifier of the client whose task to cancel.
        """
        task = self._forward_tasks.pop(client_id, None)
        if task and not task.done():
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
            except Exception as e:
                # Log but don't propagate — old task errors are irrelevant
                logger.debug(f"旧终端 task 结束时出错（可忽略）: {e}")
            logger.debug(f"旧终端 forward task 已取消: client={client_id[:8]}...")

    async def handle_terminal_start(self, client_id, ws, msg):
        """Start a new terminal session for the given CLI.

        Lifecycle sequence:
        1. Advance the generation counter (invalidates any old task).
        2. Cancel the old forward task and await its completion.
        3. Stop the old PTY session.
        4. Resolve the CLI command.
        5. Create a new PTY session.
        6. Send terminal.started to the App.
        7. Spawn a new forward task bound to the current generation.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``cli``, ``cols``, and ``rows``.
        """
        if not self.config.work_dir:
            await self.send_error(ws, t("backend.addProjectFirst"))
            return

        p = msg.typed_payload(TerminalStartPayload)
        cli_name = p.cli or self.config.default_cli
        cols = p.cols
        rows = p.rows
        logger.info(f"terminal.start: client={client_id[:8]}..., cli={cli_name}, cols={cols}, rows={rows}")

        # Step 1: advance generation — any old task checking this will exit
        gen = self._generations.get(client_id, 0) + 1
        self._generations[client_id] = gen

        # Step 2: cancel old forward task (awaits completion)
        await self._cancel_forward_task(client_id)

        # Step 3: stop old PTY session
        await self.terminal_manager.stop_session(client_id)

        # Step 4: resolve CLI command
        cli_cmd, exec_env = self._resolve_cli(cli_name)
        if not cli_cmd:
            await self.send_error(ws, t("backend.cliNotFoundInstall", name=cli_name))
            return

        # Step 5-7: create session, notify App, spawn forward task
        try:
            session = await self.terminal_manager.create_session(
                session_id=client_id, cli_command=cli_cmd,
                work_dir=self.config.work_dir, cols=cols, rows=rows,
                execution_env=exec_env,
            )
            await self.send(ws, Message.from_typed(
                MessageType.TERMINAL_STARTED,
                TerminalStartedPayload(terminal_id=client_id, cli=cli_name),
            ))
            task = asyncio.create_task(self._forward_with_restart(
                client_id, ws, session, cli_name, cli_cmd, exec_env,
                cols, rows, gen,
            ))
            self._forward_tasks[client_id] = task
        except Exception as e:
            logger.error(f"终端启动失败: {e}")
            await self.send_error(ws, t("backend.terminalStartFailed", error=str(e)))

    def _resolve_cli(self, cli_name: str) -> tuple[str, str]:
        """Resolve the terminal command and execution environment for a CLI.

        Looks up the CLI in the ACP registry first, falling back to custom
        agent providers.

        Args:
            cli_name: Name of the CLI adapter to resolve.

        Returns:
            A tuple of ``(terminal_command, execution_env)``.  Returns
            ``("", "native")`` if the CLI cannot be found.
        """
        exec_env = self.cli_manager.registry.get_execution_env(cli_name)

        from ...providers.registry import ACP_REGISTRY
        config = ACP_REGISTRY.get(cli_name)

        if config:
            # Prefer terminal_cmd (interactive TUI); fall back to ACP command
            terminal_cmd = config.get("terminal_cmd", config["command"])
            from ...utils.command import which
            resolved = which(terminal_cmd) or terminal_cmd
            return (resolved, exec_env or "native")

        # Custom agent: get command from the detected provider
        provider = self.cli_manager.registry.get_provider(cli_name)
        if provider:
            return (provider._command, exec_env or "native")

        return ("", "native")

    def _is_current_generation(self, client_id: str, gen: int) -> bool:
        """Check if the given generation is still the active one.

        Used by _forward_with_restart to detect that a newer terminal.start
        has taken over. This is the secondary guard behind Task.cancel().

        Args:
            client_id: Client identifier.
            gen: The generation number this task was spawned with.

        Returns:
            True if gen matches the current generation for this client.
        """
        return self._generations.get(client_id, 0) == gen

    async def _forward_with_restart(
        self, client_id, ws, session, cli_name, cli_cmd, exec_env,
        cols, rows, generation: int,
    ):
        """Forward terminal output to the App, restarting the CLI on exit.

        Implements exponential backoff with a maximum of ``_MAX_RESTARTS``
        consecutive restarts.  The counter resets if the CLI runs stably for
        longer than ``_STABLE_THRESHOLD`` seconds.

        Exits immediately if:
        - The task is cancelled (asyncio.CancelledError propagates naturally).
        - The generation has advanced (a newer terminal.start took over).
        - The client scope is disposed or cancelled (Agent shutting down or
          client disconnected during grace period).

        Args:
            client_id: Identifier of the owning client.
            ws: The client's WebSocket connection.
            session: The active terminal session.
            cli_name: Name of the CLI adapter.
            cli_cmd: Resolved CLI command path.
            exec_env: Execution environment (native / wsl).
            cols: Terminal column count.
            rows: Terminal row count.
            generation: The generation counter at task creation time.
        """
        restart_count = 0
        instant_exit_count = 0

        while self._is_current_generation(client_id, generation):
            # Check if client scope is still alive (not disposed or cancelled).
            # This catches both normal disconnect and Agent shutdown scenarios.
            scope = self.server._scopes.get(client_id)
            if not scope or not scope.is_alive or scope.cancelled.is_set():
                logger.debug(f"终端: scope 不可用，退出重启循环: client={client_id[:8]}...")
                return

            start_time = time.monotonic()

            # Forward output — CancelledError propagates naturally from
            # the async for loop when Task.cancel() is called
            try:
                async for data in session.read_output():
                    if not self._is_current_generation(client_id, generation):
                        logger.debug(f"终端 generation 已过期，退出转发: client={client_id[:8]}...")
                        return
                    encoded = base64.b64encode(data).decode("ascii")
                    await self.send(ws, Message.from_typed(
                        MessageType.TERMINAL_OUTPUT,
                        TerminalOutputPayload(data=encoded),
                    ))
            except asyncio.CancelledError:
                logger.debug(f"终端 forward task 被取消: client={client_id[:8]}...")
                raise
            except Exception as e:
                logger.warning(f"终端输出转发出错: {e}")

            # Generation check after output loop ends (CLI exited)
            if not self._is_current_generation(client_id, generation):
                return

            # Re-check scope before attempting restart — Agent may be
            # shutting down while we were in the output loop.
            scope = self.server._scopes.get(client_id)
            if not scope or not scope.is_alive or scope.cancelled.is_set():
                logger.debug(f"终端: scope 已失效，跳过重启: client={client_id[:8]}...")
                return

            # CLI exited — decide whether to restart based on how long it ran.
            #
            # Three categories:
            #   1. Stable run (>30s) → reset counters, always restart
            #   2. Normal crash (2-30s) → increment counter, restart with backoff
            #   3. Instant exit (<2s) → likely misconfigured, stop after 2 attempts
            elapsed = time.monotonic() - start_time
            is_instant_exit = elapsed < _INSTANT_EXIT_THRESHOLD
            logger.debug(
                f"终端 CLI 退出: client={client_id[:8]}..., "
                f"cli={cli_name}, elapsed={elapsed:.1f}s, "
                f"restart_count={restart_count}, gen={generation}, "
                f"current_gen={self._generations.get(client_id, -1)}"
            )

            if elapsed > _STABLE_THRESHOLD:
                # Ran long enough to be considered stable — reset counter
                restart_count = 0
                instant_exit_count = 0

            if is_instant_exit:
                instant_exit_count += 1
                if instant_exit_count >= _MAX_INSTANT_EXITS:
                    # CLI can't even start — no point retrying
                    error_msg = t("backend.cliCannotStart") + "\r\n"
                    encoded = base64.b64encode(error_msg.encode("utf-8")).decode("ascii")
                    try:
                        await self.send(ws, Message.from_typed(
                            MessageType.TERMINAL_OUTPUT,
                            TerminalOutputPayload(data=encoded),
                        ))
                    except Exception:
                        pass
                    logger.error(f"CLI 连续秒退 {instant_exit_count} 次，停止重启（可能是命令不存在或环境错误）")
                    break
            else:
                # Normal exit (ran for a while) — reset instant counter
                instant_exit_count = 0

            if restart_count >= _MAX_RESTARTS:
                error_msg = t("backend.cliStartFailed") + "\r\n"
                encoded = base64.b64encode(error_msg.encode("utf-8")).decode("ascii")
                try:
                    await self.send(ws, Message.from_typed(
                        MessageType.TERMINAL_OUTPUT,
                        TerminalOutputPayload(data=encoded),
                    ))
                except Exception:
                    pass
                logger.error(f"CLI 重启次数超限 ({_MAX_RESTARTS})，停止重启")
                break

            delay = _RESTART_DELAYS[min(restart_count, len(_RESTART_DELAYS) - 1)]
            logger.info(f"CLI 已退出，{delay}s 后重启 (第 {restart_count + 1}/{_MAX_RESTARTS} 次)...")

            # asyncio.sleep is cancellable — Task.cancel() will interrupt it
            await asyncio.sleep(delay)

            if not self._is_current_generation(client_id, generation):
                return

            # Final scope check before creating a new session
            scope = self.server._scopes.get(client_id)
            if not scope or not scope.is_alive or scope.cancelled.is_set():
                logger.debug(f"终端: scope 已失效，跳过重启: client={client_id[:8]}...")
                return

            try:
                session = await self.terminal_manager.create_session(
                    session_id=client_id, cli_command=cli_cmd,
                    work_dir=self.config.work_dir, cols=cols, rows=rows,
                    execution_env=exec_env,
                )
                restart_count += 1
                logger.info("CLI 已重启")
            except asyncio.CancelledError:
                raise
            except Exception as e:
                error_msg = t("backend.cliRestartFailed", error=str(e)) + "\r\n"
                encoded = base64.b64encode(error_msg.encode("utf-8")).decode("ascii")
                try:
                    await self.send(ws, Message.from_typed(
                        MessageType.TERMINAL_OUTPUT,
                        TerminalOutputPayload(data=encoded),
                    ))
                except Exception:
                    pass
                logger.error(f"CLI 重启失败: {e}")
                break

    async def handle_terminal_input(self, client_id, ws, msg):
        """Forward user input to the terminal session.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``data`` (raw input string).
        """
        p = msg.typed_payload(TerminalInputPayload)
        data = p.data
        session = self.terminal_manager.get_session(client_id)
        if session and session.is_running:
            await session.write_input(data)

    async def handle_terminal_resize(self, client_id, ws, msg):
        """Resize the terminal session.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``cols`` and ``rows``.
        """
        p = msg.typed_payload(TerminalResizePayload)
        cols = p.cols
        rows = p.rows
        logger.debug(f"terminal.resize: client={client_id[:8]}..., cols={cols}, rows={rows}")
        session = self.terminal_manager.get_session(client_id)
        if session:
            try:
                await session.resize(cols, rows)
            except Exception as e:
                logger.warning(f"terminal.resize 失败 (可忽略): {e}")

    async def handle_terminal_stop(self, client_id, ws, msg):
        """Stop the terminal session and cancel the forward task.

        Lifecycle sequence:
        1. Advance generation (invalidates the forward task's loop condition).
        2. Cancel and await the forward task.
        3. Stop the PTY session.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (no payload required).
        """
        logger.info(f"terminal.stop: client={client_id[:8]}...")
        # Advance generation to invalidate any running loop
        self._generations[client_id] = self._generations.get(client_id, 0) + 1
        await self._cancel_forward_task(client_id)
        await self.terminal_manager.stop_session(client_id)
