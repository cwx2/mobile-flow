"""Error types and codes for App-Agent WebSocket protocol.

Defines application-level error codes sent in error payloads and
the PayloadValidationError raised when a raw payload dict fails
validation against its typed Pydantic model.

Error codes are distinct from JSON-RPC 2.0 standard codes (-32xxx)
used by the ACP layer between Agent and CLI processes.

Code ranges:
    1xxx — General protocol errors (malformed messages, timeouts)
    2xxx — Authentication errors (pairing, session tokens)
    3xxx — CLI / Agent errors (not found, crashed, busy)
    4xxx — File system errors (not found, permission denied)
    5xxx — Security errors (blocked operations, confirmation required)
"""

from __future__ import annotations

from enum import IntEnum
from typing import Any

from .types import MessageType


class ErrorCode(IntEnum):
    """Application-level error codes for App-Agent communication."""

    # ── General (1xxx) ──
    UNKNOWN = 1000
    INVALID_MESSAGE = 1001
    TIMEOUT = 1002

    # ── Authentication (2xxx) ──
    AUTH_FAILED = 2001
    AUTH_EXPIRED = 2002
    AUTH_INVALID_TOKEN = 2003

    # ── CLI / Agent (3xxx) ──
    CLI_NOT_FOUND = 3001
    CLI_START_FAILED = 3002
    CLI_CRASHED = 3003
    CLI_BUSY = 3004

    # ── File System (4xxx) ──
    FILE_NOT_FOUND = 4001
    FILE_READ_ERROR = 4002
    FILE_WRITE_ERROR = 4003
    FILE_PERMISSION_DENIED = 4004

    # ── Security (5xxx) ──
    SECURITY_BLOCKED = 5001
    SECURITY_CONFIRM_REQUIRED = 5002


class PayloadValidationError(Exception):
    """Raised when a payload dict fails validation against its Pydantic model.

    Wraps the raw Pydantic validation errors with protocol context
    (which MessageType was being deserialized) so that handler-level
    error logging and error responses can include actionable details.

    The formatted message includes the MessageType wire value and up to
    3 failing field names, keeping log lines concise while still useful
    for debugging.

    Attributes:
        msg_type: The MessageType that was being deserialized when
            validation failed.
        errors: Raw Pydantic validation error dicts, each containing
            ``loc``, ``msg``, and ``type`` keys.
    """

    def __init__(self, msg_type: MessageType, errors: list[dict[str, Any]]) -> None:
        self.msg_type = msg_type
        self.errors = errors
        # Extract the deepest field name from each error's location tuple,
        # limited to the first 3 to keep the message readable.
        fields = ", ".join(
            str(e.get("loc", ("?",))[-1]) for e in errors[:3]
        )
        super().__init__(f"{msg_type.value}: validation failed on [{fields}]")
