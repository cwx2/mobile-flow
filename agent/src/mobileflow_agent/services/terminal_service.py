"""
跨平台 PTY 终端会话管理

模块：services/
职责：
  创建真正的伪终端（PTY），让 CLI 认为自己在真实终端中。
  支持三种平台：
  - WSL: 用 script -qfc 包装创建 PTY
  - Windows 原生: 用 winpty (pywinpty) 创建 ConPTY
  - Linux/macOS: 用 Python 标准库 pty.openpty()

被谁调用：
  - server/handlers/terminal_handler.py

设计参考：
  - docs/terminal-pty-plan.md
"""

from __future__ import annotations

import asyncio
import os
import sys
from typing import AsyncGenerator, Optional

from loguru import logger


def _detect_pty_method(execution_env: str) -> str:
    """检测当前平台应该使用哪种 PTY 方案"""
    if execution_env == "wsl":
        return "wsl_script"
    if sys.platform == "win32":
        try:
            import winpty  # noqa: F401
            return "winpty"
        except ImportError:
            # 没有 winpty，回退到 WSL script（如果有 WSL）
            import shutil
            if shutil.which("wsl"):
                return "wsl_script"
            return "pipe"  # 最后回退到管道模式
    # Linux / macOS
    return "pty_fork"


class TerminalSession:
    """单个终端会话，管理一个 PTY 进程"""

    def __init__(self, session_id: str):
        self.session_id = session_id
        self._running = False
        self._cols = 80
        self._rows = 24
        self._method = "pipe"
        # 不同方案的内部状态
        self._process: Optional[asyncio.subprocess.Process] = None
        self._winpty = None  # winpty.PtyProcess
        self._master_fd: Optional[int] = None  # pty fork 的 master fd
        self._child_pid: Optional[int] = None  # pty fork 的子进程 pid

    async def start(
        self,
        cli_command: str,
        work_dir: str,
        cols: int = 80,
        rows: int = 24,
        execution_env: str = "native",
    ):
        """启动终端会话，自动选择 PTY 方案"""
        self._cols = cols
        self._rows = rows
        self._method = _detect_pty_method(execution_env)
        logger.info(f"🖥️ 终端启动: method={self._method}, cmd={cli_command}, cols={cols}, rows={rows}")

        if self._method == "wsl_script":
            await self._start_wsl_script(cli_command, work_dir, cols, rows)
        elif self._method == "winpty":
            await self._start_winpty(cli_command, work_dir, cols, rows)
        elif self._method == "pty_fork":
            await self._start_pty_fork(cli_command, work_dir, cols, rows)
        else:
            await self._start_pipe(cli_command, work_dir, cols, rows)

        self._running = True

    async def _start_wsl_script(self, cli_command: str, work_dir: str, cols: int, rows: int):
        """WSL 模式：用 script -qfc 创建 PTY"""
        wsl_dir = self._win_to_wsl(work_dir)
        # script 创建 PTY 后，在内部用 stty 设置终端大小
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
        logger.info(f"🖥️ WSL script PTY 启动: PID={self._process.pid}, cols={cols}, rows={rows}")

    async def _start_winpty(self, cli_command: str, work_dir: str, cols: int, rows: int):
        """Windows 原生：用 pywinpty 创建 ConPTY"""
        from winpty import PtyProcess
        env = {**os.environ, "TERM": "xterm-256color"}
        self._winpty = PtyProcess.spawn(
            cli_command,
            dimensions=(rows, cols),
            cwd=work_dir,
            env=env,
        )
        logger.info(f"🖥️ WinPTY 启动: pid={self._winpty.pid}")

    async def _start_pty_fork(self, cli_command: str, work_dir: str, cols: int, rows: int):
        """Linux/macOS：用 pty.openpty() 创建伪终端"""
        import pty
        import fcntl
        import termios
        import struct

        master_fd, slave_fd = pty.openpty()
        # 设置终端大小
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)

        pid = os.fork()
        if pid == 0:
            # 子进程
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
            parts = cli_command.split()
            os.execvp(parts[0], parts)
        else:
            # 父进程
            os.close(slave_fd)
            self._master_fd = master_fd
            self._child_pid = pid
            logger.info(f"🖥️ PTY fork 启动: child_pid={pid}, master_fd={master_fd}")

    async def _start_pipe(self, cli_command: str, work_dir: str, cols: int, rows: int):
        """回退方案：普通管道（不支持交互输入）"""
        logger.warning("⚠️ 使用管道模式（不支持交互输入），建议安装 pywinpty")
        self._process = await asyncio.create_subprocess_exec(
            *cli_command.split(),
            cwd=work_dir,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            env={**os.environ, "TERM": "xterm-256color", "COLUMNS": str(cols), "LINES": str(rows)},
        )

    async def read_output(self) -> AsyncGenerator[bytes, None]:
        """读取终端输出（原始字节，含 ANSI 转义序列）"""
        if self._method == "winpty":
            # winpty 的 read 是阻塞的，放在线程中
            loop = asyncio.get_event_loop()
            while self._running and self._winpty:
                try:
                    data = await loop.run_in_executor(None, self._winpty.read, 4096)
                    if data:
                        yield data.encode("utf-8") if isinstance(data, str) else data
                    else:
                        break
                except Exception:
                    break
        elif self._method == "pty_fork" and self._master_fd is not None:
            # pty fork：从 master_fd 读取
            loop = asyncio.get_event_loop()
            while self._running and self._master_fd is not None:
                try:
                    data = await loop.run_in_executor(None, os.read, self._master_fd, 4096)
                    if data:
                        yield data
                    else:
                        break
                except OSError:
                    break
        elif self._process and self._process.stdout:
            # pipe / wsl_script：从 stdout 读取
            try:
                while self._running:
                    data = await self._process.stdout.read(4096)
                    if not data:
                        break
                    yield data
            except Exception as e:
                logger.warning(f"终端读取出错: {e}")
        self._running = False

    async def write_input(self, data: str):
        """写入用户输入到终端"""
        encoded = data.encode("utf-8")
        if self._method == "winpty" and self._winpty:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self._winpty.write, data)
        elif self._method == "pty_fork" and self._master_fd is not None:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, os.write, self._master_fd, encoded)
        elif self._process and self._process.stdin:
            self._process.stdin.write(encoded)
            await self._process.stdin.drain()

    async def resize(self, cols: int, rows: int):
        """调整终端尺寸"""
        self._cols = cols
        self._rows = rows
        if self._method == "winpty" and self._winpty:
            self._winpty.setwinsize(rows, cols)
        elif self._method == "pty_fork" and self._master_fd is not None:
            import fcntl, termios, struct
            winsize = struct.pack("HHHH", rows, cols, 0, 0)
            fcntl.ioctl(self._master_fd, termios.TIOCSWINSZ, winsize)
            # 发送 SIGWINCH 给子进程
            if self._child_pid:
                import signal
                os.kill(self._child_pid, signal.SIGWINCH)
        elif self._process and self._process.stdin:
            # WSL script / pipe：发送 ANSI resize 序列
            cmd = f"\x1b[8;{rows};{cols}t"
            self._process.stdin.write(cmd.encode())
            await self._process.stdin.drain()

    async def stop(self):
        """停止终端会话"""
        self._running = False
        if self._method == "winpty" and self._winpty:
            try:
                self._winpty.close()
            except Exception:
                pass
            self._winpty = None
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
                    os.kill(self._child_pid, signal.SIGKILL)
                except (ProcessLookupError, OSError):
                    pass
                self._child_pid = None
        elif self._process:
            try:
                self._process.terminate()
                await asyncio.wait_for(self._process.wait(), timeout=3)
            except (asyncio.TimeoutError, ProcessLookupError):
                self._process.kill()
            finally:
                self._process = None
        logger.info(f"🖥️ 终端会话停止: {self.session_id}")

    @property
    def is_running(self) -> bool:
        return self._running

    @staticmethod
    def _win_to_wsl(path: str) -> str:
        p = path.replace("\\", "/")
        if len(p) >= 2 and p[1] == ":":
            return f"/mnt/{p[0].lower()}{p[2:]}"
        return p


class TerminalManager:
    """管理多个终端会话"""

    def __init__(self):
        self._sessions: dict[str, TerminalSession] = {}

    async def create_session(
        self, session_id: str, cli_command: str, work_dir: str,
        cols: int = 80, rows: int = 24, execution_env: str = "native",
    ) -> TerminalSession:
        if session_id in self._sessions:
            await self._sessions[session_id].stop()
        session = TerminalSession(session_id)
        await session.start(cli_command, work_dir, cols, rows, execution_env)
        self._sessions[session_id] = session
        return session

    def get_session(self, session_id: str) -> Optional[TerminalSession]:
        return self._sessions.get(session_id)

    async def stop_session(self, session_id: str):
        session = self._sessions.pop(session_id, None)
        if session:
            await session.stop()

    async def stop_all(self):
        for session in list(self._sessions.values()):
            await session.stop()
        self._sessions.clear()
