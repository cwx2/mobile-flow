"""Session store for persisting ACP session metadata and history.

In ACP mode the CLI does not maintain a session list, so the client (Agent)
is responsible for tracking sessions.  Data is persisted to
``~/.mobileflow/sessions.json``.

History persistence (for resume-only CLIs) is stored per-session at
``~/.mobileflow/history/{session_id}.json``.

Responsibilities:
    - Record each session created via ``session/new``.
    - Filter sessions by working directory.
    - Update session preview (first user message) and message count.
    - Provide ``session_id`` for ``session/load`` restoration.
    - Persist/load/remove per-session message history for resume-only CLIs.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Optional

from loguru import logger

from ..utils.json_file import load_json_file, save_json_file


class SessionRecord:
    """A single session metadata record.

    Attributes:
        session_id: Unique ACP session identifier.
        cli_name: Name of the CLI adapter that owns this session.
        cwd: Working directory the session was created in.
        preview: Short preview text (first user message, truncated).
        created_at: Creation timestamp in milliseconds since epoch.
        updated_at: Last-update timestamp in milliseconds since epoch.
        message_count: Total number of messages exchanged in this session.
    """

    def __init__(
        self,
        session_id: str,
        cli_name: str,
        cwd: str,
        preview: str = "",
        created_at: int = 0,
        updated_at: int = 0,
        message_count: int = 0,
    ):
        self.session_id = session_id
        self.cli_name = cli_name
        self.cwd = cwd
        self.preview = preview
        self.created_at = created_at or int(time.time() * 1000)
        self.updated_at = updated_at or self.created_at
        self.message_count = message_count

    def to_dict(self) -> dict:
        """Serialise the record to a JSON-compatible dict.

        Returns:
            Dict with keys matching the on-disk schema.
        """
        return {
            "id": self.session_id,
            "cli": self.cli_name,
            "cwd": self.cwd,
            "preview": self.preview,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "message_count": self.message_count,
        }

    @staticmethod
    def from_dict(d: dict) -> SessionRecord:
        """Deserialise a record from a JSON-compatible dict.

        Args:
            d: Dict with the on-disk schema keys.

        Returns:
            A new SessionRecord instance.
        """
        return SessionRecord(
            session_id=d.get("id", ""),
            cli_name=d.get("cli", ""),
            cwd=d.get("cwd", ""),
            preview=d.get("preview", ""),
            created_at=d.get("created_at", 0),
            updated_at=d.get("updated_at", 0),
            message_count=d.get("message_count", 0),
        )


class SessionStore:
    """Persistent session list backed by ``~/.mobileflow/sessions.json``.

    Also manages per-session history files under ``~/.mobileflow/history/``
    for resume-only CLIs (those that support resume but not load).

    Attributes:
        _file: Path to the JSON storage file.
        _sessions: In-memory list of session records.
        _history_dir: Directory for per-session history JSON files.
        _max_history_messages: Cap on persisted messages per session.
    """

    def __init__(self, data_dir: Path, max_history_messages: int = 200):
        self._file = data_dir / "sessions.json"
        self._history_dir = data_dir / "history"
        self._max_history_messages = max_history_messages
        self._sessions: list[SessionRecord] = []
        self._load()

    def _load(self):
        """Load session records from the JSON file."""
        data = load_json_file(self._file, default={})
        if isinstance(data, dict):
            try:
                self._sessions = [SessionRecord.from_dict(d) for d in data.get("sessions", [])]
                logger.debug(f"加载了 {len(self._sessions)} 个会话记录")
            except Exception as e:
                logger.warning(f"加载会话记录失败: {e}")
                self._sessions = []
        else:
            self._sessions = []

    def _save(self):
        """Persist the current session list to the JSON file."""
        try:
            self._file.parent.mkdir(parents=True, exist_ok=True)
            data = {"sessions": [s.to_dict() for s in self._sessions]}
            self._file.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception as e:
            logger.error(f"保存会话记录失败: {e}")

    def add(self, session_id: str, cli_name: str, cwd: str, preview: str = "") -> SessionRecord:
        """Record a newly created session.

        The list is capped at 100 entries (oldest are dropped).

        Args:
            session_id: Unique ACP session identifier.
            cli_name: Name of the CLI adapter.
            cwd: Working directory for the session.
            preview: Optional preview text.

        Returns:
            The newly created SessionRecord.
        """
        record = SessionRecord(
            session_id=session_id,
            cli_name=cli_name,
            cwd=cwd,
            preview=preview,
        )
        self._sessions.insert(0, record)
        # Cap at 100 records
        if len(self._sessions) > 100:
            self._sessions = self._sessions[:100]
        self._save()
        logger.debug(f"记录新会话: {session_id[:16]}... cli={cli_name} cwd={cwd[-30:]}")
        return record

    def update_preview(self, session_id: str, preview: str, message_count: int = 0):
        """Update the preview text and increment the message count.

        Only sets the preview if it has not been set yet (first user message).

        Args:
            session_id: Session to update.
            preview: Preview text (truncated to 100 chars).
            message_count: Unused — the internal counter auto-increments.
        """
        for s in self._sessions:
            if s.session_id == session_id:
                if not s.preview:
                    s.preview = preview[:100]
                s.updated_at = int(time.time() * 1000)
                s.message_count += 1  # Auto-increment on each message
                self._save()
                return

    def list_by_cwd(self, cwd: str, cli_name: str = "") -> list[dict]:
        """Return sessions filtered by working directory.

        Args:
            cwd: Working directory to filter on.
            cli_name: Optional CLI name filter.

        Returns:
            List of session dicts matching the criteria.
        """
        results = []
        for s in self._sessions:
            if s.cwd == cwd:
                if cli_name and s.cli_name != cli_name:
                    continue
                results.append(s.to_dict())
        return results

    def get_latest(self, cwd: str, cli_name: str = "") -> Optional[str]:
        """Return the most recent session_id for the given working directory.

        Args:
            cwd: Working directory to search.
            cli_name: Optional CLI name filter.

        Returns:
            The session_id string, or None if no matching session exists.
        """
        for s in self._sessions:
            if s.cwd == cwd:
                if cli_name and s.cli_name != cli_name:
                    continue
                logger.debug(f"获取最新会话: cwd={cwd[-30:]}, session={s.session_id[:16]}...")
                return s.session_id
        return None

    def remove(self, session_id: str):
        """Delete a session record by its identifier.

        Args:
            session_id: The session to remove.
        """
        self._sessions = [s for s in self._sessions if s.session_id != session_id]
        self._save()
        logger.debug(f"删除会话记录: {session_id[:16]}...")

    # ── History persistence (for resume-only CLIs) ──

    def _history_path(self, session_id: str) -> Path:
        """Return the file path for a session's history JSON.

        Args:
            session_id: The session identifier.

        Returns:
            Path to ``~/.mobileflow/history/{session_id}.json``.
        """
        return self._history_dir / f"{session_id}.json"

    def save_history(self, session_id: str, messages: list[dict]) -> None:
        """Persist message history for a session.

        Caps the message list at ``max_history_messages`` (keeps most recent).
        Creates the history directory if it doesn't exist.

        File format:
            {"session_id": "...", "updated_at": <ms_timestamp>, "messages": [...]}

        Args:
            session_id: The session to save history for.
            messages: List of message dicts (same format as chat.history payload).

        Note:
            Never raises — logs errors and continues on I/O failure.
        """
        logger.debug(
            f"save_history: session_id={session_id[:16]}..., "
            f"messages={len(messages)}, cap={self._max_history_messages}"
        )

        # Enforce cap: keep most recent messages
        if len(messages) > self._max_history_messages:
            messages = messages[-self._max_history_messages:]

        data = {
            "session_id": session_id,
            "updated_at": int(time.time() * 1000),
            "messages": messages,
        }

        path = self._history_path(session_id)
        success = save_json_file(path, data)
        if success:
            logger.debug(f"历史记录已保存: session={session_id[:16]}..., count={len(messages)}")
        else:
            logger.error(f"历史记录保存失败: session={session_id[:16]}...")

    def load_history(self, session_id: str) -> list[dict]:
        """Load persisted history for a session.

        Returns an empty list if the file doesn't exist or is corrupted.
        On corruption (file exists but cannot be parsed), logs a warning
        and deletes the corrupted file to prevent repeated failures.

        Args:
            session_id: The session to load history for.

        Returns:
            List of message dicts, or [] if not found/corrupted.
        """
        logger.debug(f"load_history: session_id={session_id[:16]}...")

        path = self._history_path(session_id)
        if not path.is_file():
            logger.debug(f"历史记录文件不存在: session={session_id[:16]}...")
            return []

        data = load_json_file(path, default=None, silent=True)

        # Validate structure: must be a dict with a "messages" list
        if isinstance(data, dict) and isinstance(data.get("messages"), list):
            messages = data["messages"]
            logger.debug(f"历史记录已加载: session={session_id[:16]}..., count={len(messages)}")
            return messages

        # File exists but is corrupted or has unexpected structure
        logger.warning(
            f"历史记录文件损坏，已删除: session={session_id[:16]}..., path={path}"
        )
        try:
            path.unlink()
        except OSError as e:
            logger.error(f"删除损坏历史文件失败: path={path}, error={e}")

        return []

    def remove_history(self, session_id: str) -> None:
        """Remove persisted history for a session.

        No-op if the file doesn't exist. Used when a session is closed
        or explicitly deleted.

        Args:
            session_id: The session whose history should be removed.
        """
        logger.debug(f"remove_history: session_id={session_id[:16]}...")

        path = self._history_path(session_id)
        if not path.is_file():
            return

        try:
            path.unlink()
            logger.debug(f"历史记录已删除: session={session_id[:16]}...")
        except OSError as e:
            logger.error(f"删除历史记录失败: session={session_id[:16]}..., error={e}")

    def append_message(self, session_id: str, message: dict) -> None:
        """Append a single message to persisted history.

        Loads existing history, appends the new message, enforces the
        configured cap, and saves back. If no history file exists yet,
        creates one with just this message.

        Called after each user/assistant message for resume-only CLIs.

        Args:
            session_id: The session to append to.
            message: A single message dict to append.
        """
        logger.debug(f"append_message: session_id={session_id[:16]}..., role={message.get('role', '?')}")

        messages = self.load_history(session_id)
        messages.append(message)
        self.save_history(session_id, messages)
