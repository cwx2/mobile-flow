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
    - None (pure data structure, no external imports beyond stdlib + loguru).

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

Lifecycle:
    Created by WebSocketServer._create_client_scope().
    Survives scope suspension (grace period).
    Destroyed when the scope is disposed.
"""

from __future__ import annotations

from collections import deque
from typing import Optional

from loguru import logger


class StreamReplay:
    """Per-client ring buffer for streaming chunk replay.

    Attributes:
        _buffer: Fixed-size deque of (seq, message_dict) tuples.
        _seq: Monotonically increasing sequence counter for the current turn.
        _active: True while an AI turn is in progress.
        _done_payload: Cached chat.done payload if the turn finished
            while the client was disconnected.
        _cli_name: CLI name for the current turn (for logging).
    """

    def __init__(self, max_chunks: int = 500):
        self._buffer: deque[tuple[int, dict]] = deque(maxlen=max_chunks)
        self._seq: int = 0
        self._active: bool = False
        self._done_payload: Optional[dict] = None
        self._cli_name: str = ""

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
        logger.debug(
            f"StreamReplay: turn 结束: cli={self._cli_name}, "
            f"buffered={len(self._buffer)} chunks"
        )

    def get_replay(self, after_seq: int = 0) -> list[dict]:
        """Get all buffered chunks after the given sequence number.

        Args:
            after_seq: Only return chunks with seq > after_seq.
                Use 0 to get all buffered chunks.

        Returns:
            List of message dicts in chronological order.
        """
        return [msg for seq, msg in self._buffer if seq > after_seq]

    def clear(self) -> None:
        """Clear the buffer and reset state.

        Called when the client starts a new session or the scope
        is disposed.
        """
        self._buffer.clear()
        self._seq = 0
        self._active = False
        self._done_payload = None

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
