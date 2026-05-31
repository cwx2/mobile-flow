"""Port Detector service for the Test Panel.

Monitors OS-level TCP socket state to detect new listening ports
opened by a subprocess. Cross-platform: macOS (lsof), Linux (ss),
Windows (netstat).

Also supports output-based detection: parses subprocess stdout for
common URL patterns (e.g. "http://localhost:3000") to extract the port.

Used by TestPanelHandler during preview.start to wait for the dev
server to begin listening before sending preview.ready.

Architecture:
    - Polls OS-level socket state at 500ms intervals
    - Supports known_port mode (just wait for specific port)
    - Supports auto-detect mode (find new ports opened by PID tree)
    - Supports output-based mode (parse URLs from stdout)
    - Timeout after configurable duration (default 30s)
"""

from __future__ import annotations

import asyncio
import re
import sys
from typing import Set

from loguru import logger

from ..utils.encoding import decode_process_output

# Regex patterns to extract port from common dev server output.
# Matches: http://localhost:3000, http://127.0.0.1:8080,
# https://de4.nmm.com:7001, etc.
_PORT_PATTERNS = [
    # Standard localhost/loopback URLs
    re.compile(r"https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0):(\d+)"),
    # Any URL with explicit port (covers custom domains like de4.nmm.com:7001)
    re.compile(r"https?://[\w.\-]+:(\d+)"),
    # Text patterns: "listening on port 8080", "started on port 3000"
    re.compile(r"(?:listening|running|started|ready|serving)\s+(?:on|at)\s+(?:port\s+)?(\d{2,5})", re.IGNORECASE),
    re.compile(r"port\s*[:=]\s*(\d{2,5})", re.IGNORECASE),
]


class PortDetector:
    """Monitors OS-level socket state to detect new listening ports.

    Works on macOS (lsof), Linux (ss/netstat), and Windows (netstat).
    Also supports output-based detection by parsing subprocess stdout
    for URL patterns containing port numbers.

    Usage:
        detector = PortDetector()
        port = await detector.watch_process(pid=12345, timeout=30.0)
        # or wait for a known port:
        port = await detector.watch_process(pid=12345, known_port=3000)
        # or parse port from output:
        port = detector.extract_port_from_output("Local: http://localhost:3000/")
    """

    _POLL_INTERVAL = 0.5  # seconds between polls

    @staticmethod
    def extract_port_from_output(text: str) -> int | None:
        """Extract a port number from subprocess output text.

        Scans the text for common dev server URL patterns like
        "http://localhost:3000" or "listening on port 8080".

        Args:
            text: A line or block of subprocess output.

        Returns:
            The extracted port number (1-65535), or None if not found.
        """
        for pattern in _PORT_PATTERNS:
            match = pattern.search(text)
            if match:
                port = int(match.group(1))
                if 1 <= port <= 65535:
                    return port
        return None

    async def watch_process(
        self,
        pid: int,
        timeout: float = 30.0,
        known_port: int | None = None,
    ) -> int | None:
        """Watch for new listening TCP ports opened by pid or its children.

        If known_port is specified, just wait for that port to start
        listening (regardless of which process owns it). If known_port
        is None, detect any new listening port opened by the process tree.

        Args:
            pid: Process ID to monitor.
            timeout: Maximum seconds to wait before giving up.
            known_port: If specified, wait for this specific port to listen.

        Returns:
            The detected port number, or None on timeout.
        """
        logger.info(f"端口检测开始: pid={pid}, timeout={timeout}s, known_port={known_port}")

        if known_port is not None:
            return await self._wait_for_known_port(known_port, timeout)
        else:
            return await self._detect_new_port(pid, timeout)

    async def _wait_for_known_port(self, port: int, timeout: float) -> int | None:
        """Wait for a specific port to start listening.

        Polls the system socket state until the port appears as LISTEN,
        or timeout expires.

        Args:
            port: The port number to wait for.
            timeout: Maximum seconds to wait.

        Returns:
            The port number if it starts listening, None on timeout.
        """
        elapsed = 0.0
        while elapsed < timeout:
            listening = await self._get_listening_ports()
            if port in listening:
                logger.info(f"端口已就绪: port={port}, elapsed={elapsed:.1f}s")
                return port
            await asyncio.sleep(self._POLL_INTERVAL)
            elapsed += self._POLL_INTERVAL

        logger.warning(f"端口检测超时: port={port}, timeout={timeout}s")
        return None

    async def _detect_new_port(self, pid: int, timeout: float) -> int | None:
        """Detect new listening ports opened by a process tree.

        Takes a baseline snapshot of listening ports, then polls for
        new ports that appear and belong to the target PID or children.

        Args:
            pid: Process ID whose port tree to monitor.
            timeout: Maximum seconds to wait.

        Returns:
            The first new port detected, or None on timeout.
        """
        # Baseline: ports already listening before the process started
        baseline = await self._get_listening_ports()
        logger.debug(f"端口基线: {len(baseline)} 个已监听端口")

        elapsed = 0.0
        while elapsed < timeout:
            await asyncio.sleep(self._POLL_INTERVAL)
            elapsed += self._POLL_INTERVAL

            current = await self._get_listening_ports()
            new_ports = current - baseline

            if new_ports:
                # Check if any new port belongs to our process tree
                pid_ports = await self._get_ports_for_pid(pid)
                matched = new_ports & pid_ports
                if matched:
                    port = min(matched)  # Pick lowest port if multiple
                    logger.info(f"检测到新端口: port={port}, pid={pid}, elapsed={elapsed:.1f}s")
                    return port

        logger.warning(f"端口自动检测超时: pid={pid}, timeout={timeout}s")
        return None

    async def _get_listening_ports(self) -> Set[int]:
        """Get all currently listening TCP ports on the system.

        Uses platform-specific commands:
        - macOS: lsof -iTCP -sTCP:LISTEN -nP
        - Linux: ss -tlnp
        - Windows: netstat -an -p TCP

        Returns:
            Set of port numbers currently in LISTEN state.
        """
        try:
            if sys.platform == "darwin":
                return await self._get_listening_ports_macos()
            elif sys.platform == "linux":
                return await self._get_listening_ports_linux()
            elif sys.platform == "win32":
                return await self._get_listening_ports_windows()
            else:
                logger.warning(f"不支持的平台: {sys.platform}")
                return set()
        except Exception as e:
            logger.debug(f"获取监听端口失败: {e}")
            return set()

    async def _get_listening_ports_macos(self) -> Set[int]:
        """Get listening ports on macOS using lsof."""
        proc = await asyncio.create_subprocess_exec(
            "lsof", "-iTCP", "-sTCP:LISTEN", "-nP", "-F", "n",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await proc.communicate()
        ports: Set[int] = set()
        for line in decode_process_output(stdout).splitlines():
            # lsof -F n outputs lines like "n*:3000" or "n127.0.0.1:8080"
            if line.startswith("n") and ":" in line:
                try:
                    port_str = line.rsplit(":", 1)[-1]
                    ports.add(int(port_str))
                except (ValueError, IndexError):
                    pass
        return ports

    async def _get_listening_ports_linux(self) -> Set[int]:
        """Get listening ports on Linux using ss."""
        proc = await asyncio.create_subprocess_exec(
            "ss", "-tlnp",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await proc.communicate()
        ports: Set[int] = set()
        for line in decode_process_output(stdout).splitlines():
            # ss output: LISTEN  0  128  *:3000  *:*
            # Local address is the 4th column, port after last ':'
            parts = line.split()
            if len(parts) >= 4 and parts[0] == "LISTEN":
                local_addr = parts[3]
                try:
                    port_str = local_addr.rsplit(":", 1)[-1]
                    ports.add(int(port_str))
                except (ValueError, IndexError):
                    pass
        return ports

    async def _get_listening_ports_windows(self) -> Set[int]:
        """Get listening ports on Windows using netstat."""
        proc = await asyncio.create_subprocess_exec(
            "netstat", "-an", "-p", "TCP",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await proc.communicate()
        ports: Set[int] = set()
        for line in decode_process_output(stdout).splitlines():
            # netstat output: TCP  0.0.0.0:3000  0.0.0.0:0  LISTENING
            if "LISTENING" in line:
                parts = line.split()
                if len(parts) >= 2:
                    local_addr = parts[1]
                    try:
                        port_str = local_addr.rsplit(":", 1)[-1]
                        ports.add(int(port_str))
                    except (ValueError, IndexError):
                        pass
        return ports

    async def _get_ports_for_pid(self, pid: int) -> Set[int]:
        """Get listening ports owned by a specific PID and its children.

        Args:
            pid: Process ID to check.

        Returns:
            Set of port numbers owned by the process tree.
        """
        try:
            if sys.platform == "darwin":
                return await self._get_ports_for_pid_macos(pid)
            elif sys.platform == "linux":
                return await self._get_ports_for_pid_linux(pid)
            elif sys.platform == "win32":
                return await self._get_ports_for_pid_windows(pid)
            else:
                return set()
        except Exception as e:
            logger.debug(f"获取进程端口失败: pid={pid}, error={e}")
            return set()

    async def _get_ports_for_pid_macos(self, pid: int) -> Set[int]:
        """Get listening ports for a PID on macOS."""
        proc = await asyncio.create_subprocess_exec(
            "lsof", "-iTCP", "-sTCP:LISTEN", "-nP", f"-p{pid}", "-F", "n",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await proc.communicate()
        ports: Set[int] = set()
        for line in decode_process_output(stdout).splitlines():
            if line.startswith("n") and ":" in line:
                try:
                    port_str = line.rsplit(":", 1)[-1]
                    ports.add(int(port_str))
                except (ValueError, IndexError):
                    pass
        return ports

    async def _get_ports_for_pid_linux(self, pid: int) -> Set[int]:
        """Get listening ports for a PID on Linux."""
        proc = await asyncio.create_subprocess_exec(
            "ss", "-tlnp",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await proc.communicate()
        ports: Set[int] = set()
        pid_str = f"pid={pid}"
        for line in decode_process_output(stdout).splitlines():
            if pid_str in line and "LISTEN" in line:
                parts = line.split()
                if len(parts) >= 4:
                    local_addr = parts[3]
                    try:
                        port_str = local_addr.rsplit(":", 1)[-1]
                        ports.add(int(port_str))
                    except (ValueError, IndexError):
                        pass
        return ports

    async def _get_ports_for_pid_windows(self, pid: int) -> Set[int]:
        """Get listening ports for a PID on Windows."""
        proc = await asyncio.create_subprocess_exec(
            "netstat", "-ano", "-p", "TCP",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await proc.communicate()
        ports: Set[int] = set()
        for line in decode_process_output(stdout).splitlines():
            if "LISTENING" in line and str(pid) in line:
                parts = line.split()
                if len(parts) >= 5 and parts[-1] == str(pid):
                    local_addr = parts[1]
                    try:
                        port_str = local_addr.rsplit(":", 1)[-1]
                        ports.add(int(port_str))
                    except (ValueError, IndexError):
                        pass
        return ports
