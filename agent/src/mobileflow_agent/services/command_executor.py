"""Command Executor service for the Test Panel.

Runs arbitrary commands in a subprocess, streaming stdout/stderr
back to the caller via async callbacks. Enforces single-instance
execution per session — only one command can run at a time.

Architecture:
    - Uses asyncio.create_subprocess_shell for cross-platform execution
    - Streams output line-by-line via on_output callback
    - Supports graceful stop (SIGTERM → 5s → SIGKILL)
    - Does NOT validate or interpret the command string
"""

from __future__ import annotations

import asyncio
import os
import sys
from typing import Awaitable, Callable

from loguru import logger

from ..core.config import AgentConfig


class CommandAlreadyRunningError(Exception):
    """Raised when a second command is requested while one is active."""

    pass


class CommandExecutor:
    """Generic subprocess runner with streaming output.

    Runs one command at a time per session. Streams stdout/stderr
    separately. Supports graceful stop (SIGTERM → SIGKILL).

    Attributes:
        _config: Agent configuration for default working directory.
        _process: The currently running subprocess, or None.
        _running: Whether a command is currently executing.
    """

    def __init__(self, config: AgentConfig) -> None:
        self._config = config
        self._process: asyncio.subprocess.Process | None = None
        self._running = False

    @property
    def is_running(self) -> bool:
        """Whether a command is currently executing."""
        return self._running

    @property
    def pid(self) -> int | None:
        """PID of the currently running subprocess, or None."""
        return self._process.pid if self._process else None

    async def run(
        self,
        command: str,
        cwd: str | None = None,
        env: dict[str, str] | None = None,
        on_output: Callable[[str, str], Awaitable[None]] | None = None,
        on_done: Callable[[int, str], Awaitable[None]] | None = None,
    ) -> None:
        """Start a command in a subprocess with streaming output.

        Spawns the command via shell, streams stdout/stderr line-by-line
        through the on_output callback, and reports the exit code via
        on_done when the process terminates.

        Single-instance enforcement: raises CommandAlreadyRunningError
        if called while another command is still active.

        Args:
            command: Shell command string to execute. Passed directly to
                the OS shell without validation or interpretation.
            cwd: Working directory for the subprocess. Falls back to
                config.work_dir, then os.getcwd().
            env: Optional environment variable overrides. Merged on top
                of the current process environment.
            on_output: Async callback receiving (stream_name, text) for
                each line of output. stream_name is "stdout" or "stderr".
            on_done: Async callback receiving (exit_code, status) when
                the process terminates. status is "completed", "killed",
                or "error".

        Raises:
            CommandAlreadyRunningError: If a command is already running.
        """
        if self._running:
            raise CommandAlreadyRunningError("A command is already running")

        self._running = True
        # Resolve working directory: explicit cwd > config.work_dir > os.getcwd()
        # If cwd is relative, resolve it against config.work_dir (project root)
        if cwd:
            from pathlib import Path
            cwd_path = Path(cwd)
            if not cwd_path.is_absolute():
                base = self._config.work_dir or os.getcwd()
                working_dir = str(Path(base) / cwd_path)
            else:
                working_dir = cwd
        else:
            working_dir = self._config.work_dir or os.getcwd()

        # Merge environment: inherit current env + user overrides
        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)

        logger.info(f"执行命令: {command!r}, cwd={working_dir}")

        try:
            # Cross-platform subprocess creation
            kwargs: dict = {
                "stdout": asyncio.subprocess.PIPE,
                "stderr": asyncio.subprocess.PIPE,
                "cwd": working_dir,
                "env": merged_env,
            }
            if sys.platform == "win32":
                # Hide console window for GUI mode
                kwargs["creationflags"] = 0x08000000  # CREATE_NO_WINDOW
            else:
                # Create new process group so kill_process_tree can use
                # killpg without affecting the Agent process itself
                kwargs["start_new_session"] = True
                # On Linux: set PR_SET_PDEATHSIG so child dies with parent
                from ..utils.process import get_subprocess_preexec_fn
                preexec = get_subprocess_preexec_fn()
                if preexec:
                    kwargs["preexec_fn"] = preexec

            self._process = await asyncio.create_subprocess_shell(
                command, **kwargs
            )
            logger.debug(f"子进程已启动: pid={self._process.pid}")

            # Windows: assign to Job Object for automatic cleanup on Agent exit
            from ..utils.process import assign_to_job
            assign_to_job(self._process.pid)

            # Stream stdout and stderr concurrently
            await asyncio.gather(
                self._stream_pipe(self._process.stdout, "stdout", on_output),
                self._stream_pipe(self._process.stderr, "stderr", on_output),
            )

            # Wait for process to finish and collect exit code
            exit_code = await self._process.wait()
            logger.info(f"命令完成: exit_code={exit_code}")

            if on_done:
                await on_done(exit_code, "completed")

        except asyncio.CancelledError:
            logger.warning("命令被取消，终止子进程树")
            # Kill the entire process tree to prevent zombie processes
            if self._process and self._process.returncode is None:
                from ..utils.process import kill_process_tree
                await kill_process_tree(self._process)
            if on_done:
                try:
                    await on_done(-1, "killed")
                except Exception:
                    pass  # WebSocket may already be closed during shutdown
        except Exception as e:
            logger.error(f"命令执行失败: {e}")
            if on_done:
                try:
                    await on_done(-1, "error")
                except Exception:
                    pass
        finally:
            self._process = None
            self._running = False

    async def stop(self) -> None:
        """Gracefully stop the running command.

        Uses utils/process.py to kill the entire process tree (including
        child processes like node.exe spawned by yarn/npm). On Windows,
        this uses taskkill /T /F to prevent zombie processes.

        No-op if no command is currently running.
        """
        if not self._process or not self._running:
            return

        from ..utils.process import kill_process_tree
        logger.info(f"停止命令: 终止进程树 pid={self._process.pid}")
        await kill_process_tree(self._process)

    async def _stream_pipe(
        self,
        pipe: asyncio.StreamReader | None,
        stream_name: str,
        on_output: Callable[[str, str], Awaitable[None]] | None,
    ) -> None:
        """Read lines from a subprocess pipe and forward via callback.

        Reads until EOF (pipe closed), decoding each line using the
        system's preferred encoding (UTF-8 on macOS/Linux, CP936/GBK
        on Chinese Windows) with replacement for invalid bytes.

        Args:
            pipe: The asyncio StreamReader for stdout or stderr.
            stream_name: Label for the stream ("stdout" or "stderr").
            on_output: Async callback to receive (stream_name, text).
        """
        if pipe is None:
            return
        from ..utils.encoding import decode_process_output
        while True:
            line = await pipe.readline()
            if not line:
                break
            text = decode_process_output(line)
            if on_output:
                await on_output(stream_name, text)
