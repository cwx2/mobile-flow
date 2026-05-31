"""Pipe-based PTY backend (fallback when no real PTY is available).

Does not support interactive input (no true PTY), but guarantees the
terminal handler will not crash.  Displays a warning on first output.
On Windows, ``.cmd`` / ``.bat`` files are wrapped with ``cmd /c``.
"""

from __future__ import annotations

import asyncio
import os
from typing import AsyncGenerator, Optional

from loguru import logger

from ..utils.command import resolve_command_list
from ..utils.i18n import t


class PipePty:
    """Pipe-mode terminal backend (fallback when pywinpty is unavailable).

    Attributes:
        _process: The underlying subprocess.
        _warning_sent: Whether the interactive-mode warning has been emitted.
    """

    def __init__(self):
        self._process: Optional[asyncio.subprocess.Process] = None
        self._warning_sent = False

    async def start(self, cli_command: str, work_dir: str, cols: int, rows: int):
        """Start the subprocess in pipe mode.

        Args:
            cli_command: CLI command string to execute.
            work_dir: Working directory for the process.
            cols: Terminal width (informational only — pipe mode cannot resize).
            rows: Terminal height (informational only).
        """
        logger.warning("⚠️ 使用管道模式（不支持交互输入）")
        parts = resolve_command_list(cli_command)
        logger.debug(f"管道模式启动: cmd={' '.join(parts)}")
        env = {**os.environ, "TERM": "xterm-256color", "COLUMNS": str(cols), "LINES": str(rows)}
        self._process = await asyncio.create_subprocess_exec(
            *parts, cwd=work_dir,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            env=env,
        )
        # Assign to Job Object for automatic cleanup on Agent exit (Windows)
        from ..utils.process import assign_to_job
        assign_to_job(self._process.pid)

    async def read_output(self) -> AsyncGenerator[bytes, None]:
        """Yield output bytes from the subprocess.

        Emits a warning message on the first read to inform the user that
        interactive mode is unavailable.
        """
        # Emit a one-time warning before the first real output
        if not self._warning_sent:
            self._warning_sent = True
            yield t("backend.pywinptyWarning").encode("utf-8")
        if self._process and self._process.stdout:
            try:
                while True:
                    data = await self._process.stdout.read(4096)
                    if not data:
                        break
                    yield data
            except Exception as e:
                logger.warning(f"管道读取出错: {e}")

    async def write_input(self, data: str):
        """Write user input to the subprocess stdin.

        Args:
            data: Raw input string.
        """
        if self._process and self._process.stdin:
            self._process.stdin.write(data.encode("utf-8"))
            await self._process.stdin.drain()

    async def resize(self, cols: int, rows: int):
        """No-op: pipe mode does not support terminal resize."""
        pass

    async def stop(self) -> int | None:
        """Terminate the subprocess and return its exit code.

        Returns:
            The process exit code, or None if no process was running.
        """
        if not self._process:
            return None
        try:
            self._process.terminate()
            code = await asyncio.wait_for(self._process.wait(), timeout=3)
            logger.debug(f"管道进程退出: code={code}")
            return code
        except (asyncio.TimeoutError, ProcessLookupError):
            from ..utils.process import kill_process_tree_sync
            kill_process_tree_sync(self._process.pid)
            logger.warning("管道进程强制终止")
            return -1
        finally:
            self._process = None

    @property
    def is_alive(self) -> bool:
        """Whether the subprocess is still running."""
        return self._process is not None and self._process.returncode is None
