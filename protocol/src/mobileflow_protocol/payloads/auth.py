"""Auth domain payload models for the MobileFlow WebSocket protocol.

Defines typed Pydantic models for the four auth-related message types:
  - auth.pair    (AUTH_PAIR)    — initial 6-digit pairing request
  - auth.connect (AUTH_CONNECT) — reconnect with an existing session token
  - auth.result  (AUTH_RESULT)  — authentication outcome sent to the App
  - auth.submit  (AUTH_SUBMIT)  — forward CLI auth credentials

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Optional

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


class AuthPairPayload(PayloadBase):
    """Payload for ``auth.pair`` — initial device pairing request.

    Sent by the App when the user enters the 6-digit pairing code
    displayed on the Agent.

    Attributes:
        token: 6-digit pairing code displayed on the Agent.
        device_name: Optional human-readable device name for logging.
    """

    token: str
    device_name: Optional[str] = None


class AuthConnectPayload(PayloadBase):
    """Payload for ``auth.connect`` — reconnect with session token.

    Sent by the App on subsequent connections to skip the pairing
    flow and re-establish an authenticated session.

    Attributes:
        session_token: Persistent token obtained from a prior auth.result.
        client_id: Optional client identifier hint from the App.
    """

    session_token: str
    client_id: Optional[str] = None


class AuthResultPayload(PayloadBase):
    """Payload for ``auth.result`` — authentication outcome.

    Sent by the Agent after processing auth.pair or auth.connect.
    On success, includes the session token and optional encryption
    secret.  On failure from auth.connect, ``should_repair`` tells
    the App to fall back to a fresh pairing flow.

    Attributes:
        success: Whether authentication succeeded.
        session_token: Persistent token for future reconnections.
        error: Error description on failure.
        secret: Base64-encoded shared secret for LAN encryption.
        resumed: Whether a suspended scope was resumed.
        cli_state: Current CLI state after resume (e.g. "ready").
        cli_name: Active CLI adapter name after resume.
        client_id: Server-assigned client identifier.
        should_repair: Hint for the App to re-initiate pairing.
    """

    success: bool
    session_token: Optional[str] = None
    error: Optional[str] = None
    secret: Optional[str] = None
    resumed: Optional[bool] = None
    cli_state: Optional[str] = None
    cli_name: Optional[str] = None
    client_id: Optional[str] = None
    should_repair: Optional[bool] = None


class AuthSubmitPayload(PayloadBase):
    """Payload for ``auth.submit`` — submit CLI auth credentials.

    Sent by the App when the user provides credentials for a CLI
    adapter's authentication prompt (e.g. API key, OAuth token).

    Attributes:
        cli: Target CLI adapter name.
        method_id: Authentication method identifier from the prompt.
        data: Key-value credential data for the auth method.
    """

    cli: str
    method_id: str
    data: dict[str, str]


# ── Registry wiring ──
# Register all auth payload models so Message.typed_payload() and
# get_payload_class() can resolve them by MessageType.

register_payload(MessageType.AUTH_PAIR, AuthPairPayload)
register_payload(MessageType.AUTH_CONNECT, AuthConnectPayload)
register_payload(MessageType.AUTH_RESULT, AuthResultPayload)
register_payload(MessageType.AUTH_SUBMIT, AuthSubmitPayload)
