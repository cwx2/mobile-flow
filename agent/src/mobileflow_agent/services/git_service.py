"""Git operations service (modelled after JetBrains IDE Git integration).

Module: services/
Responsibility:
    Wraps all git command operations and returns structured results.
    Uses subprocess to invoke the system ``git`` binary (same approach as
    VS Code's built-in Git extension).

Called by:
    - server/handlers/git_handler.py

Supported operations:
    status, diff, stage/unstage, commit, push/pull, branch management,
    log, discard, repository discovery, merge conflict resolution,
    and safe command execution.
"""

from __future__ import annotations

import asyncio
import os
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from loguru import logger

from ..utils.encoding import decode_process_output
from ..utils.i18n import t


# ══════════════════════════════════════════════════════════════════════
# Merge Conflict Data Models & Parser
# ══════════════════════════════════════════════════════════════════════
#
# Architecture mirrors VS Code's merge-conflict extension:
#   - mergeConflictParser.ts → parse_conflicts()
#   - interfaces.ts IMergeRegion → ConflictRegion
#   - interfaces.ts IDocumentMergeConflictDescriptor → ConflictBlock
#   - documentMergeConflict.ts applyEdit() → apply_resolution()

# Marker constants (same as VS Code mergeConflictParser.ts)
_START_MARKER = "<<<<<<<"
_ANCESTOR_MARKER = "|||||||"
_SPLITTER_MARKER = "======="
_END_MARKER = ">>>>>>>"


@dataclass
class ConflictRegion:
    """One side of a merge conflict (current or incoming).

    Corresponds to VS Code's IMergeRegion. Stores the branch label
    (extracted from the marker line) and the actual content text
    between markers.

    Attributes:
        label: Branch name from marker (e.g. "HEAD", "feature/auth").
        content: Code text between markers (excludes marker lines).
        start_line: 0-based line number where content begins.
        end_line: 0-based line number where content ends (exclusive).
    """
    label: str
    content: str
    start_line: int
    end_line: int

    def to_dict(self) -> dict:
        """Serialise to a JSON-compatible dict."""
        return {
            "label": self.label,
            "content": self.content,
            "start_line": self.start_line,
            "end_line": self.end_line,
        }


@dataclass
class ConflictBlock:
    """A single merge conflict within a file.

    Corresponds to VS Code's IDocumentMergeConflictDescriptor:
    - range → (range_start, range_end): entire conflict including markers
    - current → our version (between <<<<<<< and =======)
    - incoming → their version (between ======= and >>>>>>>)
    - splitter → implicit (line of =======)
    - commonAncestors → skipped (diff3 mode, not supported in MVP)

    Attributes:
        id: Sequential index within the file (0-based).
        current: "Ours" region — code between <<<<<<< and =======.
        incoming: "Theirs" region — code between ======= and >>>>>>>.
        range_start: Line number of <<<<<<< marker (0-based).
        range_end: Line number of >>>>>>> marker (0-based, inclusive).
    """
    id: int
    current: ConflictRegion
    incoming: ConflictRegion
    range_start: int
    range_end: int

    def to_dict(self) -> dict:
        """Serialise to a JSON-compatible dict."""
        return {
            "id": self.id,
            "current_label": self.current.label,
            "current_content": self.current.content,
            "incoming_label": self.incoming.label,
            "incoming_content": self.incoming.content,
            "range_start": self.range_start,
            "range_end": self.range_end,
        }


def parse_conflicts(content: str) -> list[ConflictBlock]:
    """Parse merge conflict markers from file content.

    Implements the same state-machine approach as VS Code's
    MergeConflictParser.scanDocument():

    1. Track a current_conflict state (None or in-progress scan).
    2. line.startsWith('<<<<<<<') → start new conflict.
       - If already tracking a conflict → malformed file, break entirely.
    3. line.startsWith('|||||||') → skip (diff3 common ancestor block).
    4. line == '=======' → exact match, record splitter position.
    5. line.startsWith('>>>>>>>') → complete the conflict descriptor.
    6. Build ConflictBlock from collected line ranges.

    Args:
        content: Full file content as a string.

    Returns:
        List of ConflictBlock objects. Empty if no valid conflicts found
        or if the file contains malformed markers.
    """
    lines = content.split("\n")
    # Remove trailing empty element from split (file ending with newline)
    if lines and lines[-1] == "":
        lines = lines[:-1]

    conflicts: list[ConflictBlock] = []

    # State machine variables (mirrors VS Code's IScanMergedConflict)
    in_conflict = False
    start_line = -1
    start_label = ""
    splitter_line = -1
    in_ancestor = False  # True when inside |||||||...======= block

    for i, line in enumerate(lines):
        # Start marker: <<<<<<<
        if line.startswith(_START_MARKER):
            if in_conflict:
                # Malformed: nested start marker. VS Code breaks here.
                logger.warning(
                    f"冲突解析: 嵌套 <<<<<<< 标记 (line {i}), 停止解析"
                )
                break

            in_conflict = True
            start_line = i
            # Extract label after marker (e.g. "<<<<<<< HEAD" → "HEAD")
            start_label = line[len(_START_MARKER):].strip()
            splitter_line = -1
            in_ancestor = False
            continue

        if not in_conflict:
            continue

        # Common ancestor marker: ||||||| (diff3 mode, skip content)
        if line.startswith(_ANCESTOR_MARKER) and splitter_line == -1:
            in_ancestor = True
            continue

        # Splitter: ======= (must be exact match for the line content)
        if line == _SPLITTER_MARKER and splitter_line == -1:
            splitter_line = i
            in_ancestor = False
            continue

        # End marker: >>>>>>>
        if line.startswith(_END_MARKER):
            if splitter_line == -1:
                # No splitter found — malformed conflict, skip it
                in_conflict = False
                continue

            end_label = line[len(_END_MARKER):].strip()

            # Build current region: lines between start marker and splitter
            # (excluding ancestor block if present)
            current_start = start_line + 1
            current_end = splitter_line  # exclusive
            current_lines = []
            # Collect lines for current, skipping ancestor blocks
            temp_in_ancestor = False
            for j in range(current_start, current_end):
                if lines[j].startswith(_ANCESTOR_MARKER):
                    temp_in_ancestor = True
                    continue
                if temp_in_ancestor:
                    # Skip all ancestor content until splitter
                    continue
                current_lines.append(lines[j])
            current_content = "\n".join(current_lines)
            if current_lines:
                current_content += "\n"

            # Build incoming region: lines between splitter and end marker
            incoming_start = splitter_line + 1
            incoming_end = i  # exclusive
            incoming_lines = lines[incoming_start:incoming_end]
            incoming_content = "\n".join(incoming_lines)
            if incoming_lines:
                incoming_content += "\n"

            conflicts.append(ConflictBlock(
                id=len(conflicts),
                current=ConflictRegion(
                    label=start_label,
                    content=current_content,
                    start_line=current_start,
                    end_line=current_end,
                ),
                incoming=ConflictRegion(
                    label=end_label,
                    content=incoming_content,
                    start_line=incoming_start,
                    end_line=incoming_end,
                ),
                range_start=start_line,
                range_end=i,
            ))

            # Reset state for next conflict
            in_conflict = False
            start_line = -1
            splitter_line = -1

    return conflicts


def apply_resolution(content: str, conflict: ConflictBlock, resolution: str) -> str:
    """Replace a single conflict block with the chosen content.

    Mirrors VS Code's DocumentMergeConflict.applyEdit():
    - "current": replace entire conflict range with current.content
    - "incoming": replace entire conflict range with incoming.content
    - "both": replace with current.content + incoming.content (concatenated)

    VS Code special case: if the resolved content is newline-only
    ('\\n' or '\\r\\n'), the range is replaced with empty string.

    Args:
        content: Full file content.
        conflict: The ConflictBlock to resolve.
        resolution: One of "current", "incoming", "both".

    Returns:
        Updated file content with the conflict markers removed and
        the chosen content in place.

    Raises:
        ValueError: If resolution is not one of the valid values.
    """
    if resolution not in ("current", "incoming", "both"):
        raise ValueError(f"Invalid resolution: {resolution!r}")

    lines = content.split("\n")

    # Determine replacement content
    if resolution == "current":
        replacement = conflict.current.content
    elif resolution == "incoming":
        replacement = conflict.incoming.content
    else:  # both
        replacement = conflict.current.content + conflict.incoming.content

    # VS Code behavior: newline-only content → empty string
    if replacement in ("\n", "\r\n"):
        replacement = ""

    # Split replacement into lines for insertion
    # Remove trailing newline before splitting (we handle line joins)
    if replacement.endswith("\n"):
        replacement = replacement[:-1]
    replacement_lines = replacement.split("\n") if replacement else []

    # Replace the conflict range (range_start to range_end inclusive)
    new_lines = lines[:conflict.range_start] + replacement_lines + lines[conflict.range_end + 1:]

    return "\n".join(new_lines)


@dataclass
class GitFileStatus:
    """Status of a single file in the working tree.

    Attributes:
        path: Relative file path.
        status: Status code — M(odified), A(dded), D(eleted), R(enamed), ?(untracked).
        staged: Whether the change is staged for commit.
        old_path: Previous path (only set for renames).
    """
    path: str
    status: str
    staged: bool
    old_path: str = ""

    def to_dict(self) -> dict:
        """Serialise to a JSON-compatible dict."""
        return {
            "path": self.path,
            "status": self.status,
            "staged": self.staged,
            "old_path": self.old_path,
        }


@dataclass
@dataclass
class GitBranch:
    """Branch metadata with last commit info.

    Attributes:
        name: Branch name (without ``remotes/`` prefix for remote branches).
        current: Whether this is the currently checked-out branch.
        remote: Whether this is a remote-tracking branch.
        ref_type: Type of ref — "branch", "remote", or "tag".
        hash: Short commit hash of the branch tip.
        message: First line of the branch tip commit message.
        author: Author name of the branch tip commit.
        date: Relative date of the branch tip commit (e.g. "2 hours ago").
        ahead: Commits ahead of upstream (local branches only).
        behind: Commits behind upstream (local branches only).
    """
    name: str
    current: bool
    remote: bool = False
    ref_type: str = "branch"
    hash: str = ""
    message: str = ""
    author: str = ""
    date: str = ""
    ahead: int = 0
    behind: int = 0

    def to_dict(self) -> dict:
        """Serialise to a JSON-compatible dict."""
        return {
            "name": self.name,
            "current": self.current,
            "remote": self.remote,
            "type": self.ref_type,
            "hash": self.hash,
            "message": self.message,
            "author": self.author,
            "date": self.date,
            "ahead": self.ahead,
            "behind": self.behind,
        }


@dataclass
class GitLogEntry:
    """A single commit log entry.

    Attributes:
        hash: Full commit hash.
        short_hash: Abbreviated commit hash.
        message: Commit message subject line.
        author: Author name.
        date: Commit date (short format).
    """
    hash: str
    short_hash: str
    message: str
    author: str
    date: str

    def to_dict(self) -> dict:
        """Serialise to a JSON-compatible dict."""
        return {
            "hash": self.hash,
            "short_hash": self.short_hash,
            "message": self.message,
            "author": self.author,
            "date": self.date,
        }


@dataclass
class GitStatusResult:
    """Complete result of ``git status``.

    Attributes:
        branch: Current branch name.
        staged: List of staged file changes.
        unstaged: List of unstaged file changes.
        untracked: List of untracked files.
        conflicted: List of files with merge conflicts (UU/AA/DD/UD/DU status).
        ahead: Number of local commits not yet pushed to remote.
        behind: Number of remote commits not yet pulled locally.
        error: Error message (empty on success).
    """
    branch: str = ""
    staged: list[GitFileStatus] = field(default_factory=list)
    unstaged: list[GitFileStatus] = field(default_factory=list)
    untracked: list[GitFileStatus] = field(default_factory=list)
    conflicted: list[GitFileStatus] = field(default_factory=list)
    ahead: int = 0
    behind: int = 0
    error: str = ""

    def to_dict(self) -> dict:
        """Serialise to a JSON-compatible dict."""
        return {
            "branch": self.branch,
            "staged": [f.to_dict() for f in self.staged],
            "unstaged": [f.to_dict() for f in self.unstaged],
            "untracked": [f.to_dict() for f in self.untracked],
            "conflicted": [f.to_dict() for f in self.conflicted],
            "ahead": self.ahead,
            "behind": self.behind,
            "error": self.error,
        }


class GitService:
    """Async Git operations service backed by the system ``git`` binary.

    All operations are async and executed via subprocess.  Errors are returned
    as structured ``error`` fields rather than raised as exceptions.

    Attributes:
        _cwd: Current working directory for git commands.
        _command_timeout: Timeout in seconds for regular git commands.
        _discovery_timeout: Timeout in seconds for repo discovery commands.
    """

    def __init__(self, cwd: str, command_timeout: int = 30, discovery_timeout: int = 5):
        self._cwd = cwd
        self._command_timeout = command_timeout
        self._discovery_timeout = discovery_timeout

    def _update_cwd(self, cwd: str):
        """Update the working directory for subsequent git commands.

        Args:
            cwd: New working directory path.
        """
        self._cwd = cwd

    async def _run(self, *args: str, timeout: float | None = None) -> tuple[str, str, int]:
        """Execute a git command and return its output.

        Args:
            *args: Git sub-command and arguments (e.g. ``"status", "--porcelain"``).
            timeout: Optional override for the command timeout.

        Returns:
            Tuple of ``(stdout, stderr, returncode)``.
        """
        actual_timeout = timeout or self._command_timeout
        cmd = ["git"] + list(args)
        logger.debug(f"git: {' '.join(cmd)} (cwd={self._cwd})")
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                cwd=self._cwd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=actual_timeout)
            out = decode_process_output(stdout)
            err = decode_process_output(stderr).strip()
            return out, err, proc.returncode or 0
        except asyncio.TimeoutError:
            return "", t("backend.gitTimeout"), -1
        except FileNotFoundError:
            return "", t("backend.gitNotInstalled"), -1
        except Exception as e:
            return "", str(e), -1

    async def is_repo(self) -> bool:
        """Check whether the current directory is inside a git repository.

        Returns:
            True if inside a git work tree, False otherwise.
        """
        _, _, code = await self._run("rev-parse", "--is-inside-work-tree")
        return code == 0

    async def discover_repos(
        self,
        root_dir: str = "",
        max_depth: int = 3,
        ignored_folders: list[str] | None = None,
        extra_scan_paths: list[str] | None = None,
    ) -> list[dict]:
        """Discover all git repositories under a directory tree.

        Mirrors the VS Code ``model.ts`` ``scanWorkspaceFolders`` algorithm:
        1. BFS traversal (``traverseWorkspaceFolder``), depth-limited.
        2. Skip ``.git`` directories and entries in ``ignored_folders``.
        3. Validate each candidate with ``git rev-parse --git-dir``.
        4. Detect submodules via ``.gitmodules``.
        5. Support extra scan paths (VS Code ``git.scanRepositories``).

        Args:
            root_dir: Root directory to scan (defaults to ``_cwd``).
            max_depth: Maximum traversal depth (VS Code ``git.repositoryScanMaxDepth``).
                Use -1 for unlimited depth.
            ignored_folders: Directory names to skip
                (VS Code ``git.repositoryScanIgnoredFolders``).
            extra_scan_paths: Additional paths to scan
                (VS Code ``git.scanRepositories``).

        Returns:
            List of repository dicts with keys: ``path``, ``name``,
            ``relative_path``, ``branch``, ``is_current``, ``kind``,
            ``submodule_of``.
        """
        scan_root = root_dir or self._cwd
        if not scan_root:
            return []

        root_path = Path(scan_root).resolve()
        if not root_path.exists():
            return []

        # Default ignored directories (VS Code defaults + common noise)
        default_ignored = {
            'node_modules', '.venv', 'venv', '__pycache__', 'build', 'dist',
            '.gradle', '.idea', '.vscode', '.dart_tool', '.pub-cache',
            'target', 'vendor', '.tox', '.mypy_cache', '.pytest_cache',
            '.next', '.nuxt', 'coverage', '.hg', '.svn',
        }
        skip_set = default_ignored | set(ignored_folders or [])

        # ── Step 1: BFS to collect candidate directories ──
        candidate_paths: list[Path] = []
        is_root_repo = False

        # Check the root directory itself
        if (root_path / '.git').exists() or (root_path / '.git').is_file():
            candidate_paths.append(root_path)
            is_root_repo = True

        # BFS queue: (path, depth)
        # Even if root is a repo, scan children (monorepo: root + sub-repos)
        queue: deque[tuple[Path, int]] = deque()
        queue.append((root_path, 0))

        while queue:
            current_path, depth = queue.popleft()

            if depth >= max_depth and max_depth != -1:
                continue

            try:
                entries = sorted(current_path.iterdir())
            except (PermissionError, OSError):
                continue

            for entry in entries:
                # Path.is_dir() doesn't accept follow_symlinks before Python 3.12;
                # use is_symlink() check separately for compatibility with 3.10+.
                if entry.is_symlink() or not entry.is_dir():
                    continue

                name = entry.name

                # Skip the .git directory itself
                if name == '.git':
                    continue

                if name in skip_set:
                    continue

                # Skip hidden directories (. prefix)
                if name.startswith('.'):
                    continue

                # Check for a git repository marker
                git_marker = entry / '.git'
                if git_marker.exists() or git_marker.is_file():
                    if entry not in candidate_paths:
                        candidate_paths.append(entry)
                    # Do not descend into discovered repos (submodules checked later)
                    continue

                # Continue BFS
                queue.append((entry, depth + 1))

        # ── Step 2: Process extra scan paths (VS Code git.scanRepositories) ──
        for scan_path in (extra_scan_paths or []):
            if scan_path == '.git':
                continue
            abs_path = Path(scan_path) if Path(scan_path).is_absolute() else root_path / scan_path
            if abs_path.exists() and abs_path not in candidate_paths:
                candidate_paths.append(abs_path)

        # ── Step 3: Gather repo details + detect submodules ──
        result = []
        submodule_repos: list[dict] = []

        for repo_path in candidate_paths:
            repo_str = str(repo_path)

            branch = await self._get_branch(repo_str)

            try:
                rel_path = str(repo_path.relative_to(root_path))
            except ValueError:
                rel_path = repo_str

            repo_info = {
                "path": repo_str.replace("\\", "/"),
                "name": repo_path.name,
                "relative_path": rel_path.replace("\\", "/"),
                "branch": branch,
                "is_current": repo_str == str(Path(self._cwd).resolve()),
                "kind": "repository",
                "submodule_of": None,
            }
            result.append(repo_info)

            # Detect submodules (VS Code checkForSubmodules)
            submodules = await self._detect_submodules(repo_str)
            for sub_path, sub_name in submodules:
                sub_full = repo_path / sub_path
                if sub_full.exists() and sub_full not in candidate_paths:
                    sub_branch = await self._get_branch(str(sub_full))
                    try:
                        sub_rel = str(sub_full.relative_to(root_path))
                    except ValueError:
                        sub_rel = str(sub_full)
                    submodule_repos.append({
                        "path": str(sub_full).replace("\\", "/"),
                        "name": sub_name or sub_full.name,
                        "relative_path": sub_rel.replace("\\", "/"),
                        "branch": sub_branch,
                        "is_current": str(sub_full) == str(Path(self._cwd).resolve()),
                        "kind": "submodule",
                        "submodule_of": repo_str.replace("\\", "/"),
                    })

        result.extend(submodule_repos)
        logger.debug(f"发现 {len(result)} 个 git 仓库 (root={scan_root}, repos={len(result) - len(submodule_repos)}, submodules={len(submodule_repos)})")
        return result

    async def _get_branch(self, repo_path: str) -> str:
        """Get the current branch name for a repository.

        Args:
            repo_path: Absolute path to the repository root.

        Returns:
            Branch name string, or empty string on failure.
        """
        try:
            proc = await asyncio.create_subprocess_exec(
                "git", "rev-parse", "--abbrev-ref", "HEAD",
                cwd=repo_path,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=self._discovery_timeout)
            if proc.returncode == 0:
                return decode_process_output(stdout).strip()
        except Exception as e:
            logger.debug(f"Git 仓库发现失败（可忽略）: {e}")
        return ""

    async def _detect_submodules(self, repo_path: str) -> list[tuple[str, str]]:
        """Detect submodules by parsing ``.gitmodules``.

        Follows the VS Code ``checkForSubmodules`` pattern.

        Args:
            repo_path: Absolute path to the parent repository.

        Returns:
            List of ``(relative_path, name)`` tuples for each submodule.
        """
        gitmodules = Path(repo_path) / '.gitmodules'
        if not gitmodules.exists():
            return []

        try:
            proc = await asyncio.create_subprocess_exec(
                "git", "config", "--file", ".gitmodules",
                "--get-regexp", "path",
                cwd=repo_path,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=self._discovery_timeout)
            if proc.returncode != 0:
                return []

            submodules = []
            for line in decode_process_output(stdout).strip().split('\n'):
                if not line:
                    continue
                # Format: submodule.NAME.path VALUE
                parts = line.split()
                if len(parts) >= 2:
                    key = parts[0]  # submodule.xxx.path
                    path_val = parts[1]
                    # Extract the submodule name from the key
                    name_parts = key.split('.')
                    name = name_parts[1] if len(name_parts) >= 3 else path_val
                    submodules.append((path_val, name))
            return submodules
        except Exception:
            return []

    async def find_repo_for_file(self, file_path: str) -> str | None:
        """Find the git repository root for a given file.

        Walks up from the file's parent directory looking for a ``.git`` marker,
        similar to VS Code's ``onDidChangeVisibleTextEditors``.

        Args:
            file_path: Absolute path to the file.

        Returns:
            Repository root path, or None if the file is not in a repository.
        """
        try:
            proc = await asyncio.create_subprocess_exec(
                "git", "rev-parse", "--show-toplevel",
                cwd=str(Path(file_path).parent),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=self._discovery_timeout)
            if proc.returncode == 0:
                return decode_process_output(stdout).strip()
        except Exception as e:
            logger.debug(f"Git 默认分支检测失败（可忽略）: {e}")
        return None

    # ── Status ──

    async def status(self) -> GitStatusResult:
        """Get the full git status (staged / unstaged / untracked).

        Returns:
            A GitStatusResult with categorised file changes.
        """
        if not await self.is_repo():
            return GitStatusResult(error=t("backend.notGitRepo"))

        branch_out, _, _ = await self._run("branch", "--show-current")
        branch = branch_out.strip()

        # Get ahead/behind counts relative to upstream tracking branch.
        # Fails silently if no upstream is configured (e.g. new local branch).
        ahead, behind = 0, 0
        if branch:
            ab_out, _, ab_code = await self._run(
                "rev-list", "--left-right", "--count", f"HEAD...@{{u}}",
            )
            if ab_code == 0 and ab_out.strip():
                parts = ab_out.strip().split("\t")
                if len(parts) == 2:
                    ahead = int(parts[0])
                    behind = int(parts[1])

        out, err, code = await self._run("status", "--porcelain=v1", "-uall")
        if code != 0:
            return GitStatusResult(error=err.split("\n")[0] if err else t("backend.gitStatusFailed"))

        # Debug: log raw porcelain output to diagnose staged/unstaged mismatches
        logger.debug(f"git status porcelain 原始输出:\n{out.rstrip()}")

        result = GitStatusResult(branch=branch, ahead=ahead, behind=behind)
        for line in out.rstrip().split("\n"):
            if not line:
                continue
            if len(line) < 4:
                logger.warning(f"git status 格式异常行（已跳过）: {line!r}")
                continue
            x = line[0]  # Staged status indicator
            y = line[1]  # Unstaged status indicator
            path = line[3:]

            # Handle renames (R  old -> new)
            old_path = ""
            if " -> " in path:
                old_path, path = path.split(" -> ", 1)

            # Untracked
            if x == "?" and y == "?":
                result.untracked.append(GitFileStatus(
                    path=path, status="?", staged=False))
                continue

            # Merge conflicts: UU, AA, DD, UD, DU, AU, UA
            # These files have unresolved conflict markers and need
            # special handling (separate from staged/unstaged).
            xy = f"{x}{y}"
            conflict_codes = {"UU", "AA", "DD", "UD", "DU", "AU", "UA"}
            if xy in conflict_codes:
                result.conflicted.append(GitFileStatus(
                    path=path, status="U", staged=False))
                continue

            # Staged changes
            if x != " " and x != "?":
                result.staged.append(GitFileStatus(
                    path=path, status=x, staged=True, old_path=old_path))

            # Unstaged changes
            if y != " " and y != "?":
                result.unstaged.append(GitFileStatus(
                    path=path, status=y, staged=False))

        return result

    # ── Diff ──

    async def diff_file(self, path: str, staged: bool = False) -> dict:
        """Get the diff for a single file.

        Args:
            path: Relative file path.
            staged: If True, show the staged diff (``--cached``).

        Returns:
            Dict with ``diff`` and ``error`` keys.
        """
        args = ["diff"]
        if staged:
            args.append("--cached")
        args.extend(["--", path])
        out, err, code = await self._run(*args)
        if code != 0:
            return {"diff": "", "error": err.strip()[:500] if err else ""}
        return {"diff": out, "error": ""}

    async def file_content_for_diff(self, path: str, staged: bool = False) -> dict:
        """Get old and new file content for a side-by-side diff viewer.

        ``old_content`` is the HEAD version; ``new_content`` is either the
        staged version or the current on-disk content.

        For binary files (images, fonts, etc.), returns an error hint
        instead of empty strings so the App can show a meaningful message.

        Binary detection uses the same heuristic as Git: check the first
        8000 bytes for a NUL byte (\\x00). No hardcoded extension list.

        Args:
            path: Relative file path.
            staged: If True, ``new_content`` comes from the index.

        Returns:
            Dict with ``old_content``, ``new_content``, and ``error`` keys.
        """
        import os

        # old: HEAD version
        old_out, old_err, old_code = await self._run("show", f"HEAD:{path}")
        old_content = old_out if old_code == 0 else ""

        if staged:
            # Staged: index version
            new_out, _, new_code = await self._run("show", f":{path}")
            new_content = new_out if new_code == 0 else ""
        else:
            # Unstaged: current on-disk content
            full_path = os.path.join(self._cwd, path)
            try:
                # Git's binary detection: NUL byte in the first 8000 bytes
                with open(full_path, "rb") as f:
                    head = f.read(8000)
                if b"\x00" in head:
                    return {
                        "old_content": "",
                        "new_content": "",
                        "error": "binary",
                    }
                # Text file — read full content as UTF-8
                with open(full_path, "r", encoding="utf-8") as f:
                    new_content = f.read()
            except UnicodeDecodeError:
                return {
                    "old_content": "",
                    "new_content": "",
                    "error": "binary",
                }
            except FileNotFoundError:
                new_content = ""
            except Exception:
                new_content = ""

        # Final binary check: if content contains NUL chars (\x00), it's binary.
        # git show outputs raw binary data which passes through decode_process_output
        # as NUL chars (valid in UTF-8). Same heuristic as Git itself.
        if "\x00" in old_content[:8000] or "\x00" in new_content[:8000]:
            return {
                "old_content": "",
                "new_content": "",
                "error": "binary",
            }

        return {
            "old_content": old_content,
            "new_content": new_content,
            "error": "",
        }

    async def diff_all(self, staged: bool = False) -> dict:
        """Get the combined diff for all changed files.

        Args:
            staged: If True, show staged changes (``--cached``).

        Returns:
            Dict with ``diff`` and ``error`` keys.
        """
        args = ["diff", "--stat", "--patch"]
        if staged:
            args.append("--cached")
        out, err, code = await self._run(*args)
        if code != 0:
            return {"diff": "", "error": err.strip()[:500] if err else ""}
        return {"diff": out, "error": ""}

    # ── Stage / Unstage ──

    async def stage(self, paths: list[str]) -> dict:
        """Stage specific files (``git add``).

        Args:
            paths: List of relative file paths to stage.

        Returns:
            Dict with ``success`` and ``error`` keys.
        """
        if not paths:
            return {"error": t("backend.gitNoFiles")}
        out, err, code = await self._run("add", "--", *paths)
        if code != 0:
            return {"success": False, "error": err.strip()[:500] if err else ""}
        return {"success": True, "error": ""}

    async def stage_all(self) -> dict:
        """Stage all changes (``git add -A``).

        Returns:
            Dict with ``success`` and ``error`` keys.
        """
        out, err, code = await self._run("add", "-A")
        if code != 0:
            return {"success": False, "error": err.strip()[:500] if err else ""}
        return {"success": True, "error": ""}

    async def unstage(self, paths: list[str]) -> dict:
        """Unstage specific files (``git reset HEAD``).

        Args:
            paths: List of relative file paths to unstage.

        Returns:
            Dict with ``success`` and ``error`` keys.
        """
        if not paths:
            return {"error": t("backend.gitNoFiles")}
        out, err, code = await self._run("reset", "HEAD", "--", *paths)
        if code != 0:
            return {"success": False, "error": err.strip()[:500] if err else ""}
        return {"success": True, "error": ""}

    async def unstage_all(self) -> dict:
        """Unstage all staged changes (``git reset HEAD``).

        Returns:
            Dict with ``success`` and ``error`` keys.
        """
        out, err, code = await self._run("reset", "HEAD")
        if code != 0:
            return {"success": False, "error": err.strip()[:500] if err else ""}
        return {"success": True, "error": ""}

    # ── Commit ──

    async def commit(self, message: str, no_verify: bool = False) -> dict:
        """Create a commit with the given message.

        Args:
            message: Commit message text.
            no_verify: If True, skip pre-commit and commit-msg hooks.
                Only used when user explicitly chooses to force commit
                after a hook failure.

        Returns:
            Dict with ``success``, ``output``, ``error``, and
            ``hook_failed`` keys. When hook_failed is True, the UI
            should offer a "force commit" option.
        """
        if not message.strip():
            return {"success": False, "error": t("backend.gitCommitEmpty"),
                    "hook_failed": False}
        logger.info(f"git commit: message={message[:50]}, no_verify={no_verify}")

        args = ["commit"]
        if no_verify:
            args.append("--no-verify")
        args.extend(["-m", message])

        out, err, code = await self._run(*args)
        if code != 0:
            error_msg = err.strip() if err else ""
            # Return full error message for hooks (they output detailed info)
            # but cap at reasonable length to avoid huge payloads
            display_error = error_msg[:500] if error_msg else ""
            logger.error(f"git commit 失败: {error_msg.split(chr(10))[0] if error_msg else ''}")
            # Always offer force-commit option on failure (VS Code pattern:
            # don't guess the cause, let user decide if they want --no-verify)
            return {"success": False, "error": display_error,
                    "hook_failed": not no_verify}
        return {"success": True, "output": out.strip(), "error": "",
                "hook_failed": False}

    # ── Push / Pull ──

    async def push(self) -> dict:
        """Push commits to the remote.

        Returns:
            Dict with ``success``, ``output``, ``up_to_date``, and ``error`` keys.
        """
        out, err, code = await self._run("push", timeout=self._command_timeout)
        if code != 0:
            logger.error(f"git push 失败: {err.split(chr(10))[0] if err else ''}")
            return {"success": False, "up_to_date": False, "error": err.strip()[:500] if err else ""}
        combined = (out + err).strip()
        up_to_date = "Everything up-to-date" in combined
        logger.info(f"git push 成功: up_to_date={up_to_date}")
        return {"success": True, "output": combined, "up_to_date": up_to_date, "error": ""}

    async def pull(self) -> dict:
        """Pull changes from the remote.

        Returns:
            Dict with ``success``, ``output``, ``up_to_date``, and ``error`` keys.
        """
        out, err, code = await self._run("pull", timeout=self._command_timeout)
        if code != 0:
            logger.error(f"git pull 失败: {err.split(chr(10))[0] if err else ''}")
            return {"success": False, "up_to_date": False, "error": err.strip()[:500] if err else ""}
        combined = (out + err).strip()
        up_to_date = "Already up to date" in combined
        logger.info(f"git pull 成功: up_to_date={up_to_date}")
        return {"success": True, "output": combined, "up_to_date": up_to_date, "error": ""}

    async def fetch(self) -> dict:
        """Fetch changes from the remote without merging.

        Returns:
            Dict with ``success``, ``output``, and ``error`` keys.
        """
        out, err, code = await self._run("fetch", timeout=self._command_timeout)
        if code != 0:
            return {"success": False, "error": err.strip()[:500] if err else ""}
        logger.debug("git fetch 成功")
        return {"success": True, "output": (out + err).strip(), "error": ""}

    # ── Branch ──

    async def branches(self) -> dict:
        """List all local and remote branches with last commit metadata.

        Implementation mirrors VS Code's git extension (getRefs with
        includeCommitDetails). Uses git for-each-ref with NUL-separated
        fields for reliable parsing.

        Format per ref:
          refname | objectname:short | authorname | committerdate:relative |
          subject | upstream:track

        Returns:
            Dict with ``branches`` (list of branch dicts) and ``error`` keys.
        """
        # NUL separator for reliable field parsing (VS Code pattern)
        sep = "%00"
        fmt = sep.join([
            "%(refname)",
            "%(objectname:short)",
            "%(authorname)",
            "%(committerdate:relative)",
            "%(subject)",
            "%(upstream:track)",
            "%(HEAD)",
        ])
        out, err, code = await self._run(
            "for-each-ref",
            f"--format={fmt}",
            "--sort=-committerdate",
            "refs/heads/", "refs/remotes/", "refs/tags/",
        )
        if code != 0:
            return await self._branches_simple()

        import re
        track_regex = re.compile(r"\[(?:ahead (\d+))?(?:,\s*)?(?:behind (\d+))?\]")

        branches: list[GitBranch] = []

        for line in out.strip().split("\n"):
            if not line.strip():
                continue
            parts = line.split("\x00")
            if len(parts) < 6:
                continue

            refname = parts[0].strip()
            short_hash = parts[1].strip()
            author = parts[2].strip()
            date = parts[3].strip()
            message = parts[4].strip()
            track = parts[5].strip()
            head_marker = parts[6].strip() if len(parts) > 6 else ""

            # Determine branch type and name from refname
            current = head_marker == "*"
            if refname.startswith("refs/heads/"):
                name = refname[len("refs/heads/"):]
                remote = False
                ref_type = "branch"
            elif refname.startswith("refs/remotes/"):
                name = refname[len("refs/remotes/"):]
                remote = True
                ref_type = "remote"
                # Skip origin/HEAD pointer
                if name.endswith("/HEAD"):
                    continue
            elif refname.startswith("refs/tags/"):
                name = refname[len("refs/tags/"):]
                remote = False
                ref_type = "tag"
            else:
                continue

            # Parse ahead/behind from upstream:track field
            ahead = 0
            behind = 0
            m = track_regex.search(track)
            if m:
                ahead = int(m.group(1)) if m.group(1) else 0
                behind = int(m.group(2)) if m.group(2) else 0

            branches.append(GitBranch(
                name=name,
                current=current,
                remote=remote,
                ref_type=ref_type,
                hash=short_hash,
                message=message,
                author=author,
                date=date,
                ahead=ahead,
                behind=behind,
            ))

        return {"branches": [b.to_dict() for b in branches], "error": ""}

    async def _branches_simple(self) -> dict:
        """Fallback: list branches without commit metadata.

        Used when for-each-ref is not available or fails.
        """
        out, err, code = await self._run("branch", "-a", "--no-color")
        if code != 0:
            return {"branches": [], "error": err.strip()[:500] if err else ""}
        branches = []
        for line in out.strip().split("\n"):
            if not line.strip():
                continue
            current = line.startswith("*")
            name = line.lstrip("* ").strip()
            remote = name.startswith("remotes/")
            if remote:
                name = name.replace("remotes/", "", 1)
            branches.append(GitBranch(name=name, current=current, remote=remote))
        return {"branches": [b.to_dict() for b in branches], "error": ""}

    async def checkout(self, branch: str) -> dict:
        """Check out a branch.

        Args:
            branch: Branch name to check out.

        Returns:
            Dict with ``success`` and ``error`` keys.
        """
        out, err, code = await self._run("checkout", branch)
        if code != 0:
            logger.error(f"git checkout 失败: branch={branch}, error={err.split(chr(10))[0] if err else ''}")
            return {"success": False, "error": err.strip()[:500] if err else ""}
        logger.info(f"git checkout 成功: branch={branch}")
        return {"success": True, "error": ""}

    # ── Log ──

    async def log(self, count: int = 50, skip: int = 0,
                  branch: str = "", author: str = "",
                  since: str = "", until: str = "",
                  grep: str = "") -> dict:
        """Get the commit log with pagination and filter support.

        Args:
            count: Maximum number of entries to return per page.
            skip: Number of commits to skip (for pagination).
            branch: Filter by branch name (empty = current branch).
            author: Filter by author name (case-insensitive substring).
            since: Only commits after this date (ISO 8601 or git date format).
            until: Only commits before this date.
            grep: Filter by commit message keyword (case-insensitive).

        Returns:
            Dict with ``entries`` (list of log entry dicts),
            ``has_more`` (bool), and ``error`` keys.
        """
        args = ["log", f"-n{count + 1}", f"--skip={skip}",
                "--pretty=format:%H|%h|%s|%an|%ad", "--date=short"]
        if branch:
            args.append(branch)
        if author:
            args.extend([f"--author={author}", "-i"])
        if since:
            args.append(f"--since={since}")
        if until:
            args.append(f"--until={until}")
        if grep:
            args.extend([f"--grep={grep}", "-i"])

        # Request one extra to detect if more pages exist
        out, err, code = await self._run(*args)
        if code != 0:
            return {"entries": [], "has_more": False, "error": err.strip()[:500] if err else ""}
        entries = []
        for line in out.strip().split("\n"):
            if not line:
                continue
            parts = line.split("|", 4)
            if len(parts) >= 5:
                entries.append(GitLogEntry(
                    hash=parts[0], short_hash=parts[1],
                    message=parts[2], author=parts[3], date=parts[4],
                ).to_dict())
        has_more = len(entries) > count
        if has_more:
            entries = entries[:count]
        return {"entries": entries, "has_more": has_more, "error": ""}

    async def log_authors(self) -> list[str]:
        """Get a deduplicated list of commit authors for filter UI.

        Returns:
            Sorted list of unique author names.
        """
        out, _, code = await self._run(
            "log", "--all", "--format=%an",
        )
        if code != 0:
            return []
        authors = sorted(set(
            name.strip() for name in out.strip().split("\n") if name.strip()
        ))
        return authors

    async def log_search(self, query: str, count: int = 50) -> dict:
        """Search commit history by message or author.

        Searches both commit messages (--grep) and author names (--author)
        case-insensitively, then merges and deduplicates results.

        Args:
            query: Search keyword (matched against message and author).
            count: Maximum number of results to return.

        Returns:
            Dict with ``entries``, ``query``, and ``error`` keys.
        """
        if not query.strip():
            return {"entries": [], "query": query, "error": ""}

        fmt = "--pretty=format:%H|%h|%s|%an|%ad"
        date_fmt = "--date=short"

        # Search by commit message
        out_msg, _, code_msg = await self._run(
            "log", "--all", f"--grep={query}", "-i", f"-n{count}",
            fmt, date_fmt,
        )
        # Search by author
        out_author, _, code_author = await self._run(
            "log", "--all", f"--author={query}", "-i", f"-n{count}",
            fmt, date_fmt,
        )

        seen: set[str] = set()
        entries: list[dict] = []

        for out in [out_msg, out_author]:
            if not out:
                continue
            for line in out.strip().split("\n"):
                if not line:
                    continue
                parts = line.split("|", 4)
                if len(parts) >= 5 and parts[0] not in seen:
                    seen.add(parts[0])
                    entries.append(GitLogEntry(
                        hash=parts[0], short_hash=parts[1],
                        message=parts[2], author=parts[3], date=parts[4],
                    ).to_dict())

        return {"entries": entries[:count], "query": query, "error": ""}

    async def show_commit(self, commit_hash: str) -> dict:
        """Get commit details including changed file list with stats.

        Args:
            commit_hash: Full or abbreviated commit hash.

        Returns:
            Dict with commit metadata and ``files`` list, each containing
            ``path``, ``status``, ``additions``, ``deletions``.
        """
        # Get commit metadata
        out_meta, err, code = await self._run(
            "show", "--no-patch",
            "--format=%H|%h|%s|%an|%ad|%B",
            "--date=short",
            commit_hash,
        )
        if code != 0:
            return {"error": err.strip()[:500] if err else "unknown error"}

        lines = out_meta.strip().split("\n")
        meta_parts = lines[0].split("|", 5) if lines else []
        full_message = meta_parts[5].strip() if len(meta_parts) > 5 else ""
        # Full body may span multiple lines after the first
        if len(lines) > 1:
            full_message += "\n" + "\n".join(lines[1:])
        full_message = full_message.strip()

        # Get changed files with numstat (additions/deletions per file)
        out_stat, _, _ = await self._run(
            "diff-tree", "--no-commit-id", "-r", "--numstat",
            "--diff-filter=ACDMRT",
            commit_hash,
        )
        # Get file status letters (A/M/D/R)
        out_name, _, _ = await self._run(
            "diff-tree", "--no-commit-id", "-r", "--name-status",
            "--diff-filter=ACDMRT",
            commit_hash,
        )

        # Parse numstat: "additions\tdeletions\tpath"
        stat_map: dict[str, tuple[int, int]] = {}
        if out_stat:
            for line in out_stat.strip().split("\n"):
                if not line:
                    continue
                parts = line.split("\t", 2)
                if len(parts) >= 3:
                    add = int(parts[0]) if parts[0] != "-" else 0
                    delete = int(parts[1]) if parts[1] != "-" else 0
                    stat_map[parts[2]] = (add, delete)

        # Parse name-status: "STATUS\tpath" (or "STATUS\told\tnew" for renames)
        files: list[dict] = []
        if out_name:
            for line in out_name.strip().split("\n"):
                if not line:
                    continue
                parts = line.split("\t")
                if len(parts) >= 2:
                    status = parts[0][0]  # First char: A/M/D/R/C/T
                    path = parts[-1]  # Last part is the new path
                    add, delete = stat_map.get(path, (0, 0))
                    files.append({
                        "path": path,
                        "status": status,
                        "additions": add,
                        "deletions": delete,
                    })

        result = {
            "hash": meta_parts[0] if len(meta_parts) > 0 else commit_hash,
            "short_hash": meta_parts[1] if len(meta_parts) > 1 else "",
            "message": meta_parts[2] if len(meta_parts) > 2 else "",
            "author": meta_parts[3] if len(meta_parts) > 3 else "",
            "date": meta_parts[4] if len(meta_parts) > 4 else "",
            "full_message": full_message,
            "files": files,
            "error": "",
        }
        return result

    async def diff_commit_file(self, commit_hash: str, file_path: str) -> dict:
        """Get the old and new content of a file in a specific commit.

        Uses ``git show`` to retrieve the file content before and after
        the commit, suitable for feeding into DiffViewerScreen.

        Args:
            commit_hash: Full or abbreviated commit hash.
            file_path: Relative file path within the repository.

        Returns:
            Dict with ``old_content``, ``new_content``, ``path``, ``error``.
        """
        # New content (after commit)
        out_new, _, code_new = await self._run(
            "show", f"{commit_hash}:{file_path}",
        )
        # Old content (before commit — parent)
        out_old, _, code_old = await self._run(
            "show", f"{commit_hash}^:{file_path}",
        )
        return {
            "old_content": out_old if code_old == 0 else "",
            "new_content": out_new if code_new == 0 else "",
            "path": file_path,
            "error": "",
        }

    # ── Discard ──

    async def discard_file(self, path: str) -> dict:
        """Discard unstaged changes to a file (``git checkout -- <path>``).

        Args:
            path: Relative file path.

        Returns:
            Dict with ``success`` and ``error`` keys.
        """
        out, err, code = await self._run("checkout", "--", path)
        if code != 0:
            return {"success": False, "error": err.strip()[:500] if err else ""}
        return {"success": True, "error": ""}

    # ── Git Shell (restricted command executor) ──

    # Allowed git sub-commands (whitelist)
    _SAFE_SUBCOMMANDS = {
        # Read-only (fully safe)
        "status", "log", "diff", "show", "branch", "tag", "remote",
        "describe", "shortlog", "blame", "ls-files", "ls-tree",
        "rev-parse", "rev-list", "cat-file", "config",
        "reflog", "stash list", "worktree list",
        # Write operations (normal usage)
        "add", "commit", "push", "pull", "fetch", "merge", "rebase",
        "checkout", "switch", "restore", "stash", "cherry-pick",
        "revert", "rm", "mv", "init", "clone",
        # Branch management
        "branch -d", "branch -D", "branch -m",
        # Tags
        "tag -a", "tag -d",
    }

    # Dangerous sub-commands requiring explicit confirmation
    _DANGEROUS_SUBCOMMANDS = {
        "reset --hard", "push --force", "push -f",
        "clean -fd", "clean -f", "clean -df",
        "filter-branch", "gc --prune",
    }

    # Completely blocked patterns (shell injection vectors)
    _BLOCKED_PATTERNS = [
        "!",           # Shell escape
        "|",           # Pipe
        ";",           # Command separator
        "&&",          # Command chain
        "||",          # Command chain
        "`",           # Command substitution
        "$(",          # Command substitution
        ">",           # Redirect
        "<",           # Redirect
    ]

    async def execute_command(self, command: str) -> dict:
        """Execute a git command with safety checks (Git Shell).

        Only allows git commands; rejects shell injection, non-git commands,
        and dangerous operations (which require explicit confirmation).
        Commands are executed directly via subprocess without a shell.

        Args:
            command: User-entered command string (e.g. ``"git rebase -i HEAD~3"``).

        Returns:
            Dict with keys: ``success``, ``stdout``, ``stderr``, ``command``,
            ``blocked``, ``reason``, ``dangerous``.
        """
        command = command.strip()

        if not command:
            return {"success": False, "stdout": "", "stderr": "",
                    "command": "", "blocked": True, "reason": t("backend.emptyCommand"), "dangerous": False}

        # Strip leading "git " (user may type "git status" or just "status")
        if command.startswith("git "):
            command = command[4:].strip()
        elif command == "git":
            command = "status"  # Bare "git" is treated as "git status"

        # Check for shell injection patterns
        for pattern in self._BLOCKED_PATTERNS:
            if pattern in command:
                return {"success": False, "stdout": "", "stderr": "",
                        "command": f"git {command}", "blocked": True,
                        "reason": t("backend.blockedPattern", pattern=pattern), "dangerous": False}

        parts = command.split()
        if not parts:
            return {"success": False, "stdout": "", "stderr": "",
                    "command": "", "blocked": True, "reason": t("backend.emptyCommand"), "dangerous": False}

        subcmd = parts[0]

        # Auto-limit output for high-volume commands (prevent App freeze)
        if subcmd == "log" and not any(p.startswith("-") and p[1:].isdigit() for p in parts[1:]):
            if "-n" not in parts and "--max-count" not in command:
                parts.append("-100")
                command = " ".join(parts)
        elif subcmd == "shortlog" and "-n" not in parts:
            parts.append("-100")
            command = " ".join(parts)

        # Check for dangerous operations
        for dangerous in self._DANGEROUS_SUBCOMMANDS:
            if command.startswith(dangerous):
                return {"success": False, "stdout": "", "stderr": "",
                        "command": f"git {command}", "blocked": False,
                        "reason": t("backend.dangerousOp", cmd=dangerous), "dangerous": True}

        # Execute directly via subprocess (no shell)
        logger.info(f"Git Shell: git {command}")
        out, err, code = await self._run(*parts, timeout=self._command_timeout)

        return {
            "success": code == 0,
            "stdout": out,
            "stderr": err,
            "command": f"git {command}",
            "blocked": False,
            "reason": "",
            "dangerous": False,
        }

    # ── Merge Conflict Resolution ──

    async def get_conflict_files(self) -> list[dict]:
        """List all files with unresolved merge conflicts.

        Uses git status porcelain output to identify conflict status codes:
        UU (both modified), AA (both added), DD (both deleted),
        UD (us modified, them deleted), DU (us deleted, them modified).

        Returns:
            List of dicts with ``path`` and ``conflict_type`` keys.
            Empty list if no conflicts or not in a merge state.
        """
        out, err, code = await self._run("status", "--porcelain=v1", "-uall")
        if code != 0:
            return []

        conflict_codes = {"UU", "AA", "DD", "UD", "DU", "AU", "UA"}
        conflicts = []

        for line in out.rstrip().split("\n"):
            if not line or len(line) < 4:
                continue
            xy = line[0:2]
            if xy in conflict_codes:
                path = line[3:]
                conflicts.append({
                    "path": path,
                    "conflict_type": xy,
                })

        logger.debug(f"冲突文件检测: {len(conflicts)} 个冲突文件")
        return conflicts

    async def get_conflicts(self, path: str, context_lines: int = 5) -> dict:
        """Parse conflicts and generate per-conflict full-file previews.

        For each conflict block, generates three full-file previews showing
        what the file looks like if THAT specific conflict is resolved with
        each strategy (current/incoming/both). Other conflict markers remain
        untouched in the preview. Supports "resolve one at a time" UI.

        Args:
            path: Relative file path within the repository.
            context_lines: Number of context lines before/after each conflict.

        Returns:
            Dict with path, conflicts (each with preview_current/incoming/both
            and highlight_current/incoming/both), count, and error.
        """
        full_path = os.path.join(self._cwd, path)
        logger.debug(f"冲突解析: path={path}")

        try:
            with open(full_path, "rb") as f:
                head = f.read(8000)
            if b"\x00" in head:
                return self._empty_conflicts(path, "binary")
        except FileNotFoundError:
            return self._empty_conflicts(path, f"File not found: {path}")
        except Exception as e:
            return self._empty_conflicts(path, str(e))

        try:
            with open(full_path, "r", encoding="utf-8") as f:
                content = f.read()
        except UnicodeDecodeError:
            return self._empty_conflicts(path, "binary")

        blocks = parse_conflicts(content)
        logger.info(f"冲突解析完成: path={path}, count={len(blocks)}")

        if not blocks:
            return {"path": path, "conflicts": [], "count": 0, "error": ""}

        # Build per-conflict data with full-file previews
        all_lines = content.split("\n")
        conflict_dicts = []

        for target_block in blocks:
            d = target_block.to_dict()

            # Context lines for the conflict snippet view
            before_start = max(0, target_block.range_start - context_lines)
            before_lines = all_lines[before_start:target_block.range_start]
            d["context_before"] = "\n".join(before_lines) + ("\n" if before_lines else "")
            after_end = min(len(all_lines), target_block.range_end + 1 + context_lines)
            after_lines = all_lines[target_block.range_end + 1:after_end]
            d["context_after"] = "\n".join(after_lines) + ("\n" if after_lines else "")

            # Generate 3 full-file previews for THIS conflict
            for resolution in ("current", "incoming", "both"):
                preview = apply_resolution(content, target_block, resolution)
                d[f"preview_{resolution}"] = preview

                # Calculate highlight range in the preview
                if resolution == "current":
                    resolved = target_block.current.content
                elif resolution == "incoming":
                    resolved = target_block.incoming.content
                else:
                    resolved = target_block.current.content + target_block.incoming.content

                if resolved.endswith("\n"):
                    resolved = resolved[:-1]
                line_count = len(resolved.split("\n")) if resolved else 0
                start = target_block.range_start
                end = start + line_count - 1
                d[f"highlight_{resolution}"] = [start, max(start, end)]

            conflict_dicts.append(d)

        return {
            "path": path,
            "conflicts": conflict_dicts,
            "count": len(blocks),
            "error": "",
        }

    @staticmethod
    def _empty_conflicts(path: str, error: str) -> dict:
        """Return an empty conflicts result with error."""
        return {"path": path, "conflicts": [], "count": 0, "error": error}

    async def resolve_conflict(self, path: str, conflict_id: int, resolution: str) -> dict:
        """Resolve a single conflict block by immediately rewriting the file.

        Mirrors VS Code's immediate applyEdit() behavior:
        1. Read file content
        2. Parse all conflict blocks
        3. Find target block by ID
        4. Apply resolution (replace conflict range with chosen content)
        5. Write file back immediately
        6. Re-parse and return updated conflict list

        After resolution, subsequent conflict IDs and line numbers shift.
        The returned ``remaining`` list has recalculated IDs/positions.

        Args:
            path: Relative file path within the repository.
            conflict_id: 0-based index of the conflict to resolve.
            resolution: One of "current", "incoming", "both".

        Returns:
            Dict with ``success``, ``remaining`` (updated conflicts),
            ``remaining_count``, and ``error`` keys.
        """
        full_path = os.path.join(self._cwd, path)
        logger.debug(
            f"冲突解决: path={path}, conflict_id={conflict_id}, "
            f"resolution={resolution}"
        )

        # Read current file content
        try:
            with open(full_path, "r", encoding="utf-8") as f:
                content = f.read()
        except Exception as e:
            logger.error(f"冲突解决失败（读取文件）: path={path}, error={e}")
            return {
                "success": False,
                "remaining": [],
                "remaining_count": 0,
                "error": str(e),
            }

        # Parse conflicts
        blocks = parse_conflicts(content)
        if conflict_id < 0 or conflict_id >= len(blocks):
            logger.error(
                f"冲突解决失败（ID 无效）: path={path}, "
                f"conflict_id={conflict_id}, total={len(blocks)}"
            )
            return {
                "success": False,
                "remaining": [b.to_dict() for b in blocks],
                "remaining_count": len(blocks),
                "error": f"Invalid conflict_id: {conflict_id} (file has {len(blocks)} conflicts)",
            }

        # Apply resolution
        target = blocks[conflict_id]
        try:
            new_content = apply_resolution(content, target, resolution)
        except ValueError as e:
            return {
                "success": False,
                "remaining": [b.to_dict() for b in blocks],
                "remaining_count": len(blocks),
                "error": str(e),
            }

        # Write back immediately (VS Code behavior: instant file modification)
        try:
            with open(full_path, "w", encoding="utf-8") as f:
                f.write(new_content)
        except Exception as e:
            logger.error(f"冲突解决失败（写入文件）: path={path}, error={e}")
            return {
                "success": False,
                "remaining": [b.to_dict() for b in blocks],
                "remaining_count": len(blocks),
                "error": str(e),
            }

        # Re-parse to get updated conflict list (IDs/lines recalculated)
        remaining_blocks = parse_conflicts(new_content)
        logger.info(
            f"冲突解决成功: path={path}, conflict_id={conflict_id}, "
            f"resolution={resolution}, remaining={len(remaining_blocks)}"
        )

        return {
            "success": True,
            "remaining": [b.to_dict() for b in remaining_blocks],
            "remaining_count": len(remaining_blocks),
            "error": "",
        }

    async def resolve_all_conflicts(self, path: str, resolution: str) -> dict:
        """Resolve all conflicts in a file with the same strategy.

        Mirrors VS Code's acceptAll command — processes all conflicts in
        a single pass. Must apply from bottom to top to prevent line
        offset corruption (same approach as VS Code's batch edit).

        Args:
            path: Relative file path within the repository.
            resolution: One of "current", "incoming", "both".

        Returns:
            Dict with ``success``, ``resolved_count``, and ``error`` keys.
        """
        full_path = os.path.join(self._cwd, path)
        logger.debug(f"全部冲突解决: path={path}, resolution={resolution}")

        try:
            with open(full_path, "r", encoding="utf-8") as f:
                content = f.read()
        except Exception as e:
            logger.error(f"全部冲突解决失败（读取文件）: path={path}, error={e}")
            return {"success": False, "resolved_count": 0, "error": str(e)}

        blocks = parse_conflicts(content)
        if not blocks:
            return {"success": True, "resolved_count": 0, "error": ""}

        # Apply from bottom to top to preserve line numbers
        for block in reversed(blocks):
            content = apply_resolution(content, block, resolution)

        try:
            with open(full_path, "w", encoding="utf-8") as f:
                f.write(content)
        except Exception as e:
            logger.error(f"全部冲突解决失败（写入文件）: path={path}, error={e}")
            return {"success": False, "resolved_count": 0, "error": str(e)}

        logger.info(
            f"全部冲突解决成功: path={path}, resolution={resolution}, "
            f"resolved_count={len(blocks)}"
        )
        return {"success": True, "resolved_count": len(blocks), "error": ""}

    async def merge_abort(self) -> dict:
        """Abort the current merge operation (``git merge --abort``).

        Returns:
            Dict with ``success`` and ``error`` keys.
        """
        logger.info("执行 git merge --abort")
        out, err, code = await self._run("merge", "--abort")
        if code != 0:
            logger.error(f"git merge --abort 失败: {err}")
            return {"success": False, "error": err.strip()[:500] if err else ""}
        logger.info("git merge --abort 成功")
        return {"success": True, "error": ""}

    async def sequencer_abort(self) -> dict:
        """Abort the current cherry-pick or revert operation.

        Detects which operation is in progress by checking .git/ sentinel
        files, then runs the appropriate --abort command.

        Returns:
            Dict with ``success``, ``operation`` (str), and ``error`` keys.
        """
        op = await self._detect_sequencer_operation()
        if not op:
            return {"success": False, "operation": "", "error": "No operation in progress"}

        logger.info(f"执行 git {op} --abort")
        out, err, code = await self._run(op, "--abort")
        if code != 0:
            logger.error(f"git {op} --abort 失败: {err}")
            return {"success": False, "operation": op, "error": err.strip()[:500] if err else ""}
        logger.info(f"git {op} --abort 成功")
        return {"success": True, "operation": op, "error": ""}

    async def sequencer_continue(self) -> dict:
        """Continue the current cherry-pick or revert after conflicts resolved.

        Detects which operation is in progress, then runs --continue.

        Returns:
            Dict with ``success``, ``operation`` (str), and ``error`` keys.
        """
        op = await self._detect_sequencer_operation()
        if not op:
            return {"success": False, "operation": "", "error": "No operation in progress"}

        logger.info(f"执行 git {op} --continue")
        out, err, code = await self._run(op, "--continue")
        if code != 0:
            logger.error(f"git {op} --continue 失败: {err}")
            return {"success": False, "operation": op, "error": err.strip()[:500] if err else ""}
        logger.info(f"git {op} --continue 成功")
        return {"success": True, "operation": op, "error": ""}

    async def sequencer_skip(self) -> dict:
        """Skip the current commit in a cherry-pick or revert sequence.

        Runs --skip for the detected operation. Unlike abort (cancels everything),
        skip only skips the current problematic commit and continues with the rest.

        Returns:
            Dict with ``success``, ``operation`` (str), and ``error`` keys.
        """
        op = await self._detect_sequencer_operation()
        if not op:
            return {"success": False, "operation": "", "error": "No operation in progress"}

        logger.info(f"执行 git {op} --skip")
        out, err, code = await self._run(op, "--skip")
        if code != 0:
            logger.error(f"git {op} --skip 失败: {err}")
            return {"success": False, "operation": op, "error": err.strip()[:500] if err else ""}
        logger.info(f"git {op} --skip 成功")
        return {"success": True, "operation": op, "error": ""}

    async def detect_operation_state(self) -> str:
        """Detect if a merge/cherry-pick/revert is in progress.

        Returns 'merge', 'cherry-pick', 'revert', or '' (no operation).
        """
        import os
        git_dir = os.path.join(self._cwd, ".git")
        if os.path.exists(os.path.join(git_dir, "MERGE_HEAD")):
            return "merge"
        if os.path.exists(os.path.join(git_dir, "CHERRY_PICK_HEAD")):
            return "cherry-pick"
        if os.path.exists(os.path.join(git_dir, "REVERT_HEAD")):
            return "revert"
        return ""

    async def _detect_sequencer_operation(self) -> str | None:
        """Detect which sequencer operation (cherry-pick/revert) is in progress.

        Checks .git/ sentinel files. Returns 'cherry-pick', 'revert', or None.
        """
        import os
        git_dir = os.path.join(self._cwd, ".git")
        if os.path.exists(os.path.join(git_dir, "CHERRY_PICK_HEAD")):
            return "cherry-pick"
        if os.path.exists(os.path.join(git_dir, "REVERT_HEAD")):
            return "revert"
        # Check sequencer dir (for multi-commit operations)
        sequencer_dir = os.path.join(git_dir, "sequencer")
        if os.path.isdir(sequencer_dir):
            todo_file = os.path.join(sequencer_dir, "todo")
            if os.path.exists(todo_file):
                try:
                    with open(todo_file, "r") as f:
                        first_line = f.readline()
                    if "pick" in first_line:
                        return "cherry-pick"
                    if "revert" in first_line:
                        return "revert"
                except OSError:
                    pass
        return None

    # ── Undo / Revert Commit ──

    async def undo_commit(self, mode: str = "soft") -> dict:
        """Undo the last commit (git reset HEAD~1).

        Mirrors JetBrains' "Undo Commit" — removes the most recent commit
        and puts changes back according to the mode. Also returns the
        undone commit's message so the UI can pre-fill the input box.

        Args:
            mode: Reset mode — "soft", "mixed", or "hard".
                - soft: keep changes in staged (index preserved)
                - mixed: keep changes in working dir (unstaged)
                - hard: discard all changes (destructive!)

        Returns:
            Dict with ``success``, ``message`` (undone commit msg),
            and ``error`` keys.
        """
        if mode not in ("soft", "mixed", "hard"):
            return {"success": False, "message": "", "error": f"Invalid mode: {mode}"}

        # Get the commit message before resetting (for UI pre-fill)
        msg_out, _, msg_code = await self._run(
            "log", "-1", "--pretty=format:%s",
        )
        commit_message = msg_out.strip() if msg_code == 0 else ""

        logger.info(f"撤销提交: mode={mode}, message={commit_message[:50]}")

        args = ["reset", f"--{mode}", "HEAD~1"]
        out, err, code = await self._run(*args)
        if code != 0:
            logger.error(f"撤销提交失败: mode={mode}, error={err}")
            return {"success": False, "message": "", "error": err.strip()[:500] if err else ""}

        logger.info(f"撤销提交成功: mode={mode}")
        return {"success": True, "message": commit_message, "error": ""}

    async def revert_commit(self, commit_hash: str, no_commit: bool = False) -> dict:
        """Revert a commit by creating a new reverse commit.

        Automatically detects merge commits and applies --mainline 1
        (treating the first parent as mainline). This mirrors JetBrains'
        behavior: the IDE handles the -m flag transparently so the user
        never sees the raw "is a merge but no -m option" error.

        Args:
            commit_hash: Hash of the commit to revert.
            no_commit: If True, apply revert changes to staging area
                without auto-committing (--no-commit flag). Lets user
                modify or combine with other changes before committing.

        Returns:
            Dict with ``success``, ``has_conflicts`` (bool), and ``error`` keys.
            If has_conflicts is True, user needs to resolve conflicts.
        """
        logger.info(
            f"还原提交: hash={commit_hash[:12]}, no_commit={no_commit}"
        )

        # Detect merge commit by counting parents
        is_merge = await self._is_merge_commit(commit_hash)
        if is_merge:
            logger.info(f"检测到 merge commit，自动添加 --mainline 1: hash={commit_hash[:12]}")

        args = ["revert", "--no-edit"]
        if no_commit:
            args.append("--no-commit")
        if is_merge:
            args.extend(["-m", "1"])
        args.append(commit_hash)

        out, err, code = await self._run(*args)

        if code != 0:
            # Check if failure is due to conflicts
            conflict_indicators = ["CONFLICT (", "Merge conflict in"]
            has_conflicts = any(ind in (out + err) for ind in conflict_indicators)

            if has_conflicts:
                logger.warning(f"还原提交产生冲突: hash={commit_hash[:12]}")
                return {
                    "success": False,
                    "has_conflicts": True,
                    "error": (out + err).strip()[:500] if (out + err).strip() else "",
                }

            logger.error(f"还原提交失败: hash={commit_hash[:12]}, error={err}")
            return {
                "success": False,
                "has_conflicts": False,
                "error": (err or out).strip()[:500] if (err or out) else "",
            }

        logger.info(f"还原提交成功: hash={commit_hash[:12]}")
        return {"success": True, "has_conflicts": False, "error": ""}

    async def _is_merge_commit(self, commit_hash: str) -> bool:
        """Check if a commit is a merge commit (has more than one parent).

        Uses `git cat-file -p <hash>` and counts 'parent' lines.
        Falls back to False on any error to avoid blocking the revert.
        """
        out, _, code = await self._run("cat-file", "-p", commit_hash)
        if code != 0:
            return False
        parent_count = sum(1 for line in out.splitlines() if line.startswith("parent "))
        return parent_count > 1

    # ── Cherry-pick ──

    async def cherry_pick(self, commit_hash: str, no_commit: bool = False) -> dict:
        """Cherry-pick a commit onto the current branch.

        Applies the changes from the specified commit to the current HEAD.
        Automatically detects merge commits and applies --mainline 1.

        Args:
            commit_hash: Hash of the commit to cherry-pick.
            no_commit: If True, apply changes to staging area without
                auto-committing (--no-commit flag).

        Returns:
            Dict with ``success``, ``has_conflicts`` (bool), and ``error`` keys.
        """
        logger.info(
            f"Cherry-pick: hash={commit_hash[:12]}, no_commit={no_commit}"
        )

        is_merge = await self._is_merge_commit(commit_hash)
        if is_merge:
            logger.info(f"检测到 merge commit，自动添加 --mainline 1: hash={commit_hash[:12]}")

        args = ["cherry-pick"]
        if no_commit:
            args.append("--no-commit")
        if is_merge:
            args.extend(["-m", "1"])
        args.append(commit_hash)

        out, err, code = await self._run(*args)

        if code != 0:
            combined = (out + err).strip()
            conflict_indicators = ["CONFLICT (", "Merge conflict in"]
            has_conflicts = any(ind in combined for ind in conflict_indicators)

            if has_conflicts:
                logger.warning(f"Cherry-pick 产生冲突: hash={commit_hash[:12]}")
                return {
                    "success": False,
                    "has_conflicts": True,
                    "error": combined[:500],
                }

            # Auto-cleanup: if cherry-pick is empty or failed, abort residual state
            empty_indicators = ["cherry-pick is now empty", "nothing to commit"]
            is_empty = any(ind in combined for ind in empty_indicators)
            if is_empty:
                logger.info(f"Cherry-pick 为空，自动清理: hash={commit_hash[:12]}")
                await self._run("cherry-pick", "--abort")
                return {
                    "success": False,
                    "has_conflicts": False,
                    "is_empty": True,
                    "error": combined[:500] if combined else "",
                }

            logger.error(f"Cherry-pick 失败: hash={commit_hash[:12]}, error={err}")
            return {
                "success": False,
                "has_conflicts": False,
                "is_empty": False,
                "error": combined[:500] if combined else "",
            }

        logger.info(f"Cherry-pick 成功: hash={commit_hash[:12]}")
        return {"success": True, "has_conflicts": False, "error": ""}
