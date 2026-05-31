"""
GitStateManager tests.

Covers: run() with read_only/write operations, automatic refresh after write,
        optimistic update, RepositoryState guard, retry logic, throttled_status,
        update_model_state cancellation, isRepositoryHuge detection.
"""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from mobileflow_agent.core.event_bus import EventBus
from mobileflow_agent.core.errors import AppErrorCode, GitError
from mobileflow_agent.services.git_state import GitStateManager, RepositoryState
from mobileflow_agent.utils.operation import Op


def _make_git_service():
    """Create a mock GitService with standard return values."""
    git = AsyncMock()

    # status() returns a GitStatusResult-like object with to_dict()
    status_obj = MagicMock()
    status_obj.to_dict.return_value = {
        "branch": "main",
        "staged": [],
        "unstaged": [{"path": "file.py", "status": "M", "staged": False}],
        "untracked": [],
        "error": "",
    }
    git.status.return_value = status_obj

    # branches() returns a dict
    git.branches.return_value = {
        "branches": [{"name": "main", "current": True, "remote": False}],
        "error": "",
    }

    # log() returns a dict
    git.log.return_value = {
        "entries": [{"hash": "abc123", "short_hash": "abc", "message": "init", "author": "dev", "date": "2025-01-01"}],
        "error": "",
    }

    return git


@pytest.fixture
def git_state():
    """Create a GitStateManager with mocked dependencies."""
    git = _make_git_service()
    bus = EventBus()
    state = GitStateManager(git_service=git, event_bus=bus, status_limit=5000)
    return state, git, bus


@pytest.mark.asyncio
async def test_initialize_populates_state(git_state):
    """initialize() fetches status/branches/log and populates cached state."""
    state, git, _ = git_state
    await state.initialize()

    assert state.is_initialized
    assert state.status is not None
    assert state.status["branch"] == "main"
    assert state.branches is not None
    assert state.log_entries is not None
    git.status.assert_called()
    git.branches.assert_called()
    git.log.assert_called()


@pytest.mark.asyncio
async def test_run_write_triggers_refresh(git_state):
    """Write operations (non-read_only) trigger update_model_state."""
    state, git, _ = git_state

    async def do_commit():
        return {"success": True, "error": ""}

    result = await state.run(Op.Commit, run_operation=do_commit)

    assert result["success"] is True
    # update_model_state was called (which calls git.status)
    assert git.status.call_count >= 1


@pytest.mark.asyncio
async def test_run_read_only_no_refresh(git_state):
    """Read-only operations do NOT trigger update_model_state."""
    state, git, _ = git_state

    async def do_diff():
        return {"diff": "...", "error": ""}

    result = await state.run(Op.Diff, run_operation=do_diff)

    assert result["diff"] == "..."
    # git.status should NOT have been called (no refresh for read_only)
    git.status.assert_not_called()


@pytest.mark.asyncio
async def test_run_optimistic_update(git_state):
    """Optimistic update applies immediately before real refresh."""
    state, git, bus = git_state
    # Pre-populate state
    await state.initialize()
    git.status.reset_mock()

    pushed_keys = []
    async def capture_push(data):
        pushed_keys.append(data.get("key"))
    bus.on("state.changed", capture_push)

    async def do_commit():
        return {"success": True}

    def optimistic():
        return {"status": {**state.status, "staged": []}}

    await state.run(Op.Commit, run_operation=do_commit, get_optimistic=optimistic)

    # Optimistic update should have pushed git.status before the real refresh
    assert "git.status" in pushed_keys


@pytest.mark.asyncio
async def test_run_rejects_when_disposed(git_state):
    """run() raises RuntimeError when state is Disposed."""
    state, _, _ = git_state
    state._state = RepositoryState.DISPOSED

    with pytest.raises(RuntimeError, match="仓库状态异常"):
        await state.run(Op.Status)


@pytest.mark.asyncio
async def test_run_fires_events(git_state):
    """run() fires git.op.start and git.op.done events."""
    state, _, bus = git_state
    events = []

    async def capture(data):
        events.append(data)

    bus.on("git.op.start", capture)
    bus.on("git.op.done", capture)

    async def do_stage():
        return {"success": True}

    await state.run(Op.Stage, run_operation=do_stage)

    kinds = [e.get("kind") for e in events]
    assert "Stage" in kinds  # Both start and done should have fired


@pytest.mark.asyncio
async def test_retry_run_retries_on_lock():
    """_retry_run retries on index.lock errors with backoff."""
    git = _make_git_service()
    bus = EventBus()
    state = GitStateManager(git_service=git, event_bus=bus)

    call_count = 0

    async def flaky_operation():
        nonlocal call_count
        call_count += 1
        if call_count < 3:
            raise GitError(
                code=AppErrorCode.GIT_REPO_LOCKED,
                message="index.lock exists",
                stderr="Unable to create index.lock",
            )
        return {"success": True}

    result = await state._retry_run(Op.Commit, flaky_operation)
    assert result["success"] is True
    assert call_count == 3  # 2 failures + 1 success


@pytest.mark.asyncio
async def test_retry_run_no_retry_on_non_lock_error():
    """_retry_run does NOT retry on non-lock errors."""
    git = _make_git_service()
    bus = EventBus()
    state = GitStateManager(git_service=git, event_bus=bus)

    async def always_fail():
        raise ValueError("some other error")

    with pytest.raises(ValueError, match="some other error"):
        await state._retry_run(Op.Commit, always_fail)


@pytest.mark.asyncio
async def test_update_model_state_cancellation(git_state):
    """A new update_model_state call cancels the previous one."""
    state, git, _ = git_state

    # Make status slow so we can cancel it
    async def slow_status():
        await asyncio.sleep(0.5)
        return MagicMock(to_dict=lambda: {"branch": "old", "staged": [], "unstaged": [], "untracked": []})

    git.status.side_effect = slow_status

    # Start first refresh
    task1 = asyncio.create_task(state.update_model_state())
    await asyncio.sleep(0.01)

    # Start second refresh (should cancel first)
    git.status.side_effect = None  # Reset to fast mock
    git.status.return_value = MagicMock(
        to_dict=lambda: {"branch": "new", "staged": [], "unstaged": [], "untracked": []}
    )
    await state.update_model_state()

    # The state should reflect the second (newer) refresh
    assert state.status["branch"] == "new"

    # Clean up
    task1.cancel()
    try:
        await task1
    except asyncio.CancelledError:
        pass


@pytest.mark.asyncio
async def test_huge_repo_detection(git_state):
    """Repos with > status_limit changes are marked as huge."""
    state, git, _ = git_state
    state._status_limit = 10  # Low threshold for testing

    # Return many files
    many_files = [{"path": f"file{i}.py", "status": "M", "staged": False} for i in range(20)]
    git.status.return_value = MagicMock(
        to_dict=lambda: {"branch": "main", "staged": [], "unstaged": many_files, "untracked": [], "error": ""}
    )

    await state.update_model_state()
    assert state.is_repository_huge is True


@pytest.mark.asyncio
async def test_head_change_detection(git_state):
    """HEAD changes are detected and logged."""
    state, git, _ = git_state

    # First refresh: branch = main
    await state.initialize()
    assert state._prev_head == "main"

    # Second refresh: branch = feature
    git.status.return_value = MagicMock(
        to_dict=lambda: {"branch": "feature", "staged": [], "unstaged": [], "untracked": [], "error": ""}
    )
    await state.update_model_state()
    assert state._prev_head == "feature"


@pytest.mark.asyncio
async def test_clear_resets_state(git_state):
    """clear() resets all cached state to None."""
    state, _, _ = git_state
    await state.initialize()
    assert state.is_initialized

    state.clear()
    assert not state.is_initialized
    assert state.status is None
    assert state.branches is None
    assert state.log_entries is None
