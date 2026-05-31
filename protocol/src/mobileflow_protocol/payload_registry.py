"""Payload registry mapping MessageType to typed Pydantic payload models.

Provides a central lookup from any MessageType enum value to its
corresponding PayloadBase subclass.  Domain modules (auth, chat, cli,
etc.) call ``register_payload()`` at import time to populate the
registry — this keeps the registry decoupled from individual domain
definitions and allows incremental migration (P0–P5).

The registry is consumed by:
  - ``Message.typed_payload()`` for automatic deserialization
  - Validation tooling and code generators that need the full
    MessageType → Model mapping

Usage::

    from mobileflow_protocol.payload_registry import (
        get_payload_class,
        register_payload,
    )

    # Domain module registers its models at import time
    register_payload(MessageType.AUTH_PAIR, AuthPairPayload)

    # Consumer looks up the model for a given message type
    model_cls = get_payload_class(MessageType.AUTH_PAIR)
"""

from __future__ import annotations

from .payloads.base import PayloadBase
from .types import MessageType

# Central mapping from MessageType to its typed payload model class.
# Initially empty — populated as domain modules are imported and call
# register_payload().
PAYLOAD_REGISTRY: dict[MessageType, type[PayloadBase]] = {}


def get_payload_class(msg_type: MessageType) -> type[PayloadBase] | None:
    """Look up the payload model class for a message type.

    Args:
        msg_type: The MessageType to look up.

    Returns:
        The PayloadBase subclass registered for *msg_type*, or ``None``
        if no model has been registered yet (i.e. the domain has not
        been migrated).
    """
    return PAYLOAD_REGISTRY.get(msg_type)


def register_payload(
    msg_type: MessageType, model_class: type[PayloadBase]
) -> None:
    """Register a payload model class for a message type.

    Called by domain modules (``payloads/auth.py``, ``payloads/cli.py``,
    etc.) at import time to wire up their models.  Duplicate
    registrations for the same *msg_type* are allowed only if the
    *model_class* is identical — this supports safe re-imports.

    Args:
        msg_type: The MessageType this model handles.
        model_class: A PayloadBase subclass that defines the payload
            schema for *msg_type*.

    Raises:
        ValueError: If *msg_type* is already registered to a
            **different** model class (indicates a configuration bug).
    """
    existing = PAYLOAD_REGISTRY.get(msg_type)
    if existing is not None and existing is not model_class:
        raise ValueError(
            f"{msg_type.value} is already registered to "
            f"{existing.__name__}, cannot re-register to "
            f"{model_class.__name__}"
        )
    PAYLOAD_REGISTRY[msg_type] = model_class
