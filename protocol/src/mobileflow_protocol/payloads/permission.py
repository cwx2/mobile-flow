"""Permission domain payload models for the MobileFlow WebSocket protocol.

Defines typed Pydantic models for the three permission-related message types:
  - permission.request  (PERMISSION_REQUEST)  — Agent pushes permission request to App
  - permission.response (PERMISSION_RESPONSE) — App responds with user decision
  - permission.policy   (PERMISSION_POLICY)   — Agent pushes permission policy update

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Any, Optional

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


# ── Notification payloads (Agent -> App) ──


class PermissionRequestPayload(PayloadBase):
    """Payload for ``permission.request`` — Agent pushes permission request to App.

    Sent by the Agent when an ACP tool invocation requires user approval.
    The App displays the request and waits for the user to approve or
    reject.  The ``request_id`` correlates the request with its
    subsequent ``permission.response``.

    Attributes:
        request_id: Unique identifier for this permission request,
            used to correlate with the response.
        tool_name: Name of the tool requesting permission.
        tool_kind: Optional kind/category of the tool (e.g. "file",
            "shell").
        description: Optional human-readable description of what the
            tool intends to do.
        options: Available permission options for the user to choose
            from (e.g. allow_once, allow_session).
    """

    request_id: str
    tool_name: str
    tool_kind: Optional[str] = None
    description: Optional[str] = None
    options: list[dict[str, Any]] = []


class PermissionPolicyPayload(PayloadBase):
    """Payload for ``permission.policy`` — Agent pushes permission policy update.

    Sent by the Agent to inform the App of a change in the permission
    policy (e.g. switching from "ask" to "auto_approve").

    Attributes:
        policy: Policy configuration dict.  The structure is
            determined by the Agent's permission system.
    """

    policy: dict[str, Any] = {}


# ── Command payloads (App -> Agent) ──


class PermissionResponsePayload(PayloadBase):
    """Payload for ``permission.response`` — App responds with user decision.

    Sent by the App after the user approves or rejects a permission
    request.  The ``request_id`` must match the original
    ``permission.request`` so the Agent can resolve the pending Future.

    Attributes:
        request_id: Identifier of the permission request being
            responded to.
        approved: Whether the user approved the permission.
        option_id: Selected permission option (e.g. "allow_once",
            "allow_session").  Defaults to "allow_once".
    """

    request_id: str
    approved: bool
    option_id: str = "allow_once"


# ── Registry wiring ──
# Register all permission payload models so Message.typed_payload() and
# get_payload_class() can resolve them by MessageType.

register_payload(MessageType.PERMISSION_REQUEST, PermissionRequestPayload)
register_payload(MessageType.PERMISSION_RESPONSE, PermissionResponsePayload)
register_payload(MessageType.PERMISSION_POLICY, PermissionPolicyPayload)
