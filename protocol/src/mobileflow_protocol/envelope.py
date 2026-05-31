"""Message envelope for App-Agent WebSocket communication.

Every WebSocket frame carries exactly one JSON-serialized Message.
The envelope provides a stable outer structure (id, type, timestamp)
while the ``payload`` dict holds domain-specific data.

The ``payload`` field remains ``dict[str, Any]`` for backward
compatibility.  Two typed accessors enable opt-in type safety:

* ``typed_payload(model_class)`` — deserialize into a PayloadBase
  subclass, raising ``PayloadValidationError`` on failure.
* ``from_typed(type, payload, **kwargs)`` — class method that
  serializes a PayloadBase instance into the envelope dict.

Existing code that reads ``msg.payload`` as a raw dict is unaffected.
"""

from __future__ import annotations

import time
import uuid
from typing import Any, TypeVar

from pydantic import BaseModel, Field, ValidationError

from .errors import PayloadValidationError
from .payloads.base import PayloadBase
from .types import MessageType

T = TypeVar("T", bound=PayloadBase)


class Message(BaseModel):
    """WebSocket message envelope.

    Attributes:
        id: Unique message identifier (12-char UUID prefix).
            Used for request-response correlation and deduplication.
        type: Message type from the protocol enum.
        timestamp: Unix epoch milliseconds when the message was created.
        payload: Domain-specific data. Structure depends on ``type``.
    """

    id: str = Field(default_factory=lambda: str(uuid.uuid4())[:12])
    type: MessageType
    timestamp: int = Field(default_factory=lambda: int(time.time() * 1000))
    payload: dict[str, Any] = Field(default_factory=dict)

    def typed_payload(self, model_class: type[T]) -> T:
        """Deserialize the raw payload dict into a typed model.

        Provides opt-in type-safe access to the payload without
        changing the underlying ``dict[str, Any]`` storage.  Handlers
        call this at the top of their method body to get a validated,
        typed payload object.

        Args:
            model_class: A ``PayloadBase`` subclass to deserialize
                into.  Must match the expected payload schema for
                ``self.type``.

        Returns:
            A validated instance of *model_class* populated from
            ``self.payload``.

        Raises:
            PayloadValidationError: When the raw payload dict fails
                Pydantic validation against *model_class*.  The error
                includes ``self.type`` for handler-level logging.
        """
        try:
            return model_class.from_payload_dict(self.payload)
        except ValidationError as exc:
            raise PayloadValidationError(
                msg_type=self.type,
                errors=exc.errors(),
            ) from exc

    @classmethod
    def from_typed(
        cls,
        type: MessageType,
        payload: PayloadBase,
        **kwargs: Any,
    ) -> Message:
        """Create a Message from a typed payload model.

        Convenience factory that serializes the payload model to a
        plain dict via ``to_payload_dict()`` and passes it into the
        standard envelope constructor.  This keeps the wire format
        identical to hand-built dicts while giving callers compile-time
        field checking.

        Args:
            type: The message type for this envelope.
            payload: A ``PayloadBase`` instance whose fields will be
                serialized into ``Message.payload``.
            **kwargs: Additional envelope fields forwarded to the
                ``Message`` constructor (e.g. ``id``).

        Returns:
            A new ``Message`` with ``payload`` set to the dict
            representation of the typed model.
        """
        return cls(type=type, payload=payload.to_payload_dict(), **kwargs)
