"""Session domain payload models for the MobileFlow WebSocket protocol.

Defines typed Pydantic models for the five session-related message types:
  - session.list        (SESSION_LIST)        — request available sessions
  - session.list.result (SESSION_LIST_RESULT)  — session list response
  - session.new         (SESSION_NEW)          — create a new session
  - session.switch      (SESSION_SWITCH)       — switch to an existing session
  - session.close       (SESSION_CLOSE)        — close (delete) a session

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


class SessionListPayload(PayloadBase):
    """Payload for ``session.list`` — request available sessions.

    Sent by the App to retrieve the list of ACP sessions for the
    given CLI adapter.

    Attributes:
        cli: Target CLI adapter name.
    """

    cli: str


class SessionNewPayload(PayloadBase):
    """Payload for ``session.new`` — create a new session.

    Sent by the App to create a fresh ACP session.  The Agent cancels
    any in-progress prompt before creating the new session to prevent
    stale stream chunks from leaking into the new context.

    Attributes:
        cli: Target CLI adapter name.
    """

    cli: str


class SessionSwitchPayload(PayloadBase):
    """Payload for ``session.switch`` — switch to an existing session.

    Sent by the App to switch the active ACP session.  The Agent
    cancels any in-progress prompt before switching to prevent stale
    stream chunks from leaking into the switched session's context.

    Attributes:
        cli: Target CLI adapter name.
        session_id: Identifier of the session to switch to.
    """

    cli: str
    session_id: str


class SessionClosePayload(PayloadBase):
    """Payload for ``session.close`` — close (delete) a session.

    Sent by the App to close a session.  The Agent calls ACP
    close_session if supported, then removes the session from
    SessionStore so it no longer appears in the session list.

    Attributes:
        cli: Target CLI adapter name.
        session_id: Identifier of the session to close.
    """

    cli: str
    session_id: str


class SessionDeletePayload(PayloadBase):
    """Payload for ``session.delete`` — permanently delete a session.

    Sent by the App to permanently remove a session from the Agent's
    session list.  Unlike ``session.close`` (which cancels ongoing work
    and frees active resources), ``session.delete`` removes a session
    from persistent storage so it no longer appears in ``session/list``.

    Per ACP spec, this requires ``sessionCapabilities.delete``.

    Attributes:
        cli: Target CLI adapter name.
        session_id: Identifier of the session to delete.
    """

    cli: str
    session_id: str


# ── Response payloads (Agent -> App) ──


class SessionListResultPayload(PayloadBase):
    """Payload for ``session.list.result`` — session list response.

    Returned by the Agent with the list of available sessions for
    the requested CLI adapter.

    Attributes:
        sessions: List of session dicts, each containing at minimum
            ``id`` (or ``session_id``), ``preview`` (or ``title``),
            and ``updated_at``.
        cli: CLI adapter name that produced the session list.
    """

    sessions: list[dict[str, Any]] = []
    cli: str = ""


# ── Registry wiring ──
# Register all session payload models so Message.typed_payload() and
# get_payload_class() can resolve them by MessageType.

register_payload(MessageType.SESSION_LIST, SessionListPayload)
register_payload(MessageType.SESSION_LIST_RESULT, SessionListResultPayload)
register_payload(MessageType.SESSION_NEW, SessionNewPayload)
register_payload(MessageType.SESSION_SWITCH, SessionSwitchPayload)
register_payload(MessageType.SESSION_CLOSE, SessionClosePayload)
register_payload(MessageType.SESSION_DELETE, SessionDeletePayload)
