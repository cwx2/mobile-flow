"""ProjectManager recent projects property-based and unit tests.

Tests cover:
  P9: Recent projects limit and sort order — get_recent_projects(limit)
      returns at most `limit` entries, sorted by last_opened descending.

Unit tests:
  - get_recent_projects with empty list
  - _update_last_opened persistence
  - Backward compatibility with old projects.json (no last_opened field)

# Feature: project-browser-enhance
"""

from __future__ import annotations

import json
import tempfile
import shutil
import time
from pathlib import Path
from unittest.mock import patch

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from mobileflow_agent.core.config import AgentConfig
from mobileflow_agent.services.project_manager import ProjectManager
from mobileflow_agent.services.project_scanner import ProjectScanner


# ═══════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════


def _make_manager(base_dir: Path, projects: list[dict] | None = None) -> ProjectManager:
    """Create a ProjectManager with a temporary data directory."""
    data_dir = base_dir / "data"
    data_dir.mkdir(exist_ok=True)

    if projects is not None:
        config_file = data_dir / "projects.json"
        for p in projects:
            proj_dir = Path(p["path"])
            proj_dir.mkdir(parents=True, exist_ok=True)
        config_file.write_text(
            json.dumps({"projects": projects, "current_index": 0}),
            encoding="utf-8",
        )

    config = AgentConfig(
        work_dir=str(base_dir / "work"),
        data_dir=data_dir,
    )
    return ProjectManager(config)


def _patch_scanner():
    """Context manager that patches ProjectScanner static methods."""
    return (
        patch.object(ProjectScanner, '_detect_project_type', return_value=None),
        patch.object(ProjectScanner, '_has_git', return_value=False),
    )


# ═══════════════════════════════════════════════════════════════
# Property-based tests (Hypothesis)
# ═══════════════════════════════════════════════════════════════


# Feature: project-browser-enhance, Property 9: Recent projects limit and sort order
class TestRecentProjectsLimitAndSort:
    """For any list of projects with last_opened timestamps,
    get_recent_projects(limit) returns at most `limit` entries,
    sorted by last_opened in descending order (most recent first)."""

    @given(
        num_projects=st.integers(min_value=0, max_value=15),
        limit=st.integers(min_value=1, max_value=10),
    )
    @settings(max_examples=100)
    def test_limit_and_sort_invariant(self, num_projects: int, limit: int):
        td = tempfile.mkdtemp()
        try:
            base = Path(td)
            projects = []
            base_time = 1700000000.0
            for i in range(num_projects):
                proj_dir = base / f"proj_{i}"
                proj_dir.mkdir(exist_ok=True)
                projects.append({
                    "path": str(proj_dir),
                    "name": f"proj_{i}",
                    "last_opened": base_time + i * 100,
                })

            manager = _make_manager(base, projects)

            p1, p2 = _patch_scanner()
            with p1, p2:
                results = manager.get_recent_projects(limit=limit)

            assert len(results) <= limit
            assert len(results) <= num_projects

            timestamps = [r["last_opened"] for r in results]
            assert timestamps == sorted(timestamps, reverse=True), (
                f"Not sorted descending: {timestamps}"
            )
        finally:
            shutil.rmtree(td, ignore_errors=True)


# ═══════════════════════════════════════════════════════════════
# Unit tests
# ═══════════════════════════════════════════════════════════════


class TestRecentProjectsEmpty:
    def test_empty_list(self, tmp_path: Path):
        manager = _make_manager(tmp_path, projects=[])
        p1, p2 = _patch_scanner()
        with p1, p2:
            results = manager.get_recent_projects()
        assert results == []


class TestRecentProjectsSchemaCompleteness:
    REQUIRED_KEYS = {"path", "name", "project_type", "has_git", "exists", "last_opened"}

    def test_all_keys_present(self, tmp_path: Path):
        proj_dir = tmp_path / "myproj"
        proj_dir.mkdir(exist_ok=True)
        manager = _make_manager(tmp_path, projects=[{
            "path": str(proj_dir),
            "name": "myproj",
            "last_opened": time.time(),
        }])

        with (
            patch.object(ProjectScanner, '_detect_project_type', return_value="python"),
            patch.object(ProjectScanner, '_has_git', return_value=True),
        ):
            results = manager.get_recent_projects()

        assert len(results) == 1
        missing = self.REQUIRED_KEYS - set(results[0].keys())
        assert not missing, f"Missing keys: {missing}"


class TestBackwardCompatibility:
    def test_old_entries_default_to_zero(self, tmp_path: Path):
        proj_dir = tmp_path / "oldproj"
        proj_dir.mkdir(exist_ok=True)
        manager = _make_manager(tmp_path, projects=[{
            "path": str(proj_dir),
            "name": "oldproj",
        }])

        p1, p2 = _patch_scanner()
        with p1, p2:
            results = manager.get_recent_projects()

        assert len(results) == 1
        assert results[0]["last_opened"] == 0


class TestUpdateLastOpened:
    def test_timestamp_updated(self, tmp_path: Path):
        proj_dir = tmp_path / "myproj"
        proj_dir.mkdir(exist_ok=True)
        manager = _make_manager(tmp_path, projects=[{
            "path": str(proj_dir),
            "name": "myproj",
            "last_opened": 1700000000.0,
        }])

        before = time.time()
        manager._update_last_opened(str(proj_dir))
        after = time.time()

        proj = next(p for p in manager._projects if p["path"] == str(proj_dir))
        assert proj["last_opened"] >= before
        assert proj["last_opened"] <= after


class TestNonExistentProjectMarkedCorrectly:
    def test_deleted_directory(self, tmp_path: Path):
        proj_dir = tmp_path / "deleted_proj"
        proj_dir.mkdir(exist_ok=True)
        manager = _make_manager(tmp_path, projects=[{
            "path": str(proj_dir),
            "name": "deleted_proj",
            "last_opened": time.time(),
        }])

        proj_dir.rmdir()

        p1, p2 = _patch_scanner()
        with p1, p2:
            results = manager.get_recent_projects()

        assert len(results) == 1
        assert results[0]["exists"] is False
