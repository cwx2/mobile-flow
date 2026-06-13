"""Stream replay buffer for disconnect recovery.

Module: server/
Responsibility:
    Buffer streaming chunks during an AI turn so that a reconnecting
    client can catch up on missed output.  Each client gets one
    StreamReplay instance, created alongside its ClientScope.

Called by:
    - server/websocket.py creates instances in _create_client_scope().
    - server/handlers/chat_handler.py pushes chunks and manages turn lifecycle.

Dependencies:
    - stdlib (collections, json, pathlib) + loguru.

Design decisions:
    - Uses collections.deque(maxlen=N) as a fixed-size ring buffer.
      When full, oldest chunks are silently dropped — the App can
      always fall back to chat.history for the complete conversation.
    - Sequence numbers are monotonically increasing per-turn so the
      App can request "everything after seq X" on reconnect.
    - The buffer stores serialised dicts (Message.model_dump()) rather
      than Message objects to avoid holding references to pydantic
      models longer than necessary.
    - finish_turn() caches the chat.done payload so a client that
      reconnects after the turn ended can receive both the buffered
      chunks and the done signal without requesting chat.history.
    - Optional disk persistence (JSONL append-only) allows recovery
      after Agent restart. Controlled by persist_path parameter.
      Reference: Vercel resumable-stream / LibreChat Resumable Streams.

Lifecycle:
    Created by WebSocketServer._create_client_scope().
    Survives scope suspension (grace period).
    Destroyed when the scope is disposed.
"""

from __future__ import annotations

import json
from collections import deque
from pathlib import Path
from typing import Optional

from loguru import logger


class StreamReplay:
    """Per-client ring buffer for streaming chunk replay.

    Supports optional disk persistence for Agent-restart recovery.
    When persist_path is set, every push() appends to a JSONL file
    so that a fresh Agent process can restore the buffer from disk.

    Attributes:
        _buffer: Fixed-size deque of (seq, message_dict) tuples.
        _seq: Monotonically increasing sequence counter for the current turn.
        _active: True while an AI turn is in progress.
        _done_payload: Cached chat.done payload if the turn finished
            while the client was disconnected.
        _cli_name: CLI name for the current turn (for logging).
        _persist_path: Optional directory for disk persistence.
    """

    def __init__(self, max_chunks: int = 500, persist_path: Optional[Path] = None):
        self._buffer: deque[tuple[int, dict]] = deque(maxlen=max_chunks)
        self._seq: int = 0
        self._active: bool = False
        self._done_payload: Optional[dict] = None
        self._cli_name: str = ""
        self._persist_path = persist_path

    def begin_turn(self, cli_name: str = "") -> None:
        """Mark the start of a new AI turn. Clears previous buffer.

        Args:
            cli_name: CLI adapter name for logging context.
        """
        self._buffer.clear()
        self._seq = 0
        self._active = True
        self._done_payload = None
        self._cli_name = cli_name
        # Clear previous turn's disk files
        if self._persist_path:
            self._clear_disk()
        logger.debug(f"StreamReplay: 开始新 turn: cli={cli_name}")

    def push(self, msg_dict: dict) -> int:
        """Buffer a chunk message and return its sequence number.

        Args:
            msg_dict: Serialised Message dict (from Message.model_dump()).

        Returns:
            The sequence number assigned to this chunk.
        """
        self._seq += 1
        self._buffer.append((self._seq, msg_dict))
        # Persist to disk (append-only JSONL, fast sequential write)
        if self._persist_path:
            self._append_to_disk(self._seq, msg_dict)
        return self._seq

    def finish_turn(self, done_payload: dict | None = None) -> None:
        """Mark the turn as complete.

        Caches the done payload so a reconnecting client can receive
        both the buffered chunks and the done signal.

        Args:
            done_payload: The chat.done message payload dict.
        """
        self._active = False
        self._done_payload = done_payload or {}
        # Persist turn metadata to disk
        if self._persist_path:
            self._write_turn_meta()
        logger.debug(
            f"StreamReplay: turn 结束: cli={self._cli_name}, "
            f"buffered={len(self._buffer)} chunks"
        )

    def get_replay(self, after_seq: int = 0) -> list[dict]:
        """Get all buffered chunks after the given sequence number.

        Tries memory buffer first. If memory is empty (e.g. after Agent
        restart with disk restore), falls back to reading from disk.

        Args:
            after_seq: Only return chunks with seq > after_seq.
                Use 0 to get all buffered chunks.

        Returns:
            List of message dicts in chronological order.
        """
        memory_result = [msg for seq, msg in self._buffer if seq > after_seq]
        if memory_result:
            return memory_result
        # Memory empty — try disk (Agent restart scenario)
        if self._persist_path:
            return self._read_disk_replay(after_seq)
        return []

    def clear(self) -> None:
        """Clear the buffer and reset state.

        Called when the client starts a new session or the scope
        is disposed.
        """
        self._buffer.clear()
        self._seq = 0
        self._active = False
        self._done_payload = None
        if self._persist_path:
            self._clear_disk()

    @property
    def is_active(self) -> bool:
        """True if an AI turn is currently in progress."""
        return self._active

    @property
    def is_finished(self) -> bool:
        """True if a turn completed while the client was disconnected.

        The App should request chat.replay to get the buffered chunks
        and the done signal, or fall back to chat.history.
        """
        return not self._active and self._done_payload is not None

    @property
    def done_payload(self) -> dict | None:
        """The cached chat.done payload, or None if turn is still active."""
        return self._done_payload

    @property
    def seq(self) -> int:
        """Current sequence number (last pushed chunk)."""
        return self._seq

    @property
    def buffered_count(self) -> int:
        """Number of chunks currently in the buffer."""
        return len(self._buffer)

    # ── Disk persistence (optional, for Agent-restart recovery) ──

    def _append_to_disk(self, seq: int, msg_dict: dict) -> None:
        """Append a single chunk to the JSONL replay file.

        Uses append mode for sequential writes — no locking needed since
        only one StreamReplay instance writes to each file. OS page cache
        absorbs the small writes (typically 200-500 bytes per chunk).
        """
        try:
            self._persist_path.mkdir(parents=True, exist_ok=True)
            replay_file = self._persist_path / "current_turn.jsonl"
            with open(replay_file, "a", encoding="utf-8") as f:
                f.write(json.dumps({"s": seq, "m": msg_dict}, ensure_ascii=False) + "\n")
        except Exception as e:
            # Disk write failure is non-fatal — memory buffer still works
            logger.warning(f"StreamReplay 磁盘写入失败（非致命）: {e}")

    def _write_turn_meta(self) -> None:
        """Write turn metadata (done state, seq, cli_name) for restart recovery."""
        try:
            self._persist_path.mkdir(parents=True, exist_ok=True)
            meta_file = self._persist_path / "turn_meta.json"
            meta_file.write_text(json.dumps({
                "done": True,
                "seq": self._seq,
                "cli": self._cli_name,
                "done_payload": self._done_payload,
            }, ensure_ascii=False), encoding="utf-8")
        except Exception as e:
            logger.warning(f"StreamReplay 元数据写入失败: {e}")

    def _read_disk_replay(self, after_seq: int) -> list[dict]:
        """Read replay chunks from disk JSONL file.

        Used when memory buffer is empty (e.g. after Agent restart
        with restore_from_disk). Returns chunks with seq > after_seq.
        """
        replay_file = self._persist_path / "current_turn.jsonl"
        if not replay_file.exists():
            return []
        chunks = []
        try:
            with open(replay_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    entry = json.loads(line)
                    if entry["s"] > after_seq:
                        chunks.append(entry["m"])
        except Exception as e:
            logger.warning(f"StreamReplay 磁盘读取失败: {e}")
        return chunks

    def _clear_disk(self) -> None:
        """Remove disk replay files for this instance."""
        if not self._persist_path:
            return
        try:
            replay_file = self._persist_path / "current_turn.jsonl"
            meta_file = self._persist_path / "turn_meta.json"
            replay_file.unlink(missing_ok=True)
            meta_file.unlink(missing_ok=True)
        except Exception as e:
            logger.warning(f"StreamReplay 磁盘清理失败: {e}")

    # ── Factory: restore from disk after Agent restart ──

    @classmethod
    def restore_from_disk(cls, persist_path: Path, max_chunks: int = 500) -> "StreamReplay":
        """Restore a StreamReplay instance from disk after Agent restart.

        Reads turn_meta.json for state flags and current_turn.jsonl for
        buffered chunks. The restored instance can immediately serve
        get_replay() requests from a reconnecting client.

        Args:
            persist_path: Directory containing current_turn.jsonl and
                turn_meta.json files from a previous Agent run.
            max_chunks: Ring buffer capacity (should match original).

        Returns:
            A StreamReplay instance with state restored from disk.
            If files are missing or corrupted, returns a clean instance.
        """
        instance = cls(max_chunks=max_chunks, persist_path=persist_path)
        meta_file = persist_path / "turn_meta.json"
        replay_file = persist_path / "current_turn.jsonl"

        # Restore metadata
        if meta_file.exists():
            try:
                meta = json.loads(meta_file.read_text(encoding="utf-8"))
                instance._cli_name = meta.get("cli", "")
                instance._seq = meta.get("seq", 0)
                instance._done_payload = meta.get("done_payload")
                instance._active = not meta.get("done", False)
                logger.info(
                    f"StreamReplay 从磁盘恢复元数据: "
                    f"cli={instance._cli_name}, seq={instance._seq}, "
                    f"done={not instance._active}"
                )
            except Exception as e:
                logger.warning(f"StreamReplay 元数据恢复失败: {e}")

        # Restore buffer from JSONL
        if replay_file.exists():
            try:
                with open(replay_file, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        entry = json.loads(line)
                        instance._buffer.append((entry["s"], entry["m"]))
                logger.info(
                    f"StreamReplay 从磁盘恢复 {len(instance._buffer)} chunks"
                )
            except Exception as e:
                logger.warning(f"StreamReplay JSONL 恢复失败: {e}")

        return instance
