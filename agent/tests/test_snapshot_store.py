"""
SnapshotStore tests.

Covers: capture, initial content, edit baseline, versions, checkpoints,
stats, clear, max versions per file.
"""

from __future__ import annotations

import pytest

from mobileflow_agent.services.snapshot_store import SnapshotStore


class TestSnapshotStore:
    def test_capture_and_get_initial(self):
        s = SnapshotStore()
        s.capture_before_edit("a.py", "original content")
        assert s.get_initial_content("a.py") == "original content"

    def test_second_capture_keeps_initial(self):
        s = SnapshotStore()
        s.capture_before_edit("a.py", "original content")
        s.capture_before_edit("a.py", "modified content")
        assert s.get_initial_content("a.py") == "original content"

    def test_edit_baseline_is_latest(self):
        s = SnapshotStore()
        s.capture_before_edit("a.py", "original content")
        s.capture_before_edit("a.py", "modified content")
        assert s.get_edit_baseline("a.py") == "modified content"

    def test_version_count(self):
        s = SnapshotStore()
        s.capture_before_edit("a.py", "v0")
        s.capture_before_edit("a.py", "v1")
        assert s.get_version_count("a.py") == 2

    def test_get_specific_version(self):
        s = SnapshotStore()
        s.capture_before_edit("a.py", "v0")
        s.capture_before_edit("a.py", "v1")
        assert s.get_version("a.py", 0) == "v0"
        assert s.get_version("a.py", 1) == "v1"

    def test_nonexistent_file(self):
        s = SnapshotStore()
        assert s.get_initial_content("nope.py") is None

    def test_list_modified_files(self):
        s = SnapshotStore()
        s.capture_before_edit("a.py", "a")
        s.capture_before_edit("b.py", "b")
        files = s.list_modified_files()
        assert "a.py" in files and "b.py" in files

    def test_checkpoint(self):
        s = SnapshotStore()
        s.capture_before_edit("a.py", "a")
        cp_id = s.create_checkpoint("test checkpoint")
        cp = s.get_checkpoint(cp_id)
        assert cp is not None and "a.py" in cp.file_versions

    def test_stats(self):
        s = SnapshotStore()
        s.capture_before_edit("a.py", "a")
        s.capture_before_edit("b.py", "b")
        assert s.stats["files"] == 2

    def test_clear(self):
        s = SnapshotStore()
        s.capture_before_edit("a.py", "a")
        s.clear()
        assert s.get_initial_content("a.py") is None
        assert s.stats["files"] == 0

    def test_max_versions_per_file(self):
        s = SnapshotStore()
        for i in range(25):
            s.capture_before_edit("hot.py", f"v{i}" * 100)
        assert s.get_version_count("hot.py") <= s.MAX_VERSIONS_PER_FILE
