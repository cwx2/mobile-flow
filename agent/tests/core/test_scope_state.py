"""Unit tests for core/scope_state.py — scope lifecycle state machine.

Tests cover:
    - All valid state transitions succeed
    - All invalid state transitions raise InvalidStateTransition
    - DISPOSED is a terminal state (no transitions out)
    - ScopeStateEntry dataclass fields and defaults
    - InvalidStateTransition exception attributes
"""

from __future__ import annotations

import asyncio
from unittest.mock import MagicMock

import pytest

from mobileflow_agent.core.scope_state import (
    VALID_TRANSITIONS,
    InvalidStateTransition,
    ScopeLifecycleState,
    ScopeStateEntry,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_scope():
    """Create a mock ClientScope for testing."""
    scope = MagicMock()
    scope.client_id = "test-client-abc123"
    scope.is_alive = True
    return scope


def _make_entry(
    state: ScopeLifecycleState, mock_scope, identity_id: str = "stable-id-12345678"
) -> ScopeStateEntry:
    """Helper to create a ScopeStateEntry with given state."""
    return ScopeStateEntry(
        state=state,
        identity_id=identity_id,
        scope=mock_scope,
    )


# ---------------------------------------------------------------------------
# Valid transitions
# ---------------------------------------------------------------------------


class TestValidTransitions:
    """Test that all valid transitions succeed without raising."""

    def test_active_to_suspended(self, mock_scope):
        entry = _make_entry(ScopeLifecycleState.ACTIVE, mock_scope)
        entry.transition(ScopeLifecycleState.SUSPENDED)
        assert entry.state == ScopeLifecycleState.SUSPENDED

    def test_suspended_to_active(self, mock_scope):
        entry = _make_entry(ScopeLifecycleState.SUSPENDED, mock_scope)
        entry.transition(ScopeLifecycleState.ACTIVE)
        assert entry.state == ScopeLifecycleState.ACTIVE

    def test_suspended_to_disposed(self, mock_scope):
        entry = _make_entry(ScopeLifecycleState.SUSPENDED, mock_scope)
        entry.transition(ScopeLifecycleState.DISPOSED)
        assert entry.state == ScopeLifecycleState.DISPOSED

    def test_active_to_disposed(self, mock_scope):
        entry = _make_entry(ScopeLifecycleState.ACTIVE, mock_scope)
        entry.transition(ScopeLifecycleState.DISPOSED)
        assert entry.state == ScopeLifecycleState.DISPOSED

    def test_all_valid_transitions_covered(self):
        """Verify the test covers all entries in VALID_TRANSITIONS."""
        expected = {
            (ScopeLifecycleState.ACTIVE, ScopeLifecycleState.SUSPENDED),
            (ScopeLifecycleState.SUSPENDED, ScopeLifecycleState.ACTIVE),
            (ScopeLifecycleState.SUSPENDED, ScopeLifecycleState.DISPOSED),
            (ScopeLifecycleState.ACTIVE, ScopeLifecycleState.DISPOSED),
        }
        assert VALID_TRANSITIONS == expected


# ---------------------------------------------------------------------------
# Invalid transitions
# ---------------------------------------------------------------------------


class TestInvalidTransitions:
    """Test that all invalid transitions raise InvalidStateTransition."""

    def test_disposed_to_active_raises(self, mock_scope):
        entry = _make_entry(ScopeLifecycleState.DISPOSED, mock_scope)
        with pytest.raises(InvalidStateTransition) as exc_info:
            entry.transition(ScopeLifecycleState.ACTIVE)
        assert exc_info.value.from_state == ScopeLifecycleState.DISPOSED
        assert exc_info.value.to_state == ScopeLifecycleState.ACTIVE

    def test_disposed_to_suspended_raises(self, mock_scope):
        entry = _make_entry(ScopeLifecycleState.DISPOSED, mock_scope)
        with pytest.raises(InvalidStateTransition):
            entry.transition(ScopeLifecycleState.SUSPENDED)

    def test_disposed_to_disposed_raises(self, mock_scope):
        """DISPOSED is terminal — even self-transition is invalid."""
        entry = _make_entry(ScopeLifecycleState.DISPOSED, mock_scope)
        with pytest.raises(InvalidStateTransition):
            entry.transition(ScopeLifecycleState.DISPOSED)

    def test_active_to_active_raises(self, mock_scope):
        """Self-transition on ACTIVE is not in VALID_TRANSITIONS."""
        entry = _make_entry(ScopeLifecycleState.ACTIVE, mock_scope)
        with pytest.raises(InvalidStateTransition):
            entry.transition(ScopeLifecycleState.ACTIVE)

    def test_suspended_to_suspended_raises(self, mock_scope):
        """Self-transition on SUSPENDED is not in VALID_TRANSITIONS."""
        entry = _make_entry(ScopeLifecycleState.SUSPENDED, mock_scope)
        with pytest.raises(InvalidStateTransition):
            entry.transition(ScopeLifecycleState.SUSPENDED)

    def test_invalid_transition_preserves_state(self, mock_scope):
        """State must not change when transition is rejected."""
        entry = _make_entry(ScopeLifecycleState.DISPOSED, mock_scope)
        with pytest.raises(InvalidStateTransition):
            entry.transition(ScopeLifecycleState.ACTIVE)
        assert entry.state == ScopeLifecycleState.DISPOSED


# ---------------------------------------------------------------------------
# InvalidStateTransition exception
# ---------------------------------------------------------------------------


class TestInvalidStateTransitionException:
    """Test the custom exception attributes and message."""

    def test_exception_attributes(self):
        exc = InvalidStateTransition(
            from_state=ScopeLifecycleState.DISPOSED,
            to_state=ScopeLifecycleState.ACTIVE,
            identity_id="abc123def456",
        )
        assert exc.from_state == ScopeLifecycleState.DISPOSED
        assert exc.to_state == ScopeLifecycleState.ACTIVE
        assert exc.identity_id == "abc123def456"

    def test_exception_message_includes_states(self):
        exc = InvalidStateTransition(
            from_state=ScopeLifecycleState.DISPOSED,
            to_state=ScopeLifecycleState.ACTIVE,
            identity_id="test-id-1234567890",
        )
        msg = str(exc)
        assert "disposed" in msg
        assert "active" in msg

    def test_exception_message_without_identity(self):
        exc = InvalidStateTransition(
            from_state=ScopeLifecycleState.ACTIVE,
            to_state=ScopeLifecycleState.ACTIVE,
        )
        msg = str(exc)
        assert "active" in msg
        # No identity info when empty
        assert "identity=" not in msg


# ---------------------------------------------------------------------------
# ScopeStateEntry dataclass
# ---------------------------------------------------------------------------


class TestScopeStateEntry:
    """Test ScopeStateEntry field defaults and structure."""

    def test_default_fields(self, mock_scope):
        entry = ScopeStateEntry(
            state=ScopeLifecycleState.ACTIVE,
            identity_id="test-stable-id",
            scope=mock_scope,
        )
        assert entry.state == ScopeLifecycleState.ACTIVE
        assert entry.identity_id == "test-stable-id"
        assert entry.scope is mock_scope
        assert entry.suspended_at is None
        assert entry.grace_timer is None

    def test_suspended_at_field(self, mock_scope):
        entry = ScopeStateEntry(
            state=ScopeLifecycleState.SUSPENDED,
            identity_id="test-id",
            scope=mock_scope,
            suspended_at=1700000000.0,
        )
        assert entry.suspended_at == 1700000000.0

    def test_sequential_transitions(self, mock_scope):
        """Test a full lifecycle: ACTIVE → SUSPENDED → ACTIVE → DISPOSED."""
        entry = _make_entry(ScopeLifecycleState.ACTIVE, mock_scope)

        entry.transition(ScopeLifecycleState.SUSPENDED)
        assert entry.state == ScopeLifecycleState.SUSPENDED

        entry.transition(ScopeLifecycleState.ACTIVE)
        assert entry.state == ScopeLifecycleState.ACTIVE

        entry.transition(ScopeLifecycleState.DISPOSED)
        assert entry.state == ScopeLifecycleState.DISPOSED

        # Now it's terminal — cannot transition anywhere
        with pytest.raises(InvalidStateTransition):
            entry.transition(ScopeLifecycleState.ACTIVE)


# ---------------------------------------------------------------------------
# ScopeLifecycleState enum
# ---------------------------------------------------------------------------


class TestScopeLifecycleState:
    """Test the enum values and string representation."""

    def test_enum_values(self):
        assert ScopeLifecycleState.ACTIVE == "active"
        assert ScopeLifecycleState.SUSPENDED == "suspended"
        assert ScopeLifecycleState.DISPOSED == "disposed"

    def test_enum_is_str(self):
        """ScopeLifecycleState inherits from str for JSON serialization."""
        assert isinstance(ScopeLifecycleState.ACTIVE, str)

    def test_enum_has_three_members(self):
        assert len(ScopeLifecycleState) == 3
