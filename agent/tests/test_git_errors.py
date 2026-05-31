"""
GitError classification tests.

Covers: GitError.classify() mapping stderr messages to structured error codes.
"""

from __future__ import annotations

from mobileflow_agent.core.errors import AppErrorCode, GitError


def test_classify_repo_locked():
    """index.lock errors map to GIT_REPO_LOCKED."""
    assert GitError.classify("Unable to create '/repo/.git/index.lock': File exists.") == AppErrorCode.GIT_REPO_LOCKED
    assert GitError.classify("fatal: unable to create '/repo/.git/index.lock'") == AppErrorCode.GIT_REPO_LOCKED


def test_classify_cant_lock_ref():
    """Ref lock errors map to GIT_CANT_LOCK_REF."""
    assert GitError.classify("error: cannot lock ref 'refs/heads/main'") == AppErrorCode.GIT_CANT_LOCK_REF
    assert GitError.classify("unable to resolve reference 'refs/heads/main'") == AppErrorCode.GIT_CANT_LOCK_REF


def test_classify_cant_rebase():
    """Rebase errors map to GIT_CANT_REBASE."""
    assert GitError.classify("error: cannot rebase: You have unstaged changes.") == AppErrorCode.GIT_CANT_REBASE


def test_classify_not_a_repo():
    """Not-a-repo errors map to GIT_NOT_A_REPO."""
    assert GitError.classify("fatal: not a git repository (or any parent up to mount point /)") == AppErrorCode.GIT_NOT_A_REPO


def test_classify_unknown():
    """Unknown errors return None."""
    assert GitError.classify("fatal: some random error") is None
    assert GitError.classify("") is None


def test_classify_case_insensitive():
    """Classification is case-insensitive."""
    assert GitError.classify("UNABLE TO CREATE INDEX.LOCK") == AppErrorCode.GIT_REPO_LOCKED
    assert GitError.classify("NOT A GIT REPOSITORY") == AppErrorCode.GIT_NOT_A_REPO
