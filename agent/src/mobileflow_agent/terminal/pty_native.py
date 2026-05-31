"""Native PTY backend.

Platform-specific implementations:
    - Windows: ConPTY. Uses pywinpty in development mode, and a custom
      ctypes wrapper (conpty_wrapper.py) in PyInstaller frozen mode to
      work around a pywinpty stdin inheritance bug.
    - macOS / Linux: ``pty.openpty()`` + ``fork()``.

All commands are resolved via ``utils.command.resolve_command_str()``.
"""

from __future__ import annotations

import asyncio
import os
import sys
from typing import AsyncGenerator, Optional

from loguru import logger

from ..utils.command import resolve_command_list, resolve_command_str


class NativePty:
    """Native PTY backend (Windows winpty / macOS+Linux pty_fork).

    Attributes:
        _winpty: WinPTY process handle (Windows only).
        _master_fd: Master file descriptor (Unix pty_fork only).
        _child_pid: Child process PID (Unix pty_fork only).
        _method: Active backend identifier (``"winpty"`` or ``"pty_fork"``).
    """

    def __init__(self):
        self._winpty = None
        self._master_fd: Optional[int] = None
        self._child_pid: Optional[int] = None
        self._method = ""  # "winpty" | "pty_fork"

    async def start(self, cli_command: str, work_dir: str, cols: int, rows: int):
        """Start the PTY process.

        Args:
            cli_command: CLI command string to execute.
            work_dir: Working directory for the process.
            cols: Terminal width in columns.
            rows: Terminal height in rows.
        """
        if sys.platform == "win32":
            await self._start_winpty(cli_command, work_dir, cols, rows)
        else:
            await self._start_pty_fork(cli_command, work_dir, cols, rows)

    async def _start_winpty(self, cli_command: str, work_dir: str, cols: int, rows: int):
        """Start a terminal via ConPTY (Windows).

        Uses pywinpty's PtyProcess in development mode. In PyInstaller
        frozen mode, uses our custom ConPtyProcess wrapper to work around
        the winpty-rs stdin inheritance bug (see conpty_wrapper.py).

        Args:
            cli_command: CLI command string.
            work_dir: Working directory.
            cols: Terminal width.
            rows: Terminal height.
        """
        # Resolve command via the shared utility — handles .cmd/.bat
        # wrapping with cmd /c automatically (see utils/command.py)
        resolved_cmd = resolve_command_str(cli_command)

        env = {**os.environ, "TERM": "xterm-256color"}

        # PyInstaller prepends its _MEIPASS temp dir to PATH, which can
        # break child processes that rely on the original user PATH.
        if getattr(sys, 'frozen', False):
            original_path = os.environ.get("PATH", "")
            meipass = getattr(sys, '_MEIPASS', "")
            if meipass:
                cleaned = os.pathsep.join(
                    p for p in original_path.split(os.pathsep)
                    if not p.startswith(meipass)
                )
                env["PATH"] = cleaned
                logger.debug("WinPTY PATH cleaned: removed _MEIPASS entries")

        logger.debug(f"WinPTY spawn: cmd={resolved_cmd!r}, cwd={work_dir!r}, dims=({rows},{cols})")

        if getattr(sys, 'frozen', False):
            # WORKAROUND: pywinpty (winpty-rs) ConPTY stdin inheritance bug.
            # In frozen (PyInstaller) mode, use our custom ConPTY wrapper
            # that sets STARTF_USESTDHANDLES to prevent handle duplication.
            # See conpty_wrapper.py for full explanation.
            # TODO: Remove when pywinpty fixes winpty-rs#49.
            from .conpty_wrapper import ConPtyProcess
            self._winpty = ConPtyProcess.spawn(
                resolved_cmd, dimensions=(rows, cols), cwd=work_dir, env=env,
            )
        else:
            from winpty import PtyProcess
            self._winpty = PtyProcess.spawn(
                resolved_cmd, dimensions=(rows, cols), cwd=work_dir, env=env,
            )

        self._method = "winpty"
        logger.info(f"🖥️ WinPTY 启动: pid={self._winpty.pid}")

    async def _start_pty_fork(self, cli_command: str, work_dir: str, cols: int, rows: int):
        """Start a terminal via pty fork (macOS / Linux).

        Args:
            cli_command: CLI command string.
            work_dir: Working directory.
            cols: Terminal width.
            rows: Terminal height.
        """
        import pty
        import fcntl
        import termios
        import struct

        master_fd, slave_fd = pty.openpty()
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)

        # Resolve command via the shared utility (no .cmd wrapping needed
        # on Unix, but keeps the resolution logic in one place)
        cmd_list = resolve_command_list(cli_command)
        resolved = cmd_list[0]
        args = cmd_list[1:]

        pid = os.fork()
        if pid == 0:
            # Child process
            os.setsid()
            os.dup2(slave_fd, 0)
            os.dup2(slave_fd, 1)
            os.dup2(slave_fd, 2)
            os.close(master_fd)
            os.close(slave_fd)
            os.chdir(work_dir)
            os.environ["TERM"] = "xterm-256color"
            os.environ["COLUMNS"] = str(cols)
            os.environ["LINES"] = str(rows)
            os.execvp(resolved, [resolved] + args)
        else:
            os.close(slave_fd)
            self._master_fd = master_fd
            self._child_pid = pid
            self._method = "pty_fork"
            logger.info(f"🖥️ PTY fork 启动: child_pid={pid}")

    async def read_output(self) -> AsyncGenerator[bytes, None]:
        """Yield output bytes from the PTY until the process exits."""
        loop = asyncio.get_event_loop()
        if self._method == "winpty" and self._winpty:
            read_count = 0
            while self._winpty:
                try:
                    data = await loop.run_in_executor(None, self._winpty.read, 4096)
                    if data:
                        read_count += 1
                        # Log first few reads to help diagnose early exit
                        if read_count <= 3:
                            safe = data[:200].replace('\r', '\\r').replace('\n', '\\n')
                            logger.debug(f"WinPTY read #{read_count}: {safe!r}")
                        yield data.encode("utf-8") if isinstance(data, str) else data
                    else:
                        logger.debug(f"WinPTY read 返回空数据，退出循环 (共读取 {read_count} 次)")
                        break
                except Exception as e:
                    logger.debug(f"WinPTY read 异常: {e} (共读取 {read_count} 次)")
                    break
            logger.debug(f"WinPTY read_output 结束: alive={self._winpty is not None}, reads={read_count}")
        elif self._method == "pty_fork" and self._master_fd is not None:
            while self._master_fd is not None:
                try:
                    data = await loop.run_in_executor(None, os.read, self._master_fd, 4096)
                    if data:
                        yield data
                    else:
                        break
                except OSError:
                    break

    async def write_input(self, data: str):
        """Write user input to the PTY.

        Args:
            data: Raw input string.
        """
        encoded = data.encode("utf-8")
        if self._method == "winpty" and self._winpty:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self._winpty.write, data)
        elif self._method == "pty_fork" and self._master_fd is not None:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, os.write, self._master_fd, encoded)

    async def resize(self, cols: int, rows: int):
        """Resize the terminal window.

        Args:
            cols: New width in columns.
            rows: New height in rows.
        """
        if self._method == "winpty" and self._winpty:
            self._winpty.setwinsize(rows, cols)
        elif self._method == "pty_fork" and self._master_fd is not None:
            import fcntl, termios, struct, signal
            winsize = struct.pack("HHHH", rows, cols, 0, 0)
            fcntl.ioctl(self._master_fd, termios.TIOCSWINSZ, winsize)
            if self._child_pid:
                os.kill(self._child_pid, signal.SIGWINCH)

    async def stop(self) -> int | None:
        """Stop the PTY process and clean up resources.

        Returns:
            The process exit code, or None if no process was running.
        """
        if self._method == "winpty" and self._winpty:
            try:
                self._winpty.close()
            except Exception as e:
                logger.debug(f"WinPTY 关闭出错（可忽略）: {e}")
            self._winpty = None
            logger.debug("WinPTY 进程已停止")
            return 0
        elif self._method == "pty_fork":
            if self._master_fd is not None:
                try:
                    os.close(self._master_fd)
                except OSError:
                    pass
                self._master_fd = None
            if self._child_pid:
                import signal
                try:
                    os.kill(self._child_pid, signal.SIGTERM)
                    await asyncio.sleep(0.5)
                    _, status = os.waitpid(self._child_pid, os.WNOHANG)
                    if os.WIFEXITED(status):
                        code = os.WEXITSTATUS(status)
                        logger.debug(f"PTY fork 进程退出: pid={self._child_pid}, code={code}")
                        return code
                    os.kill(self._child_pid, signal.SIGKILL)
                except (ProcessLookupError, OSError, ChildProcessError):
                    pass
                self._child_pid = None
            logger.debug("PTY fork 进程已停止")
            return -1
        return None

    @property
    def is_alive(self) -> bool:
        """Whether the PTY process is still running."""
        if self._method == "winpty":
            return self._winpty is not None
        if self._method == "pty_fork":
            return self._master_fd is not None
        return False
