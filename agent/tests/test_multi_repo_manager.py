"""Tests for MultiRepoManager — parallel multi-repository state management.

Covers:
  1. open_repo: register + initial refresh
  2. close_repo: dispose + remove
  3. get_repo_for_path: longest-prefix routing
  4. get_all_status: aggregated snapshot
  5. refresh_all: parallel refresh with concurrency limit
  6. open_discovered_repos: batch registration
  7. _normalize: path normalization consistency
"""

import asyncio
import os
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from mobileflow_agent.services.multi_repo_manager import MultiRepoManager


@pytest.fixture
def mock_git_service():
    """Mock GitService that returns predictable status."""
    git = MagicMock()
    git._cwd = ""
    git._command_timeout = 30
    git._discovery_timeout = 5
    return git


@pytest.fixture
def mock_event_bus():
    """Mock EventBus."""
    bus = MagicMock()
    bus.emit = AsyncMock()
    bus.on = MagicMock()
    bus.off = MagicMock()
    return bus


@pytest.fixture
def manager(mock_git_service, mock_event_bus):
    """Create a MultiRepoManager instance."""
    return MultiRepoManager(git_service=mock_git_service, event_bus=mock_event_bus)


class TestNormalize:
    """Path normalization for consistent dict keys."""

    def test_forward_slash(self, manager):
        result = manager._normalize("D:\\project\\repo")
        assert "/" in result
        assert "\\" not in result

    def test_no_trailing_slash(self, manager):
        result = manager._normalize("/home/user/repo/")
        assert not result.endswith("/")

    def test_consistent_keys(self, manager):
        a = manager._normalize("D:\\project\\repo")
        b = manager._normalize("D:/project/repo")
        assert a == b


class TestOpenCloseRepo:
    """Repository registration and disposal."""

    @pytest.mark.asyncio
    async def test_open_repo_registers_manager(self, manager):
        """open_repo creates a GitStateManager for the path."""
        with patch("mobileflow_agent.services.multi_repo_manager.GitStateManager") as MockGSM:
            mock_instance = MagicMock()
            mock_instance.initialize = AsyncMock()
            mock_instance.throttled_status = AsyncMock()
            MockGSM.return_value = mock_instance

            await manager.open_repo("/project/repo1")
            assert manager.repo_count == 1

    @pytest.mark.asyncio
    async def test_open_repo_idempotent(self, manager):
        """Opening the same repo twice doesn't duplicate."""
        with patch("mobileflow_agent.services.multi_repo_manager.GitStateManager") as MockGSM:
            mock_instance = MagicMock()
            mock_instance.initialize = AsyncMock()
            MockGSM.return_value = mock_instance

            await manager.open_repo("/project/repo1")
            await manager.open_repo("/project/repo1")
            assert manager.repo_count == 1

    @pytest.mark.asyncio
    async def test_close_repo_removes(self, manager):
        """close_repo disposes and removes the manager."""
        with patch("mobileflow_agent.services.multi_repo_manager.GitStateManager") as MockGSM:
            mock_instance = MagicMock()
            mock_instance.initialize = AsyncMock()
            mock_instance.dispose = MagicMock()
            MockGSM.return_value = mock_instance

            await manager.open_repo("/project/repo1")
            await manager.close_repo("/project/repo1")
            assert manager.repo_count == 0
            mock_instance.dispose.assert_called_once()

    @pytest.mark.asyncio
    async def test_close_nonexistent_no_error(self, manager):
        """Closing a repo that wasn't opened doesn't raise."""
        await manager.close_repo("/nonexistent")
        assert manager.repo_count == 0


class TestGetRepoForPath:
    """File path to repository routing (longest-prefix match)."""

    @pytest.mark.asyncio
    async def test_routes_to_correct_repo(self, manager):
        """File inside a repo routes to that repo."""
        with patch("mobileflow_agent.services.multi_repo_manager.GitStateManager") as MockGSM:
            mock1 = MagicMock()
            mock1.initialize = AsyncMock()
            mock2 = MagicMock()
            mock2.initialize = AsyncMock()
            MockGSM.side_effect = [mock1, mock2]

            await manager.open_repo("/project/frontend")
            await manager.open_repo("/project/backend")

            result = manager.get_repo_for_path("/project/backend/src/main.py")
            assert result == mock2

    @pytest.mark.asyncio
    async def test_longest_prefix_wins(self, manager):
        """Nested repo takes priority over parent."""
        with patch("mobileflow_agent.services.multi_repo_manager.GitStateManager") as MockGSM:
            mock_parent = MagicMock()
            mock_parent.initialize = AsyncMock()
            mock_child = MagicMock()
            mock_child.initialize = AsyncMock()
            MockGSM.side_effect = [mock_parent, mock_child]

            await manager.open_repo("/project")
            await manager.open_repo("/project/packages/sub")

            result = manager.get_repo_for_path("/project/packages/sub/index.ts")
            assert result == mock_child

    def test_no_match_returns_none(self, manager):
        """File outside any repo returns None."""
        result = manager.get_repo_for_path("/somewhere/else/file.txt")
        assert result is None


class TestGetAllStatus:
    """Aggregated status snapshot."""

    @pytest.mark.asyncio
    async def test_returns_all_repos(self, manager):
        """get_all_status includes all registered repos."""
        with patch("mobileflow_agent.services.multi_repo_manager.GitStateManager") as MockGSM:
            mock1 = MagicMock()
            mock1.initialize = AsyncMock()
            mock1.status = {
                "branch": "main", "ahead": 1, "behind": 0,
                "staged": [{"path": "a.py", "status": "M"}],
                "unstaged": [], "untracked": [], "error": ""
            }
            mock2 = MagicMock()
            mock2.initialize = AsyncMock()
            mock2.status = {
                "branch": "dev", "ahead": 0, "behind": 2,
                "staged": [], "unstaged": [], "untracked": [], "error": ""
            }
            MockGSM.side_effect = [mock1, mock2]

            await manager.open_repo("/project/repo1")
            await manager.open_repo("/project/repo2")

            result = manager.get_all_status()
            assert len(result) == 2
            branches = {r["branch"] for r in result}
            assert "main" in branches
            assert "dev" in branches

    @pytest.mark.asyncio
    async def test_uninitialized_repo_returns_error(self, manager):
        """Repo without status returns error='not_initialized'."""
        with patch("mobileflow_agent.services.multi_repo_manager.GitStateManager") as MockGSM:
            mock1 = MagicMock()
            mock1.initialize = AsyncMock()
            mock1.status = None  # Not yet initialized
            MockGSM.return_value = mock1

            await manager.open_repo("/project/repo1")
            result = manager.get_all_status()
            assert result[0]["error"] == "not_initialized"


class TestRefreshAll:
    """Parallel refresh with concurrency control."""

    @pytest.mark.asyncio
    async def test_refreshes_all_repos(self, manager):
        """refresh_all calls throttled_status on each manager."""
        with patch("mobileflow_agent.services.multi_repo_manager.GitStateManager") as MockGSM:
            mock1 = MagicMock()
            mock1.initialize = AsyncMock()
            mock1.throttled_status = AsyncMock()
            mock2 = MagicMock()
            mock2.initialize = AsyncMock()
            mock2.throttled_status = AsyncMock()
            MockGSM.side_effect = [mock1, mock2]

            await manager.open_repo("/project/repo1")
            await manager.open_repo("/project/repo2")
            await manager.refresh_all()

            mock1.throttled_status.assert_called_once()
            mock2.throttled_status.assert_called_once()

    @pytest.mark.asyncio
    async def test_empty_repos_no_error(self, manager):
        """refresh_all with no repos doesn't raise."""
        await manager.refresh_all()  # Should not raise


class TestOpenDiscoveredRepos:
    """Batch registration from discovery results."""

    @pytest.mark.asyncio
    async def test_opens_multiple(self, manager):
        """open_discovered_repos registers all provided repos."""
        with patch("mobileflow_agent.services.multi_repo_manager.GitStateManager") as MockGSM:
            mock = MagicMock()
            mock.initialize = AsyncMock()
            MockGSM.return_value = mock

            repos = [
                {"path": "/project/a", "name": "a", "branch": "main"},
                {"path": "/project/b", "name": "b", "branch": "dev"},
                {"path": "/project/c", "name": "c", "branch": "feat"},
            ]
            await manager.open_discovered_repos(repos)
            assert manager.repo_count == 3

    @pytest.mark.asyncio
    async def test_skips_already_registered(self, manager):
        """Doesn't re-open repos that are already registered."""
        with patch("mobileflow_agent.services.multi_repo_manager.GitStateManager") as MockGSM:
            mock = MagicMock()
            mock.initialize = AsyncMock()
            MockGSM.return_value = mock

            await manager.open_repo("/project/a")
            repos = [
                {"path": "/project/a", "name": "a"},
                {"path": "/project/b", "name": "b"},
            ]
            await manager.open_discovered_repos(repos)
            # Only /project/b should be newly opened
            assert manager.repo_count == 2


class TestDispose:
    """Cleanup all managers."""

    @pytest.mark.asyncio
    async def test_dispose_clears_all(self, manager):
        """dispose() releases all managers."""
        with patch("mobileflow_agent.services.multi_repo_manager.GitStateManager") as MockGSM:
            mock = MagicMock()
            mock.initialize = AsyncMock()
            mock.dispose = MagicMock()
            MockGSM.return_value = mock

            await manager.open_repo("/project/a")
            await manager.open_repo("/project/b")
            manager.dispose()

            assert manager.repo_count == 0
            assert mock.dispose.call_count == 2
