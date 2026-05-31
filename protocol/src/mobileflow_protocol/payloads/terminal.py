"""Terminal domain payload models for the MobileFlow WebSocket protocol.

Defines typed Pydantic models for the six terminal-related message types:
  - terminal.start   (TERMINAL_START)   — start a PTY terminal session
  - terminal.started (TERMINAL_STARTED) — terminal session ready
  - terminal.input   (TERMINAL_INPUT)   — user keyboard input
  - terminal.output  (TERMINAL_OUTPUT)  — terminal output (base64)
  - terminal.resize  (TERMINAL_RESIZE)  — resize terminal dimensions
  - terminal.stop    (TERMINAL_STOP)    — stop terminal session

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


class TerminalStartPayload(PayloadBase):
    """Payload for ``terminal.start`` — start a PTY terminal session.

    Sent by the App to request a new interactive terminal session
    for the specified CLI adapter.

    Attributes:
        cli: CLI adapter name to launch in the terminal.
        cols: Terminal column count (default 80).
        rows: Terminal row count (default 24).
    """

    cli: str
    cols: int = 80
    rows: int = 24


class TerminalStartedPayload(PayloadBase):
    """Payload for ``terminal.started`` — terminal session ready.

    Sent by the Agent after the PTY session has been created and
    is ready to receive input.

    Attributes:
        terminal_id: Unique identifier for the terminal session.
        cli: CLI adapter name that was launched.
    """

    terminal_id: str = ""
    cli: str = ""


class TerminalInputPayload(PayloadBase):
    """Payload for ``terminal.input`` — user keyboard input.

    Sent by the App to forward raw keyboard input to the PTY.

    Attributes:
        data: Raw input string from the user.
    """

    data: str


class TerminalOutputPayload(PayloadBase):
    """Payload for ``terminal.output`` — terminal output data.

    Sent by the Agent to forward PTY output to the App.  The data
    field contains base64-encoded terminal output.

    Attributes:
        data: Base64-encoded terminal output.
        terminal_id: Session identifier (for multi-terminal support).
        source: Output source identifier (e.g. "stdout", "stderr").
        text: Plain text representation (optional, for accessibility).
    """

    data: str = ""
    terminal_id: str = ""
    source: str = ""
    text: str = ""


class TerminalResizePayload(PayloadBase):
    """Payload for ``terminal.resize`` — resize terminal dimensions.

    Sent by the App when the terminal view is resized.

    Attributes:
        cols: New column count.
        rows: New row count.
    """

    cols: int
    rows: int


class TerminalStopPayload(PayloadBase):
    """Payload for ``terminal.stop`` — stop terminal session.

    Sent by the App to terminate the active terminal session.
    No fields required.
    """

    pass


# ── Registry wiring ──

register_payload(MessageType.TERMINAL_START, TerminalStartPayload)
register_payload(MessageType.TERMINAL_STARTED, TerminalStartedPayload)
register_payload(MessageType.TERMINAL_INPUT, TerminalInputPayload)
register_payload(MessageType.TERMINAL_OUTPUT, TerminalOutputPayload)
register_payload(MessageType.TERMINAL_RESIZE, TerminalResizePayload)
register_payload(MessageType.TERMINAL_STOP, TerminalStopPayload)
