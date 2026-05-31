"""
Git service model tests.

Covers: GitFileStatus, GitBranch, GitLogEntry, GitStatusResult, GitService._update_cwd.
"""

from __future__ import annotations

import pytest

from mobileflow_agent.services.git_service import (
    GitFileStatus, GitBranch, GitLogEntry, GitStatusResult, GitService,
)


class TestGitFileStatus:
    def test_basic(self):
        fs = GitFileStatus(path="a.py", status="M", staged=True)
        d = fs.to_dict()
        assert d["status"] == "M" and d["staged"]

    def test_rename(self):
        fs = GitFileStatus(path="b.py", status="R", staged=True, old_path="old.py")
        assert fs.to_dict()["old_path"] == "old.py"


class TestGitBranch:
    def test_local(self):
        br = GitBranch(name="main", current=True)
        d = br.to_dict()
        assert d["current"] and not d["remote"]

    def test_remote(self):
        br = GitBranch(name="origin/main", current=False, remote=True)
        assert br.to_dict()["remote"]


class TestGitLogEntry:
    def test_to_dict(self):
        le = GitLogEntry(hash="abc", short_hash="a", message="fix", author="dev", date="2026")
        assert le.to_dict()["message"] == "fix"


class TestGitStatusResult:
    def test_full(self):
        sr = GitStatusResult(branch="main")
        sr.staged.append(GitFileStatus(path="x", status="A", staged=True))
        sr.unstaged.append(GitFileStatus(path="y", status="M", staged=False))
        sr.untracked.append(GitFileStatus(path="z", status="?", staged=False))
        d = sr.to_dict()
        assert d["branch"] == "main" and len(d["staged"]) == 1

    def test_error(self):
        assert GitStatusResult(error="err").to_dict()["error"] == "err"


class TestGitServiceCwd:
    def test_update_cwd(self):
        gs = GitService(cwd="/tmp")
        gs._update_cwd("/p")
        assert gs._cwd == "/p"
