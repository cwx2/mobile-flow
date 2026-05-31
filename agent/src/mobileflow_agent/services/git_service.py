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
    log, discard, repository discovery, and safe command execution.
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
class GitBranch:
    """Branch metadata.

    Attributes:
        name: Branch name (without ``remotes/`` prefix for remote branches).
        current: Whether this is the currently checked-out branch.
        remote: Whether this is a remote-tracking branch.
    """
    name: str
    current: bool
    remote: bool = False

    def to_dict(self) -> dict:
        """Serialise to a JSON-compatible dict."""
        return {"name": self.name, "current": self.current, "remote": self.remote}


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
        ahead: Number of local commits not yet pushed to remote.
        behind: Number of remote commits not yet pulled locally.
        error: Error message (empty on success).
    """
    branch: str = ""
    staged: list[GitFileStatus] = field(default_factory=list)
    unstaged: list[GitFileStatus] = field(default_factory=list)
    untracked: list[GitFileStatus] = field(default_factory=list)
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
            return {"diff": "", "error": err.split("\n")[0] if err else ""}
        return {"diff": out, "error": ""}

    async def file_content_for_diff(self, path: str, staged: bool = False) -> dict:
        """Get old and new file content for a side-by-side diff viewer.

        ``old_content`` is the HEAD version; ``new_content`` is either the
        staged version or the current on-disk content.

        Args:
            path: Relative file path.
            staged: If True, ``new_content`` comes from the index.

        Returns:
            Dict with ``old_content``, ``new_content``, and ``error`` keys.
        """
        # old: HEAD version
        old_out, old_err, old_code = await self._run("show", f"HEAD:{path}")
        old_content = old_out if old_code == 0 else ""

        if staged:
            # Staged: index version
            new_out, _, new_code = await self._run("show", f":{path}")
            new_content = new_out if new_code == 0 else ""
        else:
            # Unstaged: current on-disk content
            import os
            full_path = os.path.join(self._cwd, path)
            try:
                with open(full_path, "r", encoding="utf-8") as f:
                    new_content = f.read()
            except Exception:
                new_content = ""

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
            return {"diff": "", "error": err.split("\n")[0] if err else ""}
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
            return {"success": False, "error": err.split("\n")[0] if err else ""}
        return {"success": True, "error": ""}

    async def stage_all(self) -> dict:
        """Stage all changes (``git add -A``).

        Returns:
            Dict with ``success`` and ``error`` keys.
        """
        out, err, code = await self._run("add", "-A")
        if code != 0:
            return {"success": False, "error": err.split("\n")[0] if err else ""}
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
            return {"success": False, "error": err.split("\n")[0] if err else ""}
        return {"success": True, "error": ""}

    async def unstage_all(self) -> dict:
        """Unstage all staged changes (``git reset HEAD``).

        Returns:
            Dict with ``success`` and ``error`` keys.
        """
        out, err, code = await self._run("reset", "HEAD")
        if code != 0:
            return {"success": False, "error": err.split("\n")[0] if err else ""}
        return {"success": True, "error": ""}

    # ── Commit ──

    async def commit(self, message: str) -> dict:
        """Create a commit with the given message.

        Args:
            message: Commit message text.

        Returns:
            Dict with ``success``, ``output``, and ``error`` keys.
        """
        if not message.strip():
            return {"success": False, "error": t("backend.gitCommitEmpty")}
        logger.info(f"git commit: message={message[:50]}")
        out, err, code = await self._run("commit", "-m", message)
        if code != 0:
            logger.error(f"git commit 失败: {err.split(chr(10))[0] if err else ''}")
            return {"success": False, "error": err.split("\n")[0] if err else ""}
        return {"success": True, "output": out.strip(), "error": ""}

    # ── Push / Pull ──

    async def push(self) -> dict:
        """Push commits to the remote.

        Returns:
            Dict with ``success``, ``output``, ``up_to_date``, and ``error`` keys.
        """
        out, err, code = await self._run("push", timeout=self._command_timeout)
        if code != 0:
            logger.error(f"git push 失败: {err.split(chr(10))[0] if err else ''}")
            return {"success": False, "up_to_date": False, "error": err.split("\n")[0] if err else ""}
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
            return {"success": False, "up_to_date": False, "error": err.split("\n")[0] if err else ""}
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
            return {"success": False, "error": err.split("\n")[0] if err else ""}
        logger.debug("git fetch 成功")
        return {"success": True, "output": (out + err).strip(), "error": ""}

    # ── Branch ──

    async def branches(self) -> dict:
        """List all local and remote branches.

        Returns:
            Dict with ``branches`` (list of branch dicts) and ``error`` keys.
        """
        out, err, code = await self._run("branch", "-a", "--no-color")
        if code != 0:
            return {"branches": [], "error": err.split("\n")[0] if err else ""}
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
            return {"success": False, "error": err.split("\n")[0] if err else ""}
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
            return {"entries": [], "has_more": False, "error": err.split("\n")[0] if err else ""}
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
            return {"error": err.split("\n")[0] if err else "unknown error"}

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
            return {"success": False, "error": err.split("\n")[0] if err else ""}
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
