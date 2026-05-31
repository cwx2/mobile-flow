"""Diff domain payload models for the MobileFlow WebSocket protocol.

Defines typed Pydantic models for the three diff-related message types:
  - diff.preview  (DIFF_PREVIEW)  — proposed diff for review
  - diff.apply    (DIFF_APPLY)    — accept proposed diff
  - diff.reject   (DIFF_REJECT)   — reject proposed diff

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Optional

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


# ── Notification payloads (Agent -> App) ──


class DiffPreviewPayload(PayloadBase):
    """Payload for ``diff.preview`` — proposed diff for review.

    Pushed by the Agent when the AI CLI proposes a file modification.
    The App displays a diff view and lets the user accept or reject.

    Attributes:
        file_path: Relative path of the file being modified.
        old_content: Original file content before modification (None for new files).
        new_content: Proposed file content after modification.
    """

    file_path: str
    old_content: Optional[str] = None
    new_content: str


# ── Command payloads (App -> Agent) ──


class DiffApplyPayload(PayloadBase):
    """Payload for ``diff.apply`` — accept proposed diff.

    Sent by the App when the user accepts a proposed file modification.
    The Agent updates the snapshot baselines to reflect the accepted state.

    Attributes:
        file_path: Relative path of the file whose diff is accepted.
        new_content: The accepted file content.
    """

    file_path: str
    new_content: str


class DiffRejectPayload(PayloadBase):
    """Payload for ``diff.reject`` — reject proposed diff.

    Sent by the App when the user rejects a proposed file modification.
    The Agent rolls back the file to its pre-edit baseline.

    Attributes:
        file_path: Relative path of the file whose diff is rejected.
    """

    file_path: str


# ── Registry wiring ──
# Register all diff payload models so Message.typed_payload() and
# get_payload_class() can resolve them by MessageType.

register_payload(MessageType.DIFF_PREVIEW, DiffPreviewPayload)
register_payload(MessageType.DIFF_APPLY, DiffApplyPayload)
register_payload(MessageType.DIFF_REJECT, DiffRejectPayload)
