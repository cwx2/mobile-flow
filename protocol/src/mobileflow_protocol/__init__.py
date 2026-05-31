"""MobileFlow App-Agent WebSocket protocol definitions.

Provides message types, envelope format, data models, and error codes
for communication between the Flutter mobile app and the Python
desktop agent.

Package name ``mobileflow_protocol`` is legacy — see dev-workflow.md §11.

Canonical import paths:
    from mobileflow_protocol.types import MessageType
    from mobileflow_protocol.envelope import Message
    from mobileflow_protocol.models import CLIInfo, StreamChunk, ...
    from mobileflow_protocol.errors import ErrorCode
    from mobileflow_protocol.version import PROTOCOL_VERSION
"""

from .version import PROTOCOL_VERSION
from .types import MessageType
from .envelope import Message
from .models import (
    AuthPairPayload,
    AuthResultPayload,
    ChatContext,
    ChatDonePayload,
    ChatSendPayload,
    ChatStreamPayload,
    CLIInfo,
    FileNode,
    FileReadPayload,
    FileReadResultPayload,
    FileSearchPayload,
    FileTreePayload,
    FileWritePayload,
    StreamChunk,
    StreamChunkType,
)
from .errors import ErrorCode, PayloadValidationError

__all__ = [
    # Version
    "PROTOCOL_VERSION",
    # Envelope
    "Message",
    # Types
    "MessageType",
    # Models — Chat
    "ChatContext",
    "ChatSendPayload",
    "ChatStreamPayload",
    "ChatDonePayload",
    "StreamChunk",
    "StreamChunkType",
    # Models — File
    "FileNode",
    "FileTreePayload",
    "FileReadPayload",
    "FileReadResultPayload",
    "FileWritePayload",
    "FileSearchPayload",
    # Models — CLI
    "CLIInfo",
    # Models — Auth
    "AuthPairPayload",
    "AuthResultPayload",
    # Errors
    "ErrorCode",
    "PayloadValidationError",
]
