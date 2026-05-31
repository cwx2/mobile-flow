"""
OperationManager tests.

Covers: start/end lifecycle, is_idle (read_only vs write), is_running,
        should_block, should_show_progress, concurrent same-kind operations.
"""

from __future__ import annotations

from mobileflow_agent.utils.operation import Op, OpKind, Operation, OperationManager


def test_start_end_lifecycle():
    """start() returns an ID, end() removes the operation."""
    mgr = OperationManager()
    op_id = mgr.start(Op.Commit)
    assert mgr.active_count == 1
    assert mgr.is_running(OpKind.COMMIT)

    mgr.end(op_id)
    assert mgr.active_count == 0
    assert not mgr.is_running(OpKind.COMMIT)


def test_is_idle_with_read_only():
    """is_idle() returns True when only read_only operations are running."""
    mgr = OperationManager()
    op_id = mgr.start(Op.Diff)  # read_only=True
    assert mgr.is_idle()  # Read-only doesn't break idle

    mgr.end(op_id)


def test_is_idle_with_write():
    """is_idle() returns False when a write operation is running."""
    mgr = OperationManager()
    op_id = mgr.start(Op.Commit)  # read_only=False
    assert not mgr.is_idle()

    mgr.end(op_id)
    assert mgr.is_idle()


def test_should_block():
    """should_block() returns True when a blocking operation is running."""
    mgr = OperationManager()
    assert not mgr.should_block()

    op_id = mgr.start(Op.Commit)  # blocking=True
    assert mgr.should_block()

    mgr.end(op_id)
    assert not mgr.should_block()


def test_should_show_progress():
    """should_show_progress() reflects show_progress flag."""
    mgr = OperationManager()
    assert not mgr.should_show_progress()

    op_id = mgr.start(Op.Push)  # show_progress=True
    assert mgr.should_show_progress()

    mgr.end(op_id)
    assert not mgr.should_show_progress()


def test_concurrent_same_kind():
    """Multiple operations of the same kind can run concurrently."""
    mgr = OperationManager()
    id1 = mgr.start(Op.Diff)
    id2 = mgr.start(Op.Diff)
    assert mgr.active_count == 2
    assert mgr.is_running(OpKind.DIFF)

    mgr.end(id1)
    assert mgr.active_count == 1
    assert mgr.is_running(OpKind.DIFF)

    mgr.end(id2)
    assert mgr.active_count == 0
    assert not mgr.is_running(OpKind.DIFF)


def test_end_unknown_id():
    """end() with an unknown ID is a no-op (doesn't crash)."""
    mgr = OperationManager()
    mgr.end(9999)  # Should not raise
    assert mgr.active_count == 0


def test_operation_attributes():
    """Verify Op.* constants have correct attribute values."""
    assert Op.Commit.blocking is True
    assert Op.Commit.read_only is False
    assert Op.Diff.read_only is True
    assert Op.Diff.blocking is False
    assert Op.Push.remote is True
    assert Op.Pull.retry is True
    assert Op.Fetch.retry is True
    assert Op.Log.show_progress is False
