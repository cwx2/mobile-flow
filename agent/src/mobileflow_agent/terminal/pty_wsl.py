"""WSL PTY backend using ``wsl`` + ``script -qfc`` for pseudo-terminal support.

Only used when ``execution_env="wsl"``.  Wraps the CLI command inside a
``script`` session to provide PTY capabilities through the WSL bridge.
"""

from __future__ import annotations

import asyncio
from typing import AsyncGenerator, Optional

from loguru import logger

from ..utils.path import win_to_wsl


class WslPty:
    """WSL-based PTY backend using ``script -qfc``.

    Attributes:
        _process: The underlying ``wsl`` subprocess.
    """

    def __init__(self):
        self._process: Optional[asyncio.subprocess.Process] = None

    async def start(self, cli_command: str, work_dir: str, cols: int, rows: int):
        """Start a PTY session inside WSL.

        Converts the Windows working directory to a WSL path, sets terminal
        dimensions, and launches the CLI command inside ``script -qfc``.

        Args:
            cli_command: CLI command to execute inside WSL.
            work_dir: Windows-style working directory path.
            cols: Terminal width in columns.
            rows: Terminal height in rows.
        """
        wsl_dir = win_to_wsl(work_dir)
        inner_cmd = (
            f'stty cols {cols} rows {rows} 2>/dev/null; '
            f'export COLUMNS={cols} LINES={rows}; '
            f'{cli_command}'
        )
        wrapper = (
            f'cd "{wsl_dir}" && '
            f'export TERM=xterm-256color COLUMNS={cols} LINES={rows} && '
            f"script -qfc '{inner_cmd}' /dev/null"
        )
        self._process = await asyncio.create_subprocess_exec(
            "wsl", "bash", "-lc", wrapper,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        # Assign to Job Object for automatic cleanup on Agent exit (Windows)
        from ..utils.process import assign_to_job
        assign_to_job(self._process.pid)
        logger.info(f"🖥️ WSL PTY 启动: PID={self._process.pid}, cols={cols}, rows={rows}")

    async def read_output(self) -> AsyncGenerator[bytes, None]:
        """Yield output bytes from the WSL process."""
        if self._process and self._process.stdout:
            try:
                while True:
                    data = await self._process.stdout.read(4096)
                    if not data:
                        break
                    yield data
            except Exception as e:
                logger.warning(f"WSL PTY 读取出错: {e}")

    async def write_input(self, data: str):
        """Write user input to the WSL process stdin.

        Args:
            data: Raw input string.
        """
        if self._process and self._process.stdin:
            self._process.stdin.write(data.encode("utf-8"))
            await self._process.stdin.drain()

    async def resize(self, cols: int, rows: int):
        """Resize the terminal by sending an xterm escape sequence.

        Args:
            cols: New width in columns.
            rows: New height in rows.
        """
        if self._process and self._process.stdin:
            cmd = f"\x1b[8;{rows};{cols}t"
            self._process.stdin.write(cmd.encode())
            await self._process.stdin.drain()

    async def stop(self) -> int | None:
        """Terminate the WSL process and return its exit code.

        Returns:
            The process exit code, or None if no process was running.
        """
        if not self._process:
            return None
        try:
            self._process.terminate()
            code = await asyncio.wait_for(self._process.wait(), timeout=3)
            logger.debug(f"WSL PTY 进程退出: code={code}")
            return code
        except (asyncio.TimeoutError, ProcessLookupError):
            from ..utils.process import kill_process_tree_sync
            kill_process_tree_sync(self._process.pid)
            logger.warning("WSL PTY 进程强制终止")
            return -1
        finally:
            self._process = None

    @property
    def is_alive(self) -> bool:
        """Whether the WSL process is still running."""
        return self._process is not None and self._process.returncode is None
