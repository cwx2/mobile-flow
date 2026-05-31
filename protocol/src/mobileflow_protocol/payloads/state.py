"""State, heartbeat, confirm, and config payload models for the MobileFlow protocol.

Defines typed Pydantic models for the seven remaining message types
that don't belong to a larger domain:
  - status.ping      (STATUS_PING)      — heartbeat ping
  - status.pong      (STATUS_PONG)      — heartbeat pong
  - state.push       (STATE_PUSH)       — cached state update
  - confirm.request  (CONFIRM_REQUEST)  — confirm dangerous operation
  - confirm.response (CONFIRM_RESPONSE) — user confirmation
  - mode.set         (MODE_SET)         — switch ACP session mode
  - config.set       (CONFIG_SET)       — set ACP config option value

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Any

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


# ── Heartbeat ──


class StatusPingPayload(PayloadBase):
    """Payload for ``status.ping`` — heartbeat ping.

    Sent by the App to check connection liveness.
    No fields required.
    """

    pass


class StatusPongPayload(PayloadBase):
    """Payload for ``status.pong`` — heartbeat pong.

    Sent by the Agent in response to a ping.
    No fields required.
    """

    pass


# ── State push ──


class StatePushPayload(PayloadBase):
    """Payload for ``state.push`` — cached state update.

    Sent by the Agent when a cached state value changes (e.g.
    git status, git branches). The App uses the ``key`` to route
    the update to the correct state consumer.

    Attributes:
        key: State key identifying the data type (e.g. "git.status").
        data: The updated state data (structure depends on key).
    """

    key: str
    data: Any


# ── Confirm (legacy) ──


class ConfirmRequestPayload(PayloadBase):
    """Payload for ``confirm.request`` — confirm dangerous operation.

    Sent by the Agent when a CLI wants to perform a potentially
    destructive operation that requires user approval.

    Attributes:
        message: Human-readable description of the operation.
        confirm_id: Unique identifier to correlate request/response.
    """

    message: str
    confirm_id: str


class ConfirmResponsePayload(PayloadBase):
    """Payload for ``confirm.response`` — user confirmation.

    Sent by the App with the user's decision on a confirm request.

    Attributes:
        confirm_id: Identifier from the original confirm.request.
        confirmed: Whether the user approved the operation.
    """

    confirm_id: str
    confirmed: bool


# ── ACP session configuration ──


class ModeSetPayload(PayloadBase):
    """Payload for ``mode.set`` — switch ACP session mode.

    Sent by the App to change the active session mode (e.g.
    switching between different AI model configurations).

    Attributes:
        cli: Target CLI adapter name.
        mode_id: Identifier of the mode to activate.
    """

    cli: str
    mode_id: str


class ConfigSetPayload(PayloadBase):
    """Payload for ``config.set`` — set ACP config option value.

    Sent by the App to update a configuration option for the
    active ACP session (e.g. model selection, thinking mode).

    Attributes:
        cli: Target CLI adapter name.
        config_id: Configuration option identifier.
        value: New value for the option.
    """

    cli: str
    config_id: str
    value: Any


# ── Registry wiring ──

register_payload(MessageType.STATUS_PING, StatusPingPayload)
register_payload(MessageType.STATUS_PONG, StatusPongPayload)
register_payload(MessageType.STATE_PUSH, StatePushPayload)
register_payload(MessageType.CONFIRM_REQUEST, ConfirmRequestPayload)
register_payload(MessageType.CONFIRM_RESPONSE, ConfirmResponsePayload)
register_payload(MessageType.MODE_SET, ModeSetPayload)
register_payload(MessageType.CONFIG_SET, ConfigSetPayload)
