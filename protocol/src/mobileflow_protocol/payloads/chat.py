"""Chat domain payload models for the MobileFlow WebSocket protocol.

Defines typed Pydantic models for the eleven chat-related message types:
  - chat.send              (CHAT_SEND)              — user message to AI
  - chat.stream            (CHAT_STREAM)            — streaming response chunk
  - chat.done              (CHAT_DONE)              — AI turn complete
  - chat.error             (CHAT_ERROR)             — prompt-level error
  - chat.cancel            (CHAT_CANCEL)            — cancel current AI operation
  - chat.history           (CHAT_HISTORY)           — request conversation history
  - chat.history.result    (CHAT_HISTORY_RESULT)    — history page response
  - chat.history.more      (CHAT_HISTORY_MORE)      — request next history page
  - chat.history.more.result (CHAT_HISTORY_MORE_RESULT) — next page response
  - chat.replay            (CHAT_REPLAY)            — request buffered chunks after reconnect
  - chat.replay.result     (CHAT_REPLAY_RESULT)     — replayed chunks batch

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Any, Optional

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


# ── Request payloads (App -> Agent) ──


class ChatSendPayload(PayloadBase):
    """Payload for ``chat.send`` — user sends a message to the AI.

    The App sends this when the user submits a chat message.  The Agent
    forwards it to the active CLI adapter and streams the response back
    via chat.stream / chat.done.

    Attributes:
        cli: Target CLI adapter name.
        message: User's text message.
        context: Optional editor context (active file, selection).
        session_id: Target session ID (uses current if omitted).
        attachments: Optional multimodal attachments (image, audio, resource).
        context_references: Optional structured context references resolved
            by the Agent before forwarding to the AI CLI.
    """

    cli: str
    message: str
    context: Optional[dict[str, Any]] = None
    session_id: Optional[str] = None
    attachments: Optional[list[dict[str, Any]]] = None
    context_references: Optional[list[dict[str, Any]]] = None


class ChatCancelPayload(PayloadBase):
    """Payload for ``chat.cancel`` — cancel the current AI operation.

    Triggers ACP session/cancel on the active CLI, resolves pending
    permission futures as cancelled, and sends chat.done to the App.

    Attributes:
        cli: CLI adapter name whose operation to cancel (empty = default).
    """

    cli: str = ""


class ChatHistoryPayload(PayloadBase):
    """Payload for ``chat.history`` — request conversation history.

    Returns the last page of messages plus total count and has_more flag.
    The App can request older pages via chat.history.more.

    Attributes:
        cli: Target CLI adapter name.
        session_id: Optional session ID (uses current if omitted).
    """

    cli: str
    session_id: Optional[str] = None


class ChatHistoryMorePayload(PayloadBase):
    """Payload for ``chat.history.more`` — request next page of history.

    Called when the App scrolls to the top and needs older messages.

    Attributes:
        cli: Target CLI adapter name.
        offset: Number of messages to skip from the start.
        limit: Maximum number of messages to return per page.
    """

    cli: str
    offset: int = 0
    limit: int = 20


class ChatReplayPayload(PayloadBase):
    """Payload for ``chat.replay`` — request buffered stream chunks.

    Sent by the App after reconnecting when the Agent indicates that
    a streaming turn is active or recently finished.

    Attributes:
        after_seq: Sequence number after which to replay chunks.
    """

    after_seq: int = 0


# ── Response / notification payloads (Agent -> App) ──


class ChatStreamPayload(PayloadBase):
    """Payload for ``chat.stream`` — one streaming chunk from the AI.

    Each chunk is a serialized StreamChunk dict pushed to the App
    during an active AI turn.

    Attributes:
        chunk: StreamChunk serialized to dict.
    """

    chunk: dict[str, Any]


class ChatDonePayload(PayloadBase):
    """Payload for ``chat.done`` — AI turn completed.

    Sent when the AI finishes generating a response or when the
    user cancels the current operation.

    Attributes:
        cancelled: True if the turn was cancelled by the user.
        tokens_used: Total tokens consumed in this turn.
        duration_ms: Wall-clock duration of the turn in milliseconds.
        session_id: Session that completed.
    """

    cancelled: Optional[bool] = None
    tokens_used: Optional[int] = None
    duration_ms: Optional[int] = None
    session_id: Optional[str] = None


class ChatErrorPayload(PayloadBase):
    """Payload for ``chat.error`` — prompt-level error.

    Sent when the AI CLI encounters an error during message processing.

    Attributes:
        error: Human-readable error description.
    """

    error: str


class ChatHistoryResultPayload(PayloadBase):
    """Payload for ``chat.history.result`` — history page response.

    Returns a page of conversation messages with pagination metadata.

    Attributes:
        messages: List of message dicts for the current page.
        total: Total number of messages in the conversation.
        has_more: Whether older messages are available.
        cli: CLI adapter name that produced the history.
        resumed: Whether the session was resumed (True = App should
            retain its local messages instead of replacing them).
    """

    messages: list[dict[str, Any]] = []
    total: int = 0
    has_more: bool = False
    cli: str = ""
    resumed: bool = False


class ChatHistoryMoreResultPayload(PayloadBase):
    """Payload for ``chat.history.more.result`` — next page response.

    Same structure as ChatHistoryResultPayload, returned for
    paginated history requests.

    Attributes:
        messages: List of message dicts for the requested page.
        total: Total number of messages in the conversation.
        has_more: Whether even older messages are available.
        cli: CLI adapter name that produced the history.
    """

    messages: list[dict[str, Any]] = []
    total: int = 0
    has_more: bool = False
    cli: str = ""


class ChatReplayResultPayload(PayloadBase):
    """Payload for ``chat.replay.result`` — replayed chunks batch.

    Sent as a single message containing all buffered chunks after
    the requested sequence number, plus streaming state metadata.

    Attributes:
        chunks: List of buffered chunk dicts to replay.
        streaming: Whether the AI turn is still actively streaming.
        seq: Current sequence number of the replay buffer.
        streaming_state: High-level streaming state label
            ("streaming" or "completed"), used by the App to decide
            whether to expect more chat.stream messages.
    """

    chunks: list[dict[str, Any]] = []
    streaming: bool = False
    seq: int = 0
    streaming_state: Optional[str] = None


# ── Registry wiring ──
# Register all chat payload models so Message.typed_payload() and
# get_payload_class() can resolve them by MessageType.

register_payload(MessageType.CHAT_SEND, ChatSendPayload)
register_payload(MessageType.CHAT_STREAM, ChatStreamPayload)
register_payload(MessageType.CHAT_DONE, ChatDonePayload)
register_payload(MessageType.CHAT_ERROR, ChatErrorPayload)
register_payload(MessageType.CHAT_CANCEL, ChatCancelPayload)
register_payload(MessageType.CHAT_HISTORY, ChatHistoryPayload)
register_payload(MessageType.CHAT_HISTORY_RESULT, ChatHistoryResultPayload)
register_payload(MessageType.CHAT_HISTORY_MORE, ChatHistoryMorePayload)
register_payload(MessageType.CHAT_HISTORY_MORE_RESULT, ChatHistoryMoreResultPayload)
register_payload(MessageType.CHAT_REPLAY, ChatReplayPayload)
register_payload(MessageType.CHAT_REPLAY_RESULT, ChatReplayResultPayload)
