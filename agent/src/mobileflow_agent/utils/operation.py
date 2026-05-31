"""Operation manager — tracks all in-flight git/file operations.

Module: utils/
Responsibility:
    Each operation has metadata (blocking, read_only, remote, retry) that
    controls refresh behavior and UI feedback. The OperationManager tracks
    all in-flight operations and exposes queries like is_idle() and
    should_block().

    Key concept: is_idle() returns True when no WRITE operations are running.
    File change events should only trigger refresh when idle, because a
    running write operation will trigger its own refresh when it completes.

Used by:
    - services/git_state.py (run() registers/unregisters operations)
    - services/refresh_scheduler.py (checks is_idle() before scheduling)
    - server/websocket.py (checks should_show_progress() for UI feedback)
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from loguru import logger


class OpKind(str, Enum):
    """All known operation types.

    Grouped by domain: git read, git write, file, session.
    """

    # Git read operations (read_only=True, don't trigger refresh)
    STATUS = "Status"
    LOG = "Log"
    DIFF = "Diff"
    DIFF_FILE = "DiffFile"
    BRANCHES = "Branches"
    DISCOVER_REPOS = "DiscoverRepos"

    # Git write operations (trigger refresh after completion)
    COMMIT = "Commit"
    STAGE = "Stage"
    UNSTAGE = "Unstage"
    PUSH = "Push"
    PULL = "Pull"
    FETCH = "Fetch"
    CHECKOUT = "Checkout"
    BRANCH_CREATE = "BranchCreate"
    BRANCH_DELETE = "BranchDelete"
    MERGE = "Merge"
    REBASE = "Rebase"
    DISCARD = "Discard"
    STAGE_ALL = "StageAll"
    UNSTAGE_ALL = "UnstageAll"
    GIT_COMMAND = "GitCommand"

    # State management
    REFRESH = "Refresh"

    # File operations
    FILE_TREE = "FileTree"
    FILE_READ = "FileRead"
    FILE_WRITE = "FileWrite"
    FILE_CREATE = "FileCreate"
    FILE_DELETE = "FileDelete"
    FILE_RENAME = "FileRename"
    FILE_SEARCH = "FileSearch"


@dataclass(frozen=True)
class Operation:
    """Operation descriptor with metadata.

    Attributes:
        kind: Operation type identifier.
        blocking: If True, blocks other operations from starting.
            Used for operations that modify the repository state
            significantly (commit, checkout, pull, push).
        read_only: If True, does NOT trigger state refresh after
            completion. Used for queries (diff, log, show).
        remote: If True, involves network I/O (fetch, pull, push).
        retry: If True, can be retried on lock conflicts.
        show_progress: If True, App shows a progress indicator.
    """

    kind: OpKind
    blocking: bool = False
    read_only: bool = False
    remote: bool = False
    retry: bool = False
    show_progress: bool = True


class Op:
    """Pre-defined Operation instances for common operations.

    Usage::

        await git_state.run(Op.Commit, lambda: git.commit(msg))
        await git_state.run(Op.Diff, lambda: git.diff_file(path))
    """

    # ── Git read (read_only=True) ──
    Status = Operation(OpKind.STATUS, show_progress=True)
    Log = Operation(OpKind.LOG, read_only=True, show_progress=False)
    Diff = Operation(OpKind.DIFF, read_only=True, show_progress=False)
    DiffFile = Operation(OpKind.DIFF_FILE, read_only=True, show_progress=False)
    Branches = Operation(OpKind.BRANCHES, read_only=True, show_progress=False)
    DiscoverRepos = Operation(
        OpKind.DISCOVER_REPOS, read_only=True, show_progress=True
    )

    # ── Git write (trigger refresh) ──
    Commit = Operation(OpKind.COMMIT, blocking=True, show_progress=True)
    Stage = Operation(OpKind.STAGE, show_progress=True)
    Unstage = Operation(OpKind.UNSTAGE, show_progress=True)
    StageAll = Operation(OpKind.STAGE_ALL, show_progress=True)
    UnstageAll = Operation(OpKind.UNSTAGE_ALL, show_progress=True)
    Push = Operation(
        OpKind.PUSH, blocking=True, remote=True, show_progress=True
    )
    Pull = Operation(
        OpKind.PULL, blocking=True, remote=True, retry=True, show_progress=True
    )
    Fetch = Operation(
        OpKind.FETCH, remote=True, retry=True, show_progress=True
    )
    Checkout = Operation(OpKind.CHECKOUT, blocking=True, show_progress=True)
    BranchCreate = Operation(OpKind.BRANCH_CREATE, show_progress=True)
    BranchDelete = Operation(OpKind.BRANCH_DELETE, show_progress=True)
    Merge = Operation(OpKind.MERGE, blocking=True, show_progress=True)
    Rebase = Operation(OpKind.REBASE, blocking=True, show_progress=True)
    Discard = Operation(OpKind.DISCARD, show_progress=True)
    GitCommand = Operation(OpKind.GIT_COMMAND, show_progress=True)

    # ── State management ──
    Refresh = Operation(OpKind.REFRESH, show_progress=True)

    # ── File operations ──
    FileTree = Operation(OpKind.FILE_TREE, read_only=True, show_progress=False)
    FileRead = Operation(OpKind.FILE_READ, read_only=True, show_progress=False)
    FileWrite = Operation(OpKind.FILE_WRITE, show_progress=False)
    FileCreate = Operation(OpKind.FILE_CREATE, show_progress=False)
    FileDelete = Operation(OpKind.FILE_DELETE, show_progress=False)
    FileRename = Operation(OpKind.FILE_RENAME, show_progress=False)
    FileSearch = Operation(
        OpKind.FILE_SEARCH, read_only=True, show_progress=False
    )


class OperationManager:
    """Tracks all in-flight operations.

    Thread-safe within asyncio (single-threaded event loop).
    Operations are tracked by kind, allowing multiple concurrent
    operations of the same kind (e.g. multiple parallel diff requests).

    Key methods:
        - is_idle(): True when no write operations are running.
          Used by RefreshScheduler to decide whether to trigger refresh.
        - should_block(): True when a blocking operation is running.
          Used to reject new blocking operations.
        - should_show_progress(): True when any progress-worthy operation
          is running. Used by App to show spinner.
    """

    def __init__(self) -> None:
        self._operations: dict[OpKind, set[int]] = {}
        self._op_map: dict[int, Operation] = {}
        self._counter = 0

    def start(self, op: Operation) -> int:
        """Register an operation as in-flight.

        Args:
            op: Operation descriptor.

        Returns:
            Unique operation ID (used to end the operation later).
        """
        self._counter += 1
        op_id = self._counter
        self._op_map[op_id] = op
        self._operations.setdefault(op.kind, set()).add(op_id)
        logger.debug(
            f"[OperationManager] start: {op.kind.value} "
            f"(id={op_id}, blocking={op.blocking}, "
            f"read_only={op.read_only})"
        )
        return op_id

    def end(self, op_id: int) -> None:
        """Unregister an operation.

        Args:
            op_id: The ID returned by start().
        """
        op = self._op_map.pop(op_id, None)
        if op is None:
            return
        ops = self._operations.get(op.kind)
        if ops:
            ops.discard(op_id)
            if not ops:
                del self._operations[op.kind]
        logger.debug(f"[OperationManager] end: {op.kind.value} (id={op_id})")

    def is_idle(self) -> bool:
        """True when no write (non-read_only) operations are running.

        File change events should only trigger refresh when idle,
        because a running write operation will trigger its own refresh
        via run() when it completes.

        Returns:
            True if all running operations are read_only.
        """
        for op in self._op_map.values():
            if not op.read_only:
                return False
        return True

    def is_running(self, kind: OpKind) -> bool:
        """Check if any operation of the given kind is running.

        Args:
            kind: Operation kind to check.

        Returns:
            True if at least one operation of this kind is in-flight.
        """
        return kind in self._operations and len(self._operations[kind]) > 0

    def should_show_progress(self) -> bool:
        """True if any operation with show_progress=True is running."""
        for op in self._op_map.values():
            if op.show_progress:
                return True
        return False

    def should_block(self) -> bool:
        """True if any blocking operation is running.

        Used to reject new blocking operations (e.g. can't checkout
        while a commit is in progress).
        """
        for op in self._op_map.values():
            if op.blocking:
                return True
        return False

    @property
    def active_count(self) -> int:
        """Number of currently in-flight operations."""
        return len(self._op_map)
