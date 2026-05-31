"""Base class for all typed protocol payload models.

Every WebSocket message payload in the MobileFlow protocol inherits
from PayloadBase, which provides standardized serialization and
deserialization methods.  These methods bridge the gap between typed
Pydantic models and the raw ``dict[str, Any]`` that the Message
envelope carries on the wire.

Usage::

    class AuthPairPayload(PayloadBase):
        token: str
        device_name: Optional[str] = None

    # Serialize for wire
    payload = AuthPairPayload(token="123456")
    raw = payload.to_payload_dict()   # {"token": "123456", "device_name": None}

    # Deserialize from wire
    restored = AuthPairPayload.from_payload_dict(raw)
    assert restored == payload
"""

from __future__ import annotations

from typing import Any, Type, TypeVar

from pydantic import BaseModel

T = TypeVar("T", bound="PayloadBase")


class PayloadBase(BaseModel):
    """Base class for all protocol payload models.

    Provides two core operations that every payload needs:

    * ``to_payload_dict()`` — serialize to a plain dict for the
      ``Message.payload`` field (wire format).
    * ``from_payload_dict()`` — deserialize a raw dict back into a
      validated model instance.

    Subclasses only need to declare their fields; serialization
    behaviour is inherited.
    """

    def to_payload_dict(self) -> dict[str, Any]:
        """Serialize this model to a dict suitable for Message.payload.

        Uses Pydantic's ``model_dump(mode="python")`` so that nested
        models are recursively converted to plain dicts and enums are
        kept as their Python values — matching the existing wire format
        that handlers already produce.

        Returns:
            A plain ``dict[str, Any]`` ready to be placed into
            ``Message.payload`` and JSON-serialized for the wire.
        """
        return self.model_dump(mode="python")

    @classmethod
    def from_payload_dict(cls: Type[T], data: dict[str, Any]) -> T:
        """Deserialize a raw payload dict into this model.

        Uses Pydantic's ``model_validate`` which performs full type
        coercion and validation against the model's field definitions.

        Args:
            data: Raw dict from ``Message.payload``, typically
                deserialized from an incoming WebSocket JSON frame.

        Returns:
            A validated instance of this payload model.

        Raises:
            pydantic.ValidationError: When *data* contains missing
                required fields, wrong types, or values that fail
                field-level validators.
        """
        return cls.model_validate(data)
