"""Scope lifecycle state machine — validated transitions for client scopes.

Module: core/scope_state.py
Responsibility:
    Models the lifecycle of a client scope as an explicit state machine
    with three states (ACTIVE, SUSPENDED, DISPOSED) and validated
    transitions between them. Prevents illegal state changes (e.g.,
    resurrecting a disposed scope) by raising InvalidStateTransition.

    The state machine enforces:
        ACTIVE → SUSPENDED (client disconnects, grace timer starts)
        SUSPENDED → ACTIVE (client reconnects within grace period)
        SUSPENDED → DISPOSED (grace timer expires or capacity eviction)
        ACTIVE → DISPOSED (explicit dispose, e.g., Agent shutdown)

    DISPOSED is a terminal state — no transitions out of it are possible.

Used by:
    - core/scope_manager.py (orchestrates lifecycle transitions)
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from enum import Enum
from typing import TYPE_CHECKING

from loguru import logger

if TYPE_CHECKING:
    from .client_scope import ClientScope


class ScopeLifecycleState(str, Enum):
    """Explicit lifecycle states for a client scope.

    State transitions:
        ACTIVE → SUSPENDED (client disconnects, grace timer starts)
        SUSPENDED → ACTIVE (client reconnects within grace period)
        SUSPENDED → DISPOSED (grace timer expires or capacity eviction)
        ACTIVE → DISPOSED (explicit dispose, e.g., Agent shutdown)
    """

    ACTIVE = "active"
    SUSPENDED = "suspended"
    DISPOSED = "disposed"


# Valid transitions as a set of (from_state, to_state) tuples.
# Any transition not in this set is illegal and will raise InvalidStateTransition.
VALID_TRANSITIONS: set[tuple[ScopeLifecycleState, ScopeLifecycleState]] = {
    (ScopeLifecycleState.ACTIVE, ScopeLifecycleState.SUSPENDED),
    (ScopeLifecycleState.SUSPENDED, ScopeLifecycleState.ACTIVE),
    (ScopeLifecycleState.SUSPENDED, ScopeLifecycleState.DISPOSED),
    (ScopeLifecycleState.ACTIVE, ScopeLifecycleState.DISPOSED),
}


class InvalidStateTransition(Exception):
    """Raised when an illegal scope state transition is attempted.

    Attributes:
        from_state: The current state before the attempted transition.
        to_state: The target state that was rejected.
        identity_id: The stable identity ID of the scope (for diagnostics).
    """

    def __init__(
        self,
        from_state: ScopeLifecycleState,
        to_state: ScopeLifecycleState,
        identity_id: str = "",
    ) -> None:
        self.from_state = from_state
        self.to_state = to_state
        self.identity_id = identity_id
        super().__init__(
            f"非法状态转换: {from_state.value} → {to_state.value}"
            f"{f', identity={identity_id[:16]}' if identity_id else ''}"
        )


@dataclass
class ScopeStateEntry:
    """Tracks the lifecycle state of a single scope.

    Binds a ClientScope instance to its lifecycle state, stable identity,
    and grace timer. The transition() method enforces the state machine
    rules defined in VALID_TRANSITIONS.

    Attributes:
        state: Current lifecycle state.
        identity_id: The stable identity ID this scope is bound to.
        scope: The ClientScope instance managing resources.
        suspended_at: Timestamp (time.time()) when scope entered SUSPENDED.
            Used for LRU eviction ordering. None if not suspended.
        grace_timer: The asyncio.Task running the grace period countdown.
            None if no timer is active.
    """

    state: ScopeLifecycleState
    identity_id: str
    scope: ClientScope
    suspended_at: float | None = None
    grace_timer: asyncio.Task | None = field(default=None, repr=False)

    def transition(self, new_state: ScopeLifecycleState) -> None:
        """Validate and execute a state transition.

        Checks that (current_state, new_state) is in VALID_TRANSITIONS.
        If valid, updates self.state and logs the transition at INFO level.
        If invalid, raises InvalidStateTransition without modifying state.

        Args:
            new_state: Target lifecycle state.

        Raises:
            InvalidStateTransition: If the transition is not in
                VALID_TRANSITIONS (e.g., DISPOSED → ACTIVE).
        """
        if (self.state, new_state) not in VALID_TRANSITIONS:
            logger.error(
                f"[ScopeState] 非法状态转换: "
                f"{self.state.value} → {new_state.value}, "
                f"identity={self.identity_id[:16]}"
            )
            raise InvalidStateTransition(
                from_state=self.state,
                to_state=new_state,
                identity_id=self.identity_id,
            )

        old_state = self.state
        self.state = new_state
        logger.info(
            f"[ScopeState] 状态转换: {old_state.value} → {new_state.value}, "
            f"identity={self.identity_id[:16]}"
        )
