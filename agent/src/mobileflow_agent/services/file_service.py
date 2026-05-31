"""File service for project file tree, read/write, and search operations.

Provides the file system abstraction layer used by the WebSocket handlers
to serve file tree browsing, content reading/writing, and both filename
and content search (with ripgrep acceleration when available).
"""

from __future__ import annotations

import asyncio
import fnmatch
import os
import posixpath
from pathlib import Path
from typing import Callable, Optional

from loguru import logger

from mobileflow_protocol.models import FileNode, FileReadResultPayload

from ..core.config import AgentConfig
from ..utils.encoding import decode_process_output

# Default ignored directories and files (only truly useless entries)
DEFAULT_IGNORE = {
    ".git", "node_modules", "__pycache__",
    ".DS_Store", "*.pyc", "*.pyo",
}

# File extension to language identifier mapping (shared utility)
from ..utils.lang import LANG_MAP
from ..utils.i18n import t


class FileService:
    """File operations service: tree browsing, read/write, and search.

    Attributes:
        config: Agent configuration.
        root: Resolved absolute path to the project working directory.
    """

    def __init__(self, config: AgentConfig):
        self.config = config
        if not config.work_dir:
            raise ValueError("FileService requires a non-empty work_dir")
        self.root = Path(config.work_dir).resolve()
        self._gitignore_patterns: list[str] = []
        self._load_gitignore()

        # File tree cache: "path:depth" → list of FileNode dicts
        # Invalidated by RefreshScheduler on file create/delete events
        self._tree_cache: dict[str, list] = {}

    def update_root(self, new_work_dir: str) -> None:
        """Switch to a new project directory.

        Updates the root path, reloads .gitignore patterns, and clears
        all cached data. Called by ProjectManager on project switch to
        avoid creating a new FileService instance (which would break
        references held by RefreshScheduler and other components).

        Args:
            new_work_dir: New working directory path.
        """
        self.root = Path(new_work_dir).resolve()
        self._gitignore_patterns = []
        self._load_gitignore()
        self._tree_cache.clear()

    def _load_gitignore(self):
        """Load .gitignore patterns from the project root."""
        gitignore = self.root / ".gitignore"
        if gitignore.exists():
            for line in gitignore.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    self._gitignore_patterns.append(line)

    def _should_ignore(self, name: str, is_dir: bool = False) -> bool:
        """Check whether a file or directory should be excluded from results.

        Args:
            name: File or directory name (not a full path).
            is_dir: Whether the entry is a directory.

        Returns:
            True if the entry should be ignored.
        """
        if name in DEFAULT_IGNORE:
            return True
        for pattern in self._gitignore_patterns:
            if fnmatch.fnmatch(name, pattern):
                return True
        return False

    def _resolve_path(self, rel_path: str) -> Path:
        """Resolve a relative path and guard against path traversal attacks.

        Args:
            rel_path: Relative path from the project root.

        Returns:
            Resolved absolute Path.

        Raises:
            PermissionError: If the resolved path escapes the project root.
        """
        if rel_path in ("", "/", "."):
            return self.root
        clean = rel_path.lstrip("/")
        resolved = (self.root / clean).resolve()
        # Security: prevent escaping the working directory
        if not str(resolved).startswith(str(self.root)):
            raise PermissionError(f"路径越界: {rel_path}")
        return resolved

    def get_tree(self, path: str = "/", depth: int = 2) -> list[FileNode]:
        """Get the file tree rooted at the given path (lazy, depth-limited).

        Args:
            path: Relative path to start from.
            depth: Maximum directory depth to scan.

        Returns:
            List of FileNode objects representing the tree.
        """
        target = self._resolve_path(path)
        if not target.is_dir():
            return []
        return self._scan_dir(target, depth)

    def _scan_dir(self, dir_path: Path, depth: int) -> list[FileNode]:
        """Recursively scan a directory and build FileNode entries.

        Args:
            dir_path: Absolute path to the directory.
            depth: Remaining depth levels to scan.

        Returns:
            List of FileNode objects for the directory contents.
        """
        if depth <= 0:
            return []

        nodes: list[FileNode] = []
        try:
            entries = sorted(dir_path.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower()))
        except PermissionError:
            return []

        for entry in entries:
            if self._should_ignore(entry.name, entry.is_dir()):
                continue

            if entry.is_dir():
                children = self._scan_dir(entry, depth - 1) if depth > 1 else None
                nodes.append(FileNode(
                    name=entry.name,
                    type="dir",
                    children=children,
                ))
            elif entry.is_file():
                try:
                    size = entry.stat().st_size
                except OSError:
                    size = 0
                nodes.append(FileNode(
                    name=entry.name,
                    type="file",
                    size=size,
                ))

        return nodes

    def get_tree_cached(self, path: str = "/", depth: int = 2) -> list:
        """Get file tree, using cache if available.

        Cache is invalidated by RefreshScheduler on file create/delete events.
        File modify events don't invalidate tree cache (structure unchanged).

        Args:
            path: Relative path to start from.
            depth: Maximum directory depth to scan.

        Returns:
            List of FileNode objects representing the tree.
        """
        key = f"{path}:{depth}"
        cached = self._tree_cache.get(key)
        if cached is not None:
            logger.debug(f"文件树缓存命中: {key}")
            return cached

        logger.debug(f"文件树缓存未命中，扫描: {key}")
        result = self.get_tree(path, depth)
        self._tree_cache[key] = result
        return result

    def invalidate_tree_cache(self, changed_path: str = "") -> None:
        """Invalidate file tree cache entries affected by a path change.

        Called by RefreshScheduler on file create/delete events.
        Modify events don't affect tree structure, so they don't invalidate.

        Args:
            changed_path: Relative path of the changed file.
                If empty, invalidates all cache entries.
        """
        if not changed_path or not self._tree_cache:
            count = len(self._tree_cache)
            self._tree_cache.clear()
            if count:
                logger.debug(f"文件树缓存全部清除: {count} 条")
            return

        # Invalidate entries whose scanned path could contain the changed file
        parent = posixpath.dirname(changed_path)
        to_remove = []
        for key in self._tree_cache:
            cache_path = key.split(":")[0]
            # Root scan or parent directory match
            if cache_path in ("", "/") or parent.startswith(cache_path.lstrip("/")):
                to_remove.append(key)
        for key in to_remove:
            del self._tree_cache[key]
        if to_remove:
            logger.debug(
                f"文件树缓存失效: {len(to_remove)} 条, trigger={changed_path}"
            )

    def clear_all_cache(self) -> None:
        """Clear all caches. Called on project switch."""
        self._tree_cache.clear()

    def read_file(self, path: str) -> FileReadResultPayload:
        """Read a file's content with large-file protection.

        Files larger than 2 MB are rejected to avoid freezing the mobile App.

        Args:
            path: Relative file path within the project.

        Returns:
            FileReadResultPayload with content, language, and line count.

        Raises:
            FileNotFoundError: If the file does not exist.
            IsADirectoryError: If the path points to a directory.
        """
        target = self._resolve_path(path)

        if not target.exists():
            raise FileNotFoundError(f"文件不存在: {path}")
        if not target.is_file():
            raise IsADirectoryError(f"不是文件: {path}")

        # Large file protection (2 MB)
        MAX_FILE_SIZE = 2 * 1024 * 1024
        try:
            file_size = target.stat().st_size
        except OSError:
            file_size = 0
        if file_size > MAX_FILE_SIZE:
            size_mb = file_size / (1024 * 1024)
            logger.warning(f"文件过大，拒绝读取: path={path}, size={size_mb:.1f}MB")
            return FileReadResultPayload(
                path=path,
                content=None,
                language=LANG_MAP.get(target.suffix.lower()),
                line_count=0,
                error=t("backend.fileTooLarge", size=f"{size_mb:.1f}"),
            )

        # Read with UTF-8, fall back to latin-1
        try:
            content = target.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            content = target.read_text(encoding="latin-1")

        lang = LANG_MAP.get(target.suffix.lower())

        return FileReadResultPayload(
            path=path,
            content=content,
            language=lang,
            line_count=content.count("\n") + 1,
        )

    def write_file(self, path: str, content: str) -> bool:
        """Write content to a file, creating parent directories as needed.

        Args:
            path: Relative file path within the project.
            content: File content to write.

        Returns:
            True on success, False on failure.
        """
        try:
            target = self._resolve_path(path)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
            logger.info(f"📝 写入文件: {path}")
            return True
        except Exception as e:
            logger.error(f"写入失败: {path} - {e}")
            return False

    def create_file(self, parent_path: str, name: str, file_type: str) -> dict:
        """Create a new file or directory.

        Args:
            parent_path: Relative path to the parent directory.
            name: Name of the new file or directory.
            file_type: ``"file"`` or ``"dir"``.

        Returns:
            Dict with ``success``, ``path`` (on success), or ``error`` keys.
        """
        try:
            target = self._resolve_path(parent_path) / name
            if target.exists():
                return {"success": False, "error": t("backend.fileAlreadyExists", kind=("folder" if file_type == "dir" else "file"), name=name)}
            if file_type == "dir":
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.touch()
            rel = str(target.relative_to(self.root)).replace("\\", "/")
            logger.info(f"📝 创建{file_type}: {rel}")
            return {"success": True, "path": rel}
        except PermissionError:
            return {"success": False, "error": t("backend.permissionDeniedFile", action="create", name=name)}
        except Exception as e:
            return {"success": False, "error": t("backend.createFailed", error=str(e))}

    def rename_file(self, path: str, new_name: str) -> dict:
        """Rename a file or directory.

        Args:
            path: Relative path to the existing file or directory.
            new_name: New name (not a full path).

        Returns:
            Dict with ``success``, ``old_path``, ``new_path``, or ``error`` keys.
        """
        try:
            target = self._resolve_path(path)
            if not target.exists():
                return {"success": False, "error": t("backend.fileNotExist", path=path)}
            new_target = target.parent / new_name
            if new_target.exists():
                return {"success": False, "error": t("backend.renameTargetExists", name=new_name)}
            target.rename(new_target)
            new_rel = str(new_target.relative_to(self.root)).replace("\\", "/")
            logger.info(f"📝 重命名: {path} → {new_rel}")
            return {"success": True, "old_path": path, "new_path": new_rel}
        except PermissionError:
            return {"success": False, "error": t("backend.permissionDeniedFile", action="rename", name=path)}
        except Exception as e:
            return {"success": False, "error": t("backend.renameFailed", error=str(e))}

    def delete_file(self, path: str) -> dict:
        """Delete a file or directory (recursively for directories).

        Args:
            path: Relative path to the file or directory.

        Returns:
            Dict with ``success``, ``path``, or ``error`` keys.
        """
        try:
            target = self._resolve_path(path)
            if not target.exists():
                return {"success": False, "error": t("backend.fileNotExist", path=path)}
            if target.is_dir():
                import shutil
                shutil.rmtree(target)
            else:
                target.unlink()
            logger.info(f"🗑️ 删除: {path}")
            return {"success": True, "path": path}
        except PermissionError:
            return {"success": False, "error": t("backend.permissionDeniedFile", action="delete", name=path)}
        except Exception as e:
            return {"success": False, "error": t("backend.deleteFailed", error=str(e))}

    async def search(self, query: str, search_content: bool = False,
                     cancel_event: asyncio.Event | None = None,
                     on_batch: Callable | None = None,
                     is_regex: bool = False,
                     case_sensitive: bool = False,
                     whole_word: bool = False) -> list[dict]:
        """Search for files by name or content.

        Mirrors the VS Code search architecture (``getRgArgs``):
        - ``is_regex``: regex search (VS Code ``.* `` button).
        - ``case_sensitive``: case-sensitive (VS Code ``Aa`` button).
        - ``whole_word``: whole-word match (VS Code ``ab`` button).

        Args:
            query: Search query string.
            search_content: If True, search file contents; otherwise filenames.
            cancel_event: Optional event to cancel the search.
            on_batch: Optional async callback for streaming result batches.
            is_regex: Enable regex matching.
            case_sensitive: Enable case-sensitive matching.
            whole_word: Enable whole-word matching.

        Returns:
            List of result dicts.
        """
        if search_content:
            return await self._search_content_async(
                query, cancel_event, on_batch,
                is_regex=is_regex, case_sensitive=case_sensitive, whole_word=whole_word,
            )
        logger.debug(f"文件名搜索: query={query!r}")
        results = await asyncio.to_thread(self._search_filename, query)
        if on_batch and results:
            await on_batch(results)
        return results

    def _search_filename(self, query: str) -> list[dict]:
        """Search for files by name (case-insensitive substring match).

        Args:
            query: Substring to match against file names.

        Returns:
            List of result dicts with ``path`` and ``type`` keys (max 50).
        """
        results: list[dict] = []
        query_lower = query.lower()

        for root, dirs, files in os.walk(self.root):
            dirs[:] = [d for d in dirs if not self._should_ignore(d, True)]
            for fname in files:
                if self._should_ignore(fname):
                    continue
                if query_lower in fname.lower():
                    try:
                        full_path = Path(root) / fname
                        rel_path = str(full_path.relative_to(self.root)).replace("\\", "/")
                        results.append({"path": rel_path, "type": "filename"})
                    except (OSError, ValueError):
                        continue
                    if len(results) >= 50:
                        return results
        return results

    async def _search_content_async(self, query: str,
                                     cancel_event: asyncio.Event | None = None,
                                     on_batch: Callable | None = None,
                                     is_regex: bool = False,
                                     case_sensitive: bool = False,
                                     whole_word: bool = False) -> list[dict]:
        """Content search: prefer ripgrep (streaming), fall back to Python.

        Args:
            query: Search query.
            cancel_event: Optional cancellation event.
            on_batch: Optional streaming batch callback.
            is_regex: Enable regex matching.
            case_sensitive: Enable case-sensitive matching.
            whole_word: Enable whole-word matching.

        Returns:
            List of result dicts.
        """
        from ..utils.command import which as which_cmd
        rg = which_cmd("rg")
        if rg:
            results = await self._search_content_ripgrep_stream(
                rg, query, cancel_event, on_batch,
                is_regex=is_regex, case_sensitive=case_sensitive, whole_word=whole_word,
            )
            if results is not None:
                return results
        # ripgrep unavailable or failed — fall back to Python
        results = await asyncio.to_thread(self._search_content_python, query)
        if on_batch and results:
            await on_batch(results)
        return results

    async def _search_content_ripgrep_stream(
        self, rg_path: str, query: str,
        cancel_event: asyncio.Event | None = None,
        on_batch: Callable | None = None,
        is_regex: bool = False,
        case_sensitive: bool = False,
        whole_word: bool = False,
    ) -> list[dict] | None:
        """Streaming ripgrep content search (VS Code RipgrepTextSearchEngine + getRgArgs).

        Key design points:
        - Launches rg via ``asyncio.create_subprocess_exec``.
        - Reads stdout line-by-line, parsing each match immediately.
        - Kills the process and returns once 50 results are collected.
        - Respects ``cancel_event`` for immediate cancellation.
        - rg automatically reads ``.gitignore`` — no hardcoded exclusions.
        - Arguments follow the VS Code ``getRgArgs`` pattern.

        Args:
            rg_path: Absolute path to the ripgrep binary.
            query: Search query.
            cancel_event: Optional cancellation event.
            on_batch: Optional streaming batch callback.
            is_regex: Enable regex matching.
            case_sensitive: Enable case-sensitive matching.
            whole_word: Enable whole-word matching.

        Returns:
            List of result dicts, or None to signal fallback to Python search.
        """
        import json as json_mod

        # Build rg arguments (VS Code getRgArgs pattern)
        rg_args = ["--json", "--max-filesize", "1M",
                    "--hidden", "--no-require-git", "--crlf", "--no-config"]
        rg_args.append("--case-sensitive" if case_sensitive else "--ignore-case")
        if whole_word:
            rg_args.append("--word-regexp")
        if not is_regex:
            rg_args.append("--fixed-strings")
        rg_args.extend(["--", query, str(self.root)])

        try:
            proc = await asyncio.create_subprocess_exec(
                rg_path, *rg_args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=str(self.root),
            )
        except Exception as e:
            logger.warning(f"ripgrep 启动失败：{e}")
            return None  # Fall back to Python

        results: list[dict] = []
        file_lines_cache: dict[str, list[str]] = {}
        remainder = ""

        try:
            while True:
                if cancel_event and cancel_event.is_set():
                    proc.kill()
                    return []

                # Non-blocking read (up to 64 KB per chunk)
                try:
                    chunk = await asyncio.wait_for(
                        proc.stdout.read(65536), timeout=self.config.timeouts.file_search_cancel
                    )
                except asyncio.TimeoutError:
                    # No data for 0.5 s — check cancellation and retry
                    if cancel_event and cancel_event.is_set():
                        proc.kill()
                        return []
                    continue

                if not chunk:
                    break  # EOF — rg process finished

                data = remainder + decode_process_output(chunk)
                lines = data.split("\n")
                remainder = lines[-1]  # Last line may be incomplete

                batch: list[dict] = []

                for line in lines[:-1]:
                    line = line.strip()
                    if not line:
                        continue

                    try:
                        obj = json_mod.loads(line)
                    except json_mod.JSONDecodeError:
                        continue

                    if obj.get("type") != "match":
                        continue

                    entry = self._parse_rg_match(obj, file_lines_cache)
                    if entry:
                        results.append(entry)
                        batch.append(entry)

                    # Hit the result cap — kill the process and return
                    if len(results) >= 50:
                        if on_batch and batch:
                            await on_batch(batch)
                        proc.kill()
                        return results

                # Push this batch to the App
                if on_batch and batch:
                    await on_batch(batch)

        except Exception as e:
            logger.warning(f"ripgrep 流式读取出错：{e}")
            proc.kill()
            if results:
                return results
            return None  # Fall back to Python

        # Process any remaining partial line
        if remainder.strip():
            try:
                obj = json_mod.loads(remainder.strip())
                if obj.get("type") == "match":
                    entry = self._parse_rg_match(obj, file_lines_cache)
                    if entry:
                        results.append(entry)
            except json_mod.JSONDecodeError:
                pass

        # Wait for the process to exit (avoid zombie processes)
        try:
            await asyncio.wait_for(proc.wait(), timeout=self.config.timeouts.file_search)
        except asyncio.TimeoutError:
            proc.kill()

        return results

    def _parse_rg_match(self, obj: dict, file_lines_cache: dict) -> dict | None:
        """Parse a ripgrep JSON match object into a search result dict.

        Follows the VS Code ``RipgrepParser.createTextSearchMatch`` pattern:
        extracts match positions from ``submatches`` and splits the line into
        ``before`` / ``inside`` / ``after`` segments for frontend highlighting.

        Args:
            obj: Parsed ripgrep JSON match object.
            file_lines_cache: Cache of file contents (path → lines) to avoid
                re-reading files for context lines.

        Returns:
            Search result dict, or None if parsing fails.
        """
        data = obj.get("data", {})
        path_obj = data.get("path", {})
        abs_path = path_obj.get("text", "") if isinstance(data.get("path"), dict) else ""
        # Handle bytes-encoded paths
        if not abs_path and isinstance(data.get("path"), dict):
            import base64
            abs_path = base64.b64decode(data["path"].get("bytes", "")).decode("utf-8", errors="replace")

        line_number = data.get("line_number", 0)
        lines_obj = data.get("lines", {})
        full_text = lines_obj.get("text", "")
        if not full_text and isinstance(lines_obj, dict) and "bytes" in lines_obj:
            import base64
            full_text = base64.b64decode(lines_obj["bytes"]).decode("utf-8", errors="replace")
        text = full_text.strip()[:200]

        try:
            rel_path = str(Path(abs_path).relative_to(self.root)).replace("\\", "/")
        except ValueError:
            rel_path = abs_path

        # Extract submatches (VS Code pattern) — each has start/end byte offsets
        submatches = data.get("submatches", [])
        match_ranges = []
        for sm in submatches:
            match_ranges.append({
                "start": sm.get("start", 0),
                "end": sm.get("end", 0),
            })

        # Split into before/inside/after (using the first submatch)
        before = ""
        inside = ""
        after = ""
        if match_ranges and full_text:
            first = match_ranges[0]
            before = full_text[:first["start"]].strip()
            inside = full_text[first["start"]:first["end"]]
            after = full_text[first["end"]:].strip()[:100]
            # Truncate long before-text
            if len(before) > 50:
                before = "..." + before[-50:]

        # Read context lines (one line above and below)
        ctx_before = ""
        ctx_after = ""
        try:
            if abs_path not in file_lines_cache:
                file_lines_cache[abs_path] = Path(abs_path).read_text(
                    encoding="utf-8", errors="replace"
                ).splitlines()
            all_lines = file_lines_cache[abs_path]
            idx = line_number - 1
            if idx > 0:
                ctx_before = all_lines[idx - 1].strip()[:200]
            if idx < len(all_lines) - 1:
                ctx_after = all_lines[idx + 1].strip()[:200]
        except Exception:
            pass

        return {
            "path": rel_path,
            "type": "content",
            "line": line_number,
            "text": text,
            "before": before,
            "inside": inside,
            "after": after,
            "match_ranges": match_ranges,
            "context_before": ctx_before,
            "context_after": ctx_after,
        }

    def _search_content_python(self, query: str) -> list[dict]:
        """Python fallback for content search (used when ripgrep is unavailable).

        Args:
            query: Search query (case-insensitive substring match).

        Returns:
            List of result dicts (max 50).
        """
        results: list[dict] = []
        query_lower = query.lower()

        for root, dirs, files in os.walk(self.root):
            dirs[:] = [d for d in dirs if not self._should_ignore(d, True)]
            for fname in files:
                if self._should_ignore(fname):
                    continue
                full_path = Path(root) / fname
                try:
                    if not full_path.is_file() or full_path.stat().st_size >= 1_000_000:
                        continue
                    lines = full_path.read_text(encoding="utf-8").splitlines()
                    for i, line in enumerate(lines):
                        if query_lower in line.lower():
                            rel_path = str(full_path.relative_to(self.root)).replace("\\", "/")
                            # Locate the match and split into before/inside/after
                            match_start = line.lower().find(query_lower)
                            match_end = match_start + len(query_lower)
                            before = line[:match_start].strip()
                            inside = line[match_start:match_end]
                            after = line[match_end:].strip()[:100]
                            if len(before) > 50:
                                before = "..." + before[-50:]
                            results.append({
                                "path": rel_path,
                                "type": "content",
                                "line": i + 1,
                                "text": line.strip()[:200],
                                "before": before,
                                "inside": inside,
                                "after": after,
                                "match_ranges": [{"start": match_start, "end": match_end}],
                                "context_before": lines[i - 1].strip()[:200] if i > 0 else "",
                                "context_after": lines[i + 1].strip()[:200] if i < len(lines) - 1 else "",
                            })
                            if len(results) >= 50:
                                return results
                except (UnicodeDecodeError, PermissionError, OSError):
                    pass
        return results
