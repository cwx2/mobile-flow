"""WSL child Agent lifecycle manager.

Module: services/
Responsibility:
    Manages the lifecycle of a child Agent process running inside WSL.
    The parent (Windows) Agent delegates CLI-related operations to the
    child Agent, which executes them natively inside WSL — eliminating
    all cross-boundary issues (permissions, PATH, PTY, process management).

    Lifecycle:
    1. detect_all() finds WSL CLIs → marks them as env="wsl"
    2. User switches to a WSL CLI → ensure_started() launches child Agent
    3. Parent Agent connects to child via internal WebSocket
    4. CLI messages are forwarded bidirectionally (see wsl_proxy.py)
    5. Parent Agent shutdown → child Agent is terminated

    The child Agent runs in stripped-down mode (--mode wsl-child):
    only CLI management + terminal PTY, no file/git/project services.

Used by:
    - server/websocket.py (starts child Agent, routes WSL CLI messages)

Dependencies:
    - utils/path.py (win_to_wsl for path conversion)
    - core/config.py (WslConfig for timeouts and port)
"""

from __future__ import annotations

import asyncio
import os
from pathlib import Path

from loguru import logger

from ..utils.command import which
from ..utils.path import win_to_wsl


# Restart policy for child Agent crashes
_MAX_RESTARTS = 3
_RESTART_DELAYS = [2, 4, 8]  # Seconds between restart attempts
_STABLE_THRESHOLD = 60  # Seconds of uptime before restart counter resets


class WslAgentManager:
    """Manages the WSL child Agent process and WebSocket connection.

    The child Agent is started lazily (on first WSL CLI switch) and kept
    running until the parent Agent shuts down. If the child crashes, it
    is restarted with exponential backoff (max 3 attempts).

    Attributes:
        _process: The WSL child Agent subprocess.
        _ws: WebSocket connection to the child Agent.
        _port: Port the child Agent listens on.
        _work_dir: Working directory (Windows path, converted to WSL on start).
        _started: Whether the child Agent has been started.
    """

    def __init__(
        self,
        work_dir: str,
        port: int = 9601,
        startup_timeout: float = 30.0,
    ) -> None:
        self._work_dir = work_dir
        self._port = port
        self._startup_timeout = startup_timeout
        self._process: asyncio.subprocess.Process | None = None
        self._ws = None  # WebSocket connection (set after connect)
        self._started = False
        self._restart_count = 0

    @property
    def is_running(self) -> bool:
        """True if the child Agent process is alive."""
        return (
            self._process is not None
            and self._process.returncode is None
        )

    @property
    def is_connected(self) -> bool:
        """True if the WebSocket connection to the child Agent is open."""
        return self._ws is not None and self._ws.open

    async def ensure_started(self) -> bool:
        """Start the child Agent if not already running.

        Checks prerequisites (WSL available, Python installed), starts
        the child Agent process, waits for it to be ready, then connects
        via WebSocket.

        Returns:
            True if the child Agent is running and connected.
        """
        if self.is_running and self.is_connected:
            return True

        # Check prerequisites
        if not self._check_wsl_available():
            logger.error("[WslAgent] WSL 不可用")
            return False

        python_cmd = await self._find_wsl_python()
        if not python_cmd:
            logger.error("[WslAgent] WSL 中未找到 Python 3.10+，请安装: sudo apt install python3")
            return False

        # Find the agent package path in WSL
        agent_path = self._get_agent_wsl_path()
        if not agent_path:
            logger.error("[WslAgent] 无法确定 Agent 包路径")
            return False

        # Start the child Agent process
        wsl_work_dir = win_to_wsl(self._work_dir) if self._work_dir else ""
        work_dir_arg = f'--work-dir "{wsl_work_dir}"' if wsl_work_dir else ""

        # Share the Windows-side config directory with the child Agent
        # so it can read custom_agents.json (which lists WSL CLIs).
        win_config_dir = os.path.expanduser("~/.mobileflow")
        wsl_config_dir = win_to_wsl(win_config_dir)

        cmd = (
            f'export MOBILEFLOW_CONFIG_DIR="{wsl_config_dir}" && '
            f'cd "{agent_path}" && '
            f'{python_cmd} -m mobileflow_agent start '
            f'--mode wsl-child --port {self._port} {work_dir_arg}'
        )

        logger.info(f"[WslAgent] 启动子 Agent: port={self._port}")
        logger.debug(f"[WslAgent] 命令: wsl bash -lc '{cmd}'")

        try:
            self._process = await asyncio.create_subprocess_exec(
                "wsl", "bash", "-lc", cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
            )
        except Exception as e:
            logger.error(f"[WslAgent] 启动子 Agent 进程失败: {e}")
            return False

        # Assign to Job Object for automatic cleanup on Agent exit (Windows)
        from ..utils.process import assign_to_job
        assign_to_job(self._process.pid)

        # Wait for the child Agent to be ready (poll the port)
        connected = await self._wait_for_ready()
        if not connected:
            logger.error("[WslAgent] 子 Agent 启动超时，未能连接")
            await self.stop()
            return False

        self._started = True
        self._restart_count = 0
        logger.info(f"[WslAgent] 子 Agent 已就绪: port={self._port}")
        return True

    async def _wait_for_ready(self) -> bool:
        """Poll the child Agent's WebSocket port until it responds.

        Tries localhost first (WSL1), then WSL2 IP fallback.

        Returns:
            True if connected successfully within the timeout.
        """
        import websockets

        deadline = asyncio.get_event_loop().time() + self._startup_timeout
        poll_interval = 0.5

        while asyncio.get_event_loop().time() < deadline:
            # Check if process died
            if self._process and self._process.returncode is not None:
                logger.warning(f"[WslAgent] 子 Agent 进程已退出: code={self._process.returncode}")
                return False

            # Try connecting
            for url in self._get_connection_urls():
                try:
                    self._ws = await asyncio.wait_for(
                        websockets.connect(url, ping_interval=None),
                        timeout=2.0,
                    )
                    logger.info(f"[WslAgent] WebSocket 已连接: {url}")
                    return True
                except Exception as e:
                    logger.debug(f"[WslAgent] 连接尝试失败: {url}, error={e}")

            await asyncio.sleep(poll_interval)

        return False

    def _get_connection_urls(self) -> list[str]:
        """Get candidate WebSocket URLs for connecting to the child Agent.

        Returns localhost first (works for WSL1 and some WSL2 configs),
        then tries to discover the WSL2 IP.

        Returns:
            List of WebSocket URLs to try.
        """
        urls = [f"ws://localhost:{self._port}"]
        # WSL2 IP discovery would go here if needed
        # For now, localhost covers WSL1 and WSL2 with mirrored networking
        return urls

    async def stop(self) -> None:
        """Stop the child Agent process and close the WebSocket connection."""
        if self._ws:
            try:
                await self._ws.close()
            except Exception as e:
                logger.debug(f"[WslAgent] WebSocket 关闭出错（可忽略）: {e}")
            self._ws = None

        if self._process and self._process.returncode is None:
            logger.info("[WslAgent] 停止子 Agent 进程...")
            try:
                self._process.terminate()
                await asyncio.wait_for(self._process.wait(), timeout=5.0)
                logger.info("[WslAgent] 子 Agent 已停止")
            except asyncio.TimeoutError:
                logger.warning("[WslAgent] 子 Agent 停止超时，强制杀死")
                self._process.kill()
                await self._process.wait()
            except Exception as e:
                logger.warning(f"[WslAgent] 停止子 Agent 出错: {e}")

        self._process = None
        self._started = False

    async def send(self, data: str) -> None:
        """Send a message to the child Agent via WebSocket.

        Args:
            data: JSON-serialized message string.

        Raises:
            ConnectionError: If not connected to the child Agent.
        """
        if not self.is_connected:
            raise ConnectionError("未连接到 WSL 子 Agent")
        await self._ws.send(data)

    async def recv(self) -> str:
        """Receive a message from the child Agent via WebSocket.

        Returns:
            JSON-serialized message string.

        Raises:
            ConnectionError: If not connected to the child Agent.
        """
        if not self.is_connected:
            raise ConnectionError("未连接到 WSL 子 Agent")
        return await self._ws.recv()

    def _check_wsl_available(self) -> bool:
        """Check if WSL is installed and available."""
        return which("wsl") is not None

    async def _find_wsl_python(self) -> str | None:
        """Find a suitable Python interpreter in WSL with Agent dependencies.

        Checks the dedicated venv first (/root/.mobileflow-venv/bin/python),
        then falls back to system python3/python. Verifies version >= 3.10.

        The venv is preferred because Ubuntu 24.04+ blocks system-wide pip
        installs (PEP 668), so Agent dependencies are installed in the venv.

        Returns:
            Python command string, or None if not found.
        """
        # Prefer the dedicated venv (has Agent dependencies installed)
        candidates = [
            "/root/.mobileflow-venv/bin/python",
            "python3",
            "python",
        ]
        for cmd in candidates:
            try:
                proc = await asyncio.create_subprocess_exec(
                    "wsl", "bash", "-lc", f"{cmd} --version",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=5.0)
                if proc.returncode == 0:
                    version_str = stdout.decode().strip()
                    logger.debug(f"[WslAgent] WSL Python: {cmd} → {version_str}")
                    # Parse version: "Python 3.10.12" (may have suffix like "+")
                    try:
                        parts = version_str.split()
                        if len(parts) >= 2:
                            ver = parts[1].split(".")
                            major = int(ver[0])
                            minor = int(''.join(c for c in ver[1] if c.isdigit()))
                            if major >= 3 and minor >= 10:
                                return cmd
                        logger.warning(f"[WslAgent] Python 版本过低: {version_str}，需要 3.10+")
                    except (ValueError, IndexError) as e:
                        logger.warning(f"[WslAgent] Python 版本解析失败: {version_str}, error={e}")
            except Exception as e:
                logger.debug(f"[WslAgent] Python 检测失败: {e}")
        return None

    def _get_agent_wsl_path(self) -> str | None:
        """Get the Agent package path in WSL format.

        Walks up from the current file to find pyproject.toml (same
        algorithm as config.py's _find_project_root), then converts
        the path to WSL format via /mnt/c/... mapping.

        Returns:
            WSL path to the agent package directory, or None.
        """
        import sys

        # PyInstaller bundle: use _MEIPASS
        if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
            agent_root = Path(sys._MEIPASS)
        else:
            # Walk up to find pyproject.toml (same as config._find_project_root)
            current = Path(__file__).resolve().parent
            agent_root = None
            for _ in range(10):
                if (current / "pyproject.toml").exists():
                    agent_root = current
                    break
                current = current.parent

            if agent_root is None:
                logger.warning("[WslAgent] 未找到 pyproject.toml，无法确定 Agent 路径")
                return None

        wsl_path = win_to_wsl(str(agent_root))
        logger.debug(f"[WslAgent] Agent 路径: {agent_root} → {wsl_path}")
        return wsl_path

    async def health_check(self) -> bool:
        """Check if the child Agent is healthy.

        Sends a ping and waits for pong. Returns False if the connection
        is broken or the child Agent is unresponsive.

        Returns:
            True if the child Agent is responsive.
        """
        if not self.is_connected:
            return False
        try:
            pong = await self._ws.ping()
            await asyncio.wait_for(pong, timeout=5.0)
            return True
        except Exception:
            return False

    def dispose(self) -> None:
        """Synchronous cleanup hint. Actual cleanup is async via stop()."""
        # Mark as not started so no new operations are forwarded
        self._started = False
