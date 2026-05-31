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
  - git.switch_repo      (GIT_SWITCH_REPO)      — switch active repository
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

    Sent by the App to request the current Git status. No fields
    required; the Agent uses the active working directory.
    """

    pass


class GitDiffPayload(PayloadBase):
    """Payload for ``git.diff`` — request file diff.

    When ``path`` is provided, returns the diff for that specific file.
    Otherwise returns both unstaged and staged diffs for the whole repo.

    Attributes:
        path: File path to diff (empty for whole-repo diff).
        staged: Whether to show staged changes only.
    """

    path: str = ""
    staged: bool = False


class GitStagePayload(PayloadBase):
    """Payload for ``git.stage`` — stage files for commit.

    Either provide specific ``paths`` or set ``all`` to stage everything.

    Attributes:
        paths: List of file paths to stage.
        all: Whether to stage all changed files.
    """

    paths: list[str] = []
    all: bool = False


class GitUnstagePayload(PayloadBase):
    """Payload for ``git.unstage`` — unstage files.

    Either provide specific ``paths`` or set ``all`` to unstage everything.

    Attributes:
        paths: List of file paths to unstage.
        all: Whether to unstage all staged files.
    """

    paths: list[str] = []
    all: bool = False


class GitCommitPayload(PayloadBase):
    """Payload for ``git.commit`` — create a commit.

    Attributes:
        message: Commit message text.
    """

    message: str = ""


class GitPushPayload(PayloadBase):
    """Payload for ``git.push`` — push commits to remote.

    No fields required; the Agent pushes the current branch.
    """

    pass


class GitPullPayload(PayloadBase):
    """Payload for ``git.pull`` — pull changes from remote.

    No fields required; the Agent pulls the current branch.
    """

    pass


class GitBranchesPayload(PayloadBase):
    """Payload for ``git.branches`` — list all branches.

    No fields required; the Agent returns all local and remote branches.
    """

    pass


class GitCheckoutPayload(PayloadBase):
    """Payload for ``git.checkout`` — switch to a branch.

    Attributes:
        branch: Name of the branch to check out.
    """

    branch: str = ""


class GitLogPayload(PayloadBase):
    """Payload for ``git.log`` — request commit log.

    Attributes:
        count: Maximum number of commits to return.
    """

    count: int = 50


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
    """

    query: str = ""
    branch: str = ""
    author: str = ""
    since: str = ""
    until: str = ""
    skip: int = 0
    count: int = 50


class GitLogAuthorsPayload(PayloadBase):
    """Payload for ``git.log.authors`` — list unique commit authors.

    No fields required; the Agent scans the log for unique authors.
    """

    pass


class GitShowPayload(PayloadBase):
    """Payload for ``git.show`` — show commit details.

    Attributes:
        hash: Commit hash to show.
    """

    hash: str = ""


class GitDiffCommitPayload(PayloadBase):
    """Payload for ``git.diff.commit`` — diff a specific commit file.

    Returns old/new file content for a specific commit and file path.

    Attributes:
        hash: Commit hash.
        path: File path within the commit.
    """

    hash: str = ""
    path: str = ""


class GitDiscardPayload(PayloadBase):
    """Payload for ``git.discard`` — discard changes to a file.

    Attributes:
        path: File path whose changes should be discarded.
    """

    path: str = ""


class GitReposPayload(PayloadBase):
    """Payload for ``git.repos`` — discover git repositories.

    Attributes:
        max_depth: Maximum directory depth to scan for repos.
    """

    max_depth: int = 3


class GitSwitchRepoPayload(PayloadBase):
    """Payload for ``git.switch_repo`` — switch active repository.

    Attributes:
        path: Repository root path to switch to.
    """

    path: str = ""


class GitExecPayload(PayloadBase):
    """Payload for ``git.exec`` — execute arbitrary git command.

    The Agent performs safety checks before execution. Dangerous
    commands require explicit ``confirmed=True`` from the user.

    Attributes:
        command: Git command string to execute.
        confirmed: Whether the user confirmed a dangerous command.
    """

    command: str = ""
    confirmed: bool = False


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


# ── Registry wiring ──
# Register all git payload models so Message.typed_payload() and
# get_payload_class() can resolve them by MessageType.

register_payload(MessageType.GIT_STATUS, GitStatusPayload)
register_payload(MessageType.GIT_STATUS_RESULT, GitStatusResultPayload)
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
register_payload(MessageType.GIT_SWITCH_REPO, GitSwitchRepoPayload)
register_payload(MessageType.GIT_EXEC, GitExecPayload)
register_payload(MessageType.GIT_EXEC_RESULT, GitExecResultPayload)
