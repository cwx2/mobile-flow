"""
RefreshScheduler tests.

Covers: debounce + throttle chain, guard conditions (auto_refresh, isRepositoryHuge,
        isIdle), file tree cache invalidation, cooldown behavior.
"""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, MagicMock, PropertyMock

import pytest

from mobileflow_agent.core.event_bus import EventBus
from mobileflow_agent.core.events import Events
from mobileflow_agent.services.refresh_scheduler import RefreshScheduler
from mobileflow_agent.utils.operation import OperationManager


def _make_mocks():
    """Create mock git_state, file_service, and operations."""
    git_state = MagicMock()
    git_state.is_repository_huge = False
    git_state.throttled_status = AsyncMock()

    file_service = MagicMock()
    file_service.invalidate_tree_cache = MagicMock()

    operations = OperationManager()

    return git_state, file_service, operations


@pytest.mark.asyncio
async def test_file_change_triggers_refresh():
    """A file change event eventually triggers throttled_status."""
    git_state, file_service, operations = _make_mocks()
    bus = EventBus()

    scheduler = RefreshScheduler(
        git_state=git_state,
        file_service=file_service,
        operations=operations,
        event_bus=bus,
        debounce_delay=0.05,  # Short delay for testing
        cooldown=0.0,
    )

    await bus.emit(Events.FILE_CHANGED, {"path": "src/main.py", "change": "modified"})

    # Wait for debounce + execution
    await asyncio.sleep(0.3)

    git_state.throttled_status.assert_called()
    scheduler.dispose()


@pytest.mark.asyncio
async def test_auto_refresh_disabled_skips():
    """When auto_refresh is disabled, file changes are ignored."""
    git_state, file_service, operations = _make_mocks()
    bus = EventBus()

    scheduler = RefreshScheduler(
        git_state=git_state,
        file_service=file_service,
        operations=operations,
        event_bus=bus,
        debounce_delay=0.05,
        cooldown=0.0,
        auto_refresh=False,
    )

    await bus.emit(Events.FILE_CHANGED, {"path": "src/main.py", "change": "modified"})
    await asyncio.sleep(0.2)

    git_state.throttled_status.assert_not_called()
    scheduler.dispose()


@pytest.mark.asyncio
async def test_huge_repo_skips_refresh():
    """When repository is huge, file changes are ignored."""
    git_state, file_service, operations = _make_mocks()
    git_state.is_repository_huge = True
    bus = EventBus()

    scheduler = RefreshScheduler(
        git_state=git_state,
        file_service=file_service,
        operations=operations,
        event_bus=bus,
        debounce_delay=0.05,
        cooldown=0.0,
    )

    await bus.emit(Events.FILE_CHANGED, {"path": "src/main.py", "change": "modified"})
    await asyncio.sleep(0.2)

    git_state.throttled_status.assert_not_called()
    scheduler.dispose()


@pytest.mark.asyncio
async def test_create_event_invalidates_tree_cache():
    """File create events invalidate the file tree cache."""
    git_state, file_service, operations = _make_mocks()
    bus = EventBus()

    scheduler = RefreshScheduler(
        git_state=git_state,
        file_service=file_service,
        operations=operations,
        event_bus=bus,
        debounce_delay=0.05,
        cooldown=0.0,
    )

    await bus.emit(Events.FILE_CHANGED, {"path": "src/new_file.py", "change": "created"})

    # Tree cache invalidation happens synchronously in the handler
    file_service.invalidate_tree_cache.assert_called_once_with("src/new_file.py")
    scheduler.dispose()


@pytest.mark.asyncio
async def test_modify_event_no_tree_invalidation():
    """File modify events do NOT invalidate the file tree cache."""
    git_state, file_service, operations = _make_mocks()
    bus = EventBus()

    scheduler = RefreshScheduler(
        git_state=git_state,
        file_service=file_service,
        operations=operations,
        event_bus=bus,
        debounce_delay=0.05,
        cooldown=0.0,
    )

    await bus.emit(Events.FILE_CHANGED, {"path": "src/main.py", "change": "modified"})

    file_service.invalidate_tree_cache.assert_not_called()
    scheduler.dispose()


@pytest.mark.asyncio
async def test_not_idle_skips_refresh():
    """When write operations are running, file changes are skipped."""
    git_state, file_service, operations = _make_mocks()
    bus = EventBus()

    # Simulate a running write operation
    from mobileflow_agent.utils.operation import Op
    op_id = operations.start(Op.Commit)

    scheduler = RefreshScheduler(
        git_state=git_state,
        file_service=file_service,
        operations=operations,
        event_bus=bus,
        debounce_delay=0.05,
        cooldown=0.0,
    )

    await bus.emit(Events.FILE_CHANGED, {"path": "src/main.py", "change": "modified"})
    await asyncio.sleep(0.2)

    git_state.throttled_status.assert_not_called()

    operations.end(op_id)
    scheduler.dispose()
