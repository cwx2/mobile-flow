"""Git domain payload models for the MobileFlow WebSocket protocol.

Defines typed Pydantic models for the 28 git-related message types:
  - git.status           (GIT_STATUS)           — request repo status
  - git.status.result    (GIT_STATUS_RESULT)    — repo status
  - git.diff             (GIT_DIFF)             — request file diff
  - git.diff.result      (GIT_DIFF_RESULT)      — diff content
  - git.stage            (GIT_STAGE)            — stage files
  - git.stage.result     (GIT_STAGE_RESULT)     — stage result
  - git.unstage          (GIT_UNSTAGE)          — unstage files
  - git.unstage.result   (GIT_UNSTAGE_RESULT)   — unstage result
  - git.commit           (GIT_COMMIT)           — create commit
  - git.commit.result    (GIT_COMMIT_RESULT)    — commit result
  - git.push             (GIT_PUSH)             — push to remote
  - git.push.result      (GIT_PUSH_RESULT)      — push result
  - git.pull             (GIT_PULL)             — pull from remote
  - git.pull.result      (GIT_PULL_RESULT)      — pull result
  - git.branches         (GIT_BRANCHES)         — list branches
  - git.branches.result  (GIT_BRANCHES_RESULT)  — branch list
  - git.checkout         (GIT_CHECKOUT)         — switch branch
  - git.checkout.result  (GIT_CHECKOUT_RESULT)  — checkout result
  - git.log              (GIT_LOG)              — request commit log
  - git.log.result       (GIT_LOG_RESULT)       — commit log
  - git.log.search       (GIT_LOG_SEARCH)       — search commit log
  - git.log.search.result(GIT_LOG_SEARCH_RESULT)— search results
  - git.log.authors      (GIT_LOG_AUTHORS)      — list commit authors
  - git.log.authors.result(GIT_LOG_AUTHORS_RESULT)— author list
  - git.show             (GIT_SHOW)             — show commit details
  - git.show.result      (GIT_SHOW_RESULT)      — commit details
  - git.diff.commit      (GIT_DIFF_COMMIT)      — diff a specific commit file
  - git.diff.commit.result(GIT_DIFF_COMMIT_RESULT)— commit file diff
  - git.discard          (GIT_DISCARD)          — discard file changes
  - git.discard.result   (GIT_DISCARD_RESULT)   — discard result
  - git.repos            (GIT_REPOS)            — discover git repositories
  - git.repos.result     (GIT_REPOS_RESULT)     — repository list
  - git.exec             (GIT_EXEC)             — execute arbitrary git command
  - git.exec.result      (GIT_EXEC_RESULT)      — execution result

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Any, Optional

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


# ── Request payloads (App -> Agent) ──


class GitStatusPayload(PayloadBase):
    """Payload for ``git.status`` — request repo status.

    Attributes:
        repo: Target repository path. Empty = use default/first repo.
    """

    repo: str = ""


class GitStatusAllPayload(PayloadBase):
    """Payload for ``git.status.all`` — request status of all repositories.

    Returns the aggregated status of every discovered repository in
    parallel. Used by the multi-repo aggregated view.
    """

    pass


class GitStatusAllResultPayload(PayloadBase):
    """Payload for ``git.status.all.result`` — all repositories status.

    Attributes:
        repos: List of repository status dicts. Each contains:
            path, name, branch, ahead, behind, staged, unstaged, untracked, error.
    """

    repos: list[dict[str, Any]] = []


class GitDiffPayload(PayloadBase):
    """Payload for ``git.diff`` — request file diff.

    When ``path`` is provided, returns the diff for that specific file.
    Otherwise returns both unstaged and staged diffs for the whole repo.

    Attributes:
        path: File path to diff (empty for whole-repo diff).
        staged: Whether to show staged changes only.
        repo: Target repository path.
    """

    path: str = ""
    staged: bool = False
    repo: str = ""


class GitStagePayload(PayloadBase):
    """Payload for ``git.stage`` — stage files for commit.

    Either provide specific ``paths`` or set ``all`` to stage everything.

    Attributes:
        paths: List of file paths to stage.
        all: Whether to stage all changed files.
        repo: Target repository path (required).
    """

    paths: list[str] = []
    all: bool = False
    repo: str = ""


class GitUnstagePayload(PayloadBase):
    """Payload for ``git.unstage`` — unstage files.

    Either provide specific ``paths`` or set ``all`` to unstage everything.

    Attributes:
        paths: List of file paths to unstage.
        all: Whether to unstage all staged files.
        repo: Target repository path (required).
    """

    paths: list[str] = []
    all: bool = False
    repo: str = ""


class GitCommitPayload(PayloadBase):
    """Payload for ``git.commit`` — create a commit.

    Attributes:
        message: Commit message text.
        repo: Target repository path (required).
        no_verify: Skip pre-commit/commit-msg hooks (user opt-in after failure).
    """

    message: str = ""
    repo: str = ""
    no_verify: bool = False


class GitPushPayload(PayloadBase):
    """Payload for ``git.push`` — push commits to remote.

    Attributes:
        repo: Target repository path (required).
    """

    repo: str = ""


class GitPullPayload(PayloadBase):
    """Payload for ``git.pull`` — pull changes from remote.

    Attributes:
        repo: Target repository path (required).
    """

    repo: str = ""


class GitBranchesPayload(PayloadBase):
    """Payload for ``git.branches`` — list all branches.

    Attributes:
        repo: Target repository path.
    """

    repo: str = ""


class GitCheckoutPayload(PayloadBase):
    """Payload for ``git.checkout`` — switch to a branch.

    Attributes:
        branch: Name of the branch to check out.
        repo: Target repository path (required).
    """

    branch: str = ""
    repo: str = ""


class GitLogPayload(PayloadBase):
    """Payload for ``git.log`` — request commit log.

    Attributes:
        count: Maximum number of commits to return.
        repo: Target repository path.
    """

    count: int = 50
    repo: str = ""


class GitLogSearchPayload(PayloadBase):
    """Payload for ``git.log.search`` — unified log query with filters.

    All parameters are optional. Combines text search, branch/author
    filters, date range, and pagination into a single request.

    Attributes:
        query: Text search string (maps to --grep).
        branch: Branch name filter.
        author: Author name filter (maps to --author).
        since: Start date filter (maps to --since).
        until: End date filter (maps to --until).
        skip: Number of commits to skip (pagination offset).
        count: Maximum number of commits to return.
        repo: Target repository path.
    """

    query: str = ""
    branch: str = ""
    author: str = ""
    since: str = ""
    until: str = ""
    skip: int = 0
    count: int = 50
    repo: str = ""


class GitLogAuthorsPayload(PayloadBase):
    """Payload for ``git.log.authors`` — list unique commit authors.

    Attributes:
        repo: Target repository path.
    """

    repo: str = ""


class GitShowPayload(PayloadBase):
    """Payload for ``git.show`` — show commit details.

    Attributes:
        hash: Commit hash to show.
        repo: Target repository path.
    """

    hash: str = ""
    repo: str = ""


class GitDiffCommitPayload(PayloadBase):
    """Payload for ``git.diff.commit`` — diff a specific commit file.

    Returns old/new file content for a specific commit and file path.

    Attributes:
        hash: Commit hash.
        path: File path within the commit.
        repo: Target repository path.
    """

    hash: str = ""
    path: str = ""
    repo: str = ""


class GitDiscardPayload(PayloadBase):
    """Payload for ``git.discard`` — discard changes to a file.

    Attributes:
        path: File path whose changes should be discarded.
        repo: Target repository path (required).
    """

    path: str = ""
    repo: str = ""


class GitReposPayload(PayloadBase):
    """Payload for ``git.repos`` — discover git repositories.

    Attributes:
        max_depth: Maximum directory depth to scan for repos.
    """

    max_depth: int = 3


class GitExecPayload(PayloadBase):
    """Payload for ``git.exec`` — execute arbitrary git command.

    The Agent performs safety checks before execution. Dangerous
    commands require explicit ``confirmed=True`` from the user.

    Attributes:
        command: Git command string to execute.
        confirmed: Whether the user confirmed a dangerous command.
        repo: Target repository path (required).
    """

    command: str = ""
    confirmed: bool = False
    repo: str = ""


# ── Response payloads (Agent -> App) ──


class GitStatusResultPayload(PayloadBase):
    """Payload for ``git.status.result`` — repository status.

    Contains branch info, staged/unstaged/untracked file lists.
    Uses dict[str, Any] for internal structure since the status
    data varies by repository state.

    Attributes:
        branch: Current branch name.
        staged: List of staged file change dicts.
        unstaged: List of unstaged file change dicts.
        untracked: List of untracked file paths.
        ahead: Number of commits ahead of remote.
        behind: Number of commits behind remote.
        error: Error message if status retrieval failed.
    """

    branch: str = ""
    staged: list[dict[str, Any]] = []
    unstaged: list[dict[str, Any]] = []
    untracked: list[str] = []
    ahead: int = 0
    behind: int = 0
    error: Optional[str] = None


class GitDiffResultPayload(PayloadBase):
    """Payload for ``git.diff.result`` — diff content.

    For single-file diffs, contains the file content fields.
    For whole-repo diffs, contains unstaged and staged diff text.

    Attributes:
        diff: Unstaged diff text (or single-file diff).
        staged: Staged diff text (whole-repo mode).
        old_content: Original file content (single-file mode).
        new_content: Modified file content (single-file mode).
        language: Detected language (single-file mode).
        error: Error message if diff failed.
    """

    diff: str = ""
    staged: str = ""
    old_content: Optional[str] = None
    new_content: Optional[str] = None
    language: Optional[str] = None
    error: Optional[str] = None


class GitStageResultPayload(PayloadBase):
    """Payload for ``git.stage.result`` — stage operation result.

    Attributes:
        success: Whether the stage operation succeeded.
        error: Error message if staging failed.
    """

    success: bool = False
    error: Optional[str] = None


class GitUnstageResultPayload(PayloadBase):
    """Payload for ``git.unstage.result`` — unstage operation result.

    Attributes:
        success: Whether the unstage operation succeeded.
        error: Error message if unstaging failed.
    """

    success: bool = False
    error: Optional[str] = None


class GitCommitResultPayload(PayloadBase):
    """Payload for ``git.commit.result`` — commit operation result.

    Attributes:
        success: Whether the commit succeeded.
        hash: Commit hash of the new commit (on success).
        error: Error message if commit failed.
    """

    success: bool = False
    hash: Optional[str] = None
    error: Optional[str] = None


class GitPushResultPayload(PayloadBase):
    """Payload for ``git.push.result`` — push operation result.

    Attributes:
        success: Whether the push succeeded.
        output: Combined stdout/stderr output from git push.
        up_to_date: Whether the remote was already up-to-date.
        error: Error message if push failed.
    """

    success: bool = False
    output: str = ""
    up_to_date: bool = False
    error: Optional[str] = None


class GitPullResultPayload(PayloadBase):
    """Payload for ``git.pull.result`` — pull operation result.

    Attributes:
        success: Whether the pull succeeded.
        output: Combined stdout/stderr output from git pull.
        up_to_date: Whether the local branch was already up-to-date.
        error: Error message if pull failed.
    """

    success: bool = False
    output: str = ""
    up_to_date: bool = False
    error: Optional[str] = None


class GitBranchesResultPayload(PayloadBase):
    """Payload for ``git.branches.result`` — branch list.

    Attributes:
        branches: List of branch info dicts (name, is_current, etc.).
        current: Name of the current branch.
        error: Error message if listing failed.
    """

    branches: list[dict[str, Any]] = []
    current: str = ""
    error: Optional[str] = None


class GitCheckoutResultPayload(PayloadBase):
    """Payload for ``git.checkout.result`` — checkout operation result.

    Attributes:
        success: Whether the checkout succeeded.
        error: Error message if checkout failed.
    """

    success: bool = False
    error: Optional[str] = None


class GitLogResultPayload(PayloadBase):
    """Payload for ``git.log.result`` — commit log.

    Attributes:
        entries: List of commit info dicts (GitLogEntry serialized).
        has_more: Whether more commits are available (pagination).
        error: Error message if log retrieval failed.
    """

    entries: list[dict[str, Any]] = []
    has_more: bool = False
    error: Optional[str] = None


class GitLogSearchResultPayload(PayloadBase):
    """Payload for ``git.log.search.result`` — log search results.

    Attributes:
        entries: List of matching commit info dicts (GitLogEntry serialized).
        has_more: Whether more results are available (pagination).
        query: The original search query string.
        error: Error message if search failed.
    """

    entries: list[dict[str, Any]] = []
    has_more: bool = False
    query: str = ""
    error: Optional[str] = None


class GitLogAuthorsResultPayload(PayloadBase):
    """Payload for ``git.log.authors.result`` — unique author list.

    Attributes:
        authors: List of unique author name strings.
    """

    authors: list[str] = []


class GitShowResultPayload(PayloadBase):
    """Payload for ``git.show.result`` — commit details.

    Contains commit metadata and list of changed files.
    Uses dict[str, Any] since the structure varies.

    Attributes:
        hash: Commit hash.
        short_hash: Abbreviated commit hash.
        author: Author name.
        date: Commit date string.
        message: Short commit message (subject line).
        full_message: Full commit message including body.
        files: List of changed file dicts.
        error: Error message if show failed.
    """

    hash: str = ""
    short_hash: str = ""
    author: str = ""
    date: str = ""
    message: str = ""
    full_message: str = ""
    files: list[dict[str, Any]] = []
    error: Optional[str] = None


class GitDiffCommitResultPayload(PayloadBase):
    """Payload for ``git.diff.commit.result`` — commit file diff.

    Returns old/new content for a specific file in a commit.

    Attributes:
        old_content: File content before the commit.
        new_content: File content after the commit.
        language: Detected programming language.
        error: Error message if diff failed.
    """

    old_content: str = ""
    new_content: str = ""
    language: str = ""
    error: Optional[str] = None


class GitDiscardResultPayload(PayloadBase):
    """Payload for ``git.discard.result`` — discard operation result.

    Attributes:
        success: Whether the discard succeeded.
        error: Error message if discard failed.
    """

    success: bool = False
    error: Optional[str] = None


class GitReposResultPayload(PayloadBase):
    """Payload for ``git.repos.result`` — discovered repository list.

    Attributes:
        repos: List of repository info dicts (path, name, is_current).
    """

    repos: list[dict[str, Any]] = []


class GitExecResultPayload(PayloadBase):
    """Payload for ``git.exec.result`` — git command execution result.

    Attributes:
        success: Whether the command executed successfully.
        output: Command stdout output.
        stdout: Command stdout (alias used by some code paths).
        stderr: Command stderr output.
        command: The command that was executed.
        blocked: Whether the command was blocked by safety checks.
        reason: Reason the command was blocked.
        dangerous: Whether the command was flagged as dangerous.
        error: Error message if execution failed.
    """

    success: bool = False
    output: str = ""
    stdout: str = ""
    stderr: str = ""
    command: str = ""
    blocked: bool = False
    reason: str = ""
    dangerous: bool = False
    error: Optional[str] = None


# ── Merge Conflict Resolution Payloads ──


class GitConflictsPayload(PayloadBase):
    """Payload for ``git.conflicts`` — request conflict blocks for a file.

    Attributes:
        repo: Target repository path.
        path: Relative file path to parse conflicts from.
    """

    repo: str = ""
    path: str = ""


class GitConflictsResultPayload(PayloadBase):
    """Payload for ``git.conflicts.result`` — conflict blocks list.

    Attributes:
        repo: Repository path.
        path: File path.
        conflicts: List of conflict block dicts (id, current_*, incoming_*, range_*).
        count: Total number of conflicts in the file.
        error: Error message (empty on success).
    """

    repo: str = ""
    path: str = ""
    conflicts: list[dict[str, Any]] = []
    count: int = 0
    error: str = ""


class GitConflictResolvePayload(PayloadBase):
    """Payload for ``git.conflict.resolve`` — resolve a single conflict block.

    Attributes:
        repo: Target repository path.
        path: Relative file path.
        conflict_id: 0-based index of the conflict to resolve.
        resolution: Resolution strategy — "current", "incoming", or "both".
    """

    repo: str = ""
    path: str = ""
    conflict_id: int = 0
    resolution: str = ""


class GitConflictResolveResultPayload(PayloadBase):
    """Payload for ``git.conflict.resolve.result`` — single resolve result.

    Attributes:
        repo: Repository path.
        path: File path.
        success: Whether the resolution succeeded.
        remaining: Updated conflict list after resolution (recalculated IDs).
        remaining_count: Number of remaining unresolved conflicts.
        error: Error message (empty on success).
    """

    repo: str = ""
    path: str = ""
    success: bool = False
    remaining: list[dict[str, Any]] = []
    remaining_count: int = 0
    error: str = ""


class GitConflictResolveAllPayload(PayloadBase):
    """Payload for ``git.conflict.resolve.all`` — resolve all conflicts in file.

    Attributes:
        repo: Target repository path.
        path: Relative file path.
        resolution: Resolution strategy — "current", "incoming", or "both".
    """

    repo: str = ""
    path: str = ""
    resolution: str = ""


class GitConflictResolveAllResultPayload(PayloadBase):
    """Payload for ``git.conflict.resolve.all.result`` — batch resolve result.

    Attributes:
        repo: Repository path.
        path: File path.
        success: Whether all resolutions succeeded.
        resolved_count: Number of conflicts resolved.
        error: Error message (empty on success).
    """

    repo: str = ""
    path: str = ""
    success: bool = False
    resolved_count: int = 0
    error: str = ""


class GitMergeAbortPayload(PayloadBase):
    """Payload for ``git.merge.abort`` — abort current merge operation.

    Attributes:
        repo: Target repository path.
    """

    repo: str = ""


class GitMergeAbortResultPayload(PayloadBase):
    """Payload for ``git.merge.abort.result`` — abort result.

    Attributes:
        repo: Repository path.
        success: Whether the abort succeeded.
        error: Error message (empty on success).
    """

    repo: str = ""
    success: bool = False
    error: str = ""


class GitUndoCommitPayload(PayloadBase):
    """Payload for ``git.undo.commit`` — undo/reset commit(s) via git reset.

    Attributes:
        repo: Target repository path.
        mode: Reset mode — "soft", "mixed", or "hard".
        target: Reset target — defaults to "HEAD~1" (undo last commit).
            Can be a commit hash to reset the branch to that commit.
    """

    repo: str = ""
    mode: str = "soft"
    target: str = "HEAD~1"


class GitUndoCommitResultPayload(PayloadBase):
    """Payload for ``git.undo.commit.result`` — undo/reset result.

    Attributes:
        repo: Repository path.
        success: Whether the reset succeeded.
        message: The undone commit's message (for pre-filling input).
        commits_reset: Number of commits that were reset (0 if failed).
        error: Error message (empty on success).
    """

    repo: str = ""
    success: bool = False
    message: str = ""
    commits_reset: int = 0
    error: str = ""


class GitRevertCommitPayload(PayloadBase):
    """Payload for ``git.revert.commit`` — revert a commit.

    Attributes:
        repo: Target repository path.
        hash: Commit hash to revert.
        no_commit: If True, stage revert changes without auto-committing.
    """

    repo: str = ""
    hash: str = ""
    no_commit: bool = False


class GitRevertCommitResultPayload(PayloadBase):
    """Payload for ``git.revert.commit.result`` — revert result.

    Attributes:
        repo: Repository path.
        success: Whether the revert succeeded.
        has_conflicts: Whether revert produced merge conflicts.
        error: Error message (empty on success).
    """

    repo: str = ""
    success: bool = False
    has_conflicts: bool = False
    error: str = ""


class GitCherryPickPayload(PayloadBase):
    """Payload for ``git.cherry.pick`` — cherry-pick a commit.

    Attributes:
        repo: Target repository path.
        hash: Commit hash to cherry-pick.
        no_commit: If True, apply changes to staging area without auto-committing.
    """

    repo: str = ""
    hash: str = ""
    no_commit: bool = False


class GitCherryPickResultPayload(PayloadBase):
    """Payload for ``git.cherry.pick.result`` — cherry-pick result.

    Attributes:
        repo: Repository path.
        success: Whether the cherry-pick succeeded.
        has_conflicts: Whether cherry-pick produced merge conflicts.
        error: Error message (empty on success).
    """

    repo: str = ""
    success: bool = False
    has_conflicts: bool = False
    error: str = ""


class GitSequencerContinuePayload(PayloadBase):
    """Payload for ``git.sequencer.continue``."""

    repo: str = ""


class GitSequencerContinueResultPayload(PayloadBase):
    """Payload for ``git.sequencer.continue.result``.

    Attributes:
        repo: Repository path.
        success: Whether the continue operation succeeded.
        operation: The sequencer operation type ('cherry-pick' or 'revert').
        error: Error message (empty on success).
    """

    repo: str = ""
    success: bool = False
    operation: str = ""
    error: str = ""


class GitSequencerAbortPayload(PayloadBase):
    """Payload for ``git.sequencer.abort``."""

    repo: str = ""


class GitSequencerAbortResultPayload(PayloadBase):
    """Payload for ``git.sequencer.abort.result``.

    Attributes:
        repo: Repository path.
        success: Whether the abort operation succeeded.
        operation: The sequencer operation type ('cherry-pick' or 'revert').
        error: Error message (empty on success).
    """

    repo: str = ""
    success: bool = False
    operation: str = ""
    error: str = ""


class GitSequencerSkipPayload(PayloadBase):
    """Payload for ``git.sequencer.skip``."""

    repo: str = ""


class GitSequencerSkipResultPayload(PayloadBase):
    """Payload for ``git.sequencer.skip.result``.

    Attributes:
        repo: Repository path.
        success: Whether the skip operation succeeded.
        operation: The sequencer operation type ('cherry-pick' or 'revert').
        error: Error message (empty on success).
    """

    repo: str = ""
    success: bool = False
    operation: str = ""
    error: str = ""


# ── Registry wiring ──
# Register all git payload models so Message.typed_payload() and
# get_payload_class() can resolve them by MessageType.

register_payload(MessageType.GIT_STATUS, GitStatusPayload)
register_payload(MessageType.GIT_STATUS_RESULT, GitStatusResultPayload)
register_payload(MessageType.GIT_STATUS_ALL, GitStatusAllPayload)
register_payload(MessageType.GIT_STATUS_ALL_RESULT, GitStatusAllResultPayload)
register_payload(MessageType.GIT_DIFF, GitDiffPayload)
register_payload(MessageType.GIT_DIFF_RESULT, GitDiffResultPayload)
register_payload(MessageType.GIT_STAGE, GitStagePayload)
register_payload(MessageType.GIT_STAGE_RESULT, GitStageResultPayload)
register_payload(MessageType.GIT_UNSTAGE, GitUnstagePayload)
register_payload(MessageType.GIT_UNSTAGE_RESULT, GitUnstageResultPayload)
register_payload(MessageType.GIT_COMMIT, GitCommitPayload)
register_payload(MessageType.GIT_COMMIT_RESULT, GitCommitResultPayload)
register_payload(MessageType.GIT_PUSH, GitPushPayload)
register_payload(MessageType.GIT_PUSH_RESULT, GitPushResultPayload)
register_payload(MessageType.GIT_PULL, GitPullPayload)
register_payload(MessageType.GIT_PULL_RESULT, GitPullResultPayload)
register_payload(MessageType.GIT_BRANCHES, GitBranchesPayload)
register_payload(MessageType.GIT_BRANCHES_RESULT, GitBranchesResultPayload)
register_payload(MessageType.GIT_CHECKOUT, GitCheckoutPayload)
register_payload(MessageType.GIT_CHECKOUT_RESULT, GitCheckoutResultPayload)
register_payload(MessageType.GIT_LOG, GitLogPayload)
register_payload(MessageType.GIT_LOG_RESULT, GitLogResultPayload)
register_payload(MessageType.GIT_LOG_SEARCH, GitLogSearchPayload)
register_payload(MessageType.GIT_LOG_SEARCH_RESULT, GitLogSearchResultPayload)
register_payload(MessageType.GIT_LOG_AUTHORS, GitLogAuthorsPayload)
register_payload(MessageType.GIT_LOG_AUTHORS_RESULT, GitLogAuthorsResultPayload)
register_payload(MessageType.GIT_SHOW, GitShowPayload)
register_payload(MessageType.GIT_SHOW_RESULT, GitShowResultPayload)
register_payload(MessageType.GIT_DIFF_COMMIT, GitDiffCommitPayload)
register_payload(MessageType.GIT_DIFF_COMMIT_RESULT, GitDiffCommitResultPayload)
register_payload(MessageType.GIT_DISCARD, GitDiscardPayload)
register_payload(MessageType.GIT_DISCARD_RESULT, GitDiscardResultPayload)
register_payload(MessageType.GIT_REPOS, GitReposPayload)
register_payload(MessageType.GIT_REPOS_RESULT, GitReposResultPayload)
register_payload(MessageType.GIT_EXEC, GitExecPayload)
register_payload(MessageType.GIT_EXEC_RESULT, GitExecResultPayload)

# Merge conflict resolution payloads
register_payload(MessageType.GIT_CONFLICTS, GitConflictsPayload)
register_payload(MessageType.GIT_CONFLICTS_RESULT, GitConflictsResultPayload)
register_payload(MessageType.GIT_CONFLICT_RESOLVE, GitConflictResolvePayload)
register_payload(MessageType.GIT_CONFLICT_RESOLVE_RESULT, GitConflictResolveResultPayload)
register_payload(MessageType.GIT_CONFLICT_RESOLVE_ALL, GitConflictResolveAllPayload)
register_payload(MessageType.GIT_CONFLICT_RESOLVE_ALL_RESULT, GitConflictResolveAllResultPayload)
register_payload(MessageType.GIT_MERGE_ABORT, GitMergeAbortPayload)
register_payload(MessageType.GIT_MERGE_ABORT_RESULT, GitMergeAbortResultPayload)
register_payload(MessageType.GIT_UNDO_COMMIT, GitUndoCommitPayload)
register_payload(MessageType.GIT_UNDO_COMMIT_RESULT, GitUndoCommitResultPayload)
register_payload(MessageType.GIT_REVERT_COMMIT, GitRevertCommitPayload)
register_payload(MessageType.GIT_REVERT_COMMIT_RESULT, GitRevertCommitResultPayload)
register_payload(MessageType.GIT_CHERRY_PICK, GitCherryPickPayload)
register_payload(MessageType.GIT_CHERRY_PICK_RESULT, GitCherryPickResultPayload)
register_payload(MessageType.GIT_SEQUENCER_CONTINUE, GitSequencerContinuePayload)
register_payload(MessageType.GIT_SEQUENCER_CONTINUE_RESULT, GitSequencerContinueResultPayload)
register_payload(MessageType.GIT_SEQUENCER_ABORT, GitSequencerAbortPayload)
register_payload(MessageType.GIT_SEQUENCER_ABORT_RESULT, GitSequencerAbortResultPayload)
register_payload(MessageType.GIT_SEQUENCER_SKIP, GitSequencerSkipPayload)
register_payload(MessageType.GIT_SEQUENCER_SKIP_RESULT, GitSequencerSkipResultPayload)
