"""Terminal session lifecycle manager.

Manages the creation, lookup, and teardown of multiple concurrent terminal
sessions identified by session ID.
"""

from __future__ import annotations

import asyncio
from typing import Optional

from loguru import logger

from .session import TerminalSession


class TerminalManager:
    """Manages multiple terminal sessions keyed by session ID.

    Attributes:
        _sessions: Mapping of session_id to active TerminalSession.
        _shutdown_timeout: Per-session shutdown timeout in seconds.
    """

    def __init__(self, shutdown_timeout: float = 5):
        self._sessions: dict[str, TerminalSession] = {}
        self._shutdown_timeout = shutdown_timeout

    async def create_session(
        self, session_id: str, cli_command: str, work_dir: str,
        cols: int = 80, rows: int = 24, execution_env: str = "native",
    ) -> TerminalSession:
        """Create a new terminal session, stopping any existing one with the same ID.

        Args:
            session_id: Unique identifier for the session.
            cli_command: CLI command to execute in the terminal.
            work_dir: Working directory for the terminal process.
            cols: Initial terminal width in columns.
            rows: Initial terminal height in rows.
            execution_env: Execution environment (``"native"`` or ``"wsl"``).

        Returns:
            The newly created TerminalSession.
        """
        if session_id in self._sessions:
            await self._sessions[session_id].stop()
        session = TerminalSession(session_id)
        await session.start(cli_command, work_dir, cols, rows, execution_env)
        self._sessions[session_id] = session
        logger.info(f"终端会话创建: id={session_id[:8]}..., cmd={cli_command}, env={execution_env}")
        return session

    def get_session(self, session_id: str) -> Optional[TerminalSession]:
        """Look up a terminal session by ID.

        Args:
            session_id: Session identifier.

        Returns:
            The TerminalSession, or None if not found.
        """
        return self._sessions.get(session_id)

    async def stop_session(self, session_id: str):
        """Stop and remove a terminal session with timeout protection.

        If the session doesn't stop within the configured timeout, logs a
        warning and continues. Never blocks the caller indefinitely.

        Args:
            session_id: Session identifier.
        """
        session = self._sessions.pop(session_id, None)
        if session:
            try:
                await asyncio.wait_for(session.stop(), timeout=self._shutdown_timeout)
            except asyncio.TimeoutError:
                logger.warning(f"终端会话停止超时: id={session_id[:8]}...")
            except Exception as e:
                logger.warning(f"终端会话停止出错: id={session_id[:8]}..., error={e}")
            logger.debug(f"终端会话停止: id={session_id[:8]}...")

    async def stop_all(self):
        """Stop all active terminal sessions with per-session timeout.

        Each session gets the configured timeout to stop gracefully. Sessions
        that don't stop in time are logged and skipped — the overall shutdown
        is never blocked by a single hung terminal.
        """
        count = len(self._sessions)
        if count == 0:
            return
        logger.info(f"停止所有终端会话: {count} 个")
        for sid, session in list(self._sessions.items()):
            try:
                await asyncio.wait_for(session.stop(), timeout=self._shutdown_timeout)
            except asyncio.TimeoutError:
                logger.warning(f"终端会话停止超时: id={sid[:8]}...")
            except Exception as e:
                logger.warning(f"终端会话停止出错: id={sid[:8]}..., error={e}")
        self._sessions.clear()
        logger.info(f"所有终端会话已停止")
