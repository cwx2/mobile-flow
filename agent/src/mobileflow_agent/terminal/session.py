"""Unified terminal session interface.

Automatically selects the appropriate PTY backend based on the execution
environment:
    - ``native`` → NativePty (winpty on Windows / pty_fork on macOS+Linux).
    - ``wsl``    → WslPty.
    - unknown    → tries native first, then falls back to WSL.
"""

from __future__ import annotations

import shutil
import sys
from typing import AsyncGenerator, Optional

from loguru import logger


class TerminalSession:
    """A single terminal session wrapping a PTY backend.

    Attributes:
        session_id: Unique identifier for this session.
    """

    def __init__(self, session_id: str):
        self.session_id = session_id
        self._backend = None  # NativePty | WslPty | PipePty
        self._running = False
        self._cli_command = ""
        self._work_dir = ""
        self._cols = 80
        self._rows = 24
        self._execution_env = "native"

    async def start(
        self, cli_command: str, work_dir: str,
        cols: int = 80, rows: int = 24,
        execution_env: str = "native",
    ):
        """Start the terminal by selecting and initialising the PTY backend.

        Args:
            cli_command: CLI command to execute.
            work_dir: Working directory for the process.
            cols: Terminal width in columns.
            rows: Terminal height in rows.
            execution_env: Execution environment (``"native"`` or ``"wsl"``).
        """
        self._cli_command = cli_command
        self._work_dir = work_dir
        self._cols = cols
        self._rows = rows
        self._execution_env = execution_env

        self._backend = _create_backend(execution_env)
        logger.debug(f"终端会话启动: id={self.session_id[:8]}..., cmd={cli_command}, env={execution_env}")
        await self._backend.start(cli_command, work_dir, cols, rows)
        self._running = True

    async def read_output(self) -> AsyncGenerator[bytes, None]:
        """Yield output bytes from the PTY backend until it exits."""
        if self._backend:
            async for data in self._backend.read_output():
                yield data
        self._running = False

    async def write_input(self, data: str):
        """Write user input to the PTY backend.

        Args:
            data: Raw input string to send.
        """
        if self._backend:
            await self._backend.write_input(data)

    async def resize(self, cols: int, rows: int):
        """Resize the terminal.

        Args:
            cols: New width in columns.
            rows: New height in rows.
        """
        self._cols = cols
        self._rows = rows
        if self._backend:
            await self._backend.resize(cols, rows)

    async def stop(self) -> int | None:
        """Stop the session and return the exit code.

        Returns:
            The process exit code, or None if no backend was running.
        """
        self._running = False
        if self._backend:
            code = await self._backend.stop()
            self._backend = None
            logger.info(f"🖥️ 终端会话停止: {self.session_id}")
            return code
        return None

    @property
    def is_running(self) -> bool:
        """Whether the terminal session is currently active."""
        return self._running


def _create_backend(execution_env: str):
    """Create the appropriate PTY backend for the given execution environment.

    Args:
        execution_env: ``"wsl"`` for WSL, anything else for native.

    Returns:
        A PTY backend instance (NativePty, WslPty, or PipePty).
    """
    if execution_env == "wsl":
        from .pty_wsl import WslPty
        return WslPty()

    # Native environment
    if sys.platform == "win32":
        try:
            import winpty  # noqa: F401
            from .pty_native import NativePty
            return NativePty()
        except ImportError:
            logger.warning("未安装 pywinpty，使用管道模式")
            from .pty_pipe import PipePty
            return PipePty()

    # macOS / Linux
    from .pty_native import NativePty
    return NativePty()
