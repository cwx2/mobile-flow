"""Context reference resolution service for AI prompts.

Resolves structured context references (files, folders, git diffs, terminal
output, URLs, diagnostics) into formatted text blocks that get prepended
to user messages before forwarding to the AI CLI provider.

The App sends lightweight reference descriptors via the ``context_references``
field in ``chat.send``; this module resolves them to actual content on the
Agent side, keeping the App thin (zero data storage principle).

Models defined here (``LineRangeModel``, ``ContextReferenceModel``) mirror
the Dart ``ContextReference`` / ``LineRange`` classes and are deserialized
from the ``context_references`` array in the ``chat.send`` payload.

The ``ContextResolver`` class uses ``FileService`` for file operations,
``GitService`` for diffs, and enforces token budget limits from
``ContextConfig``.
"""

from __future__ import annotations

import asyncio
import math
import os
from pathlib import Path
from typing import TYPE_CHECKING, Literal, Optional

from loguru import logger
from pydantic import BaseModel

if TYPE_CHECKING:
    from ..core.config import ContextConfig
    from .file_service import FileService
    from .git_service import GitService


class LineRangeModel(BaseModel):
    """Line range for file context references.

    Represents a contiguous range of lines within a file, used when the
    user wants to reference only a specific section (e.g., lines 42-50)
    rather than the entire file.

    Both ``start`` and ``end`` are 1-indexed and inclusive, matching the
    line numbers displayed in editors.

    Args:
        start: First line number to include (1-indexed, inclusive).
        end: Last line number to include (1-indexed, inclusive).
    """

    start: int
    end: int


class ContextReferenceModel(BaseModel):
    """Structured context reference from the App.

    Deserialized from the ``context_references`` array in the ``chat.send``
    payload. Each instance describes one code artifact the user wants to
    attach to their chat message.

    The ``type`` field determines how the reference is resolved:
    - ``file``: read file content (optionally restricted by ``line_range``)
    - ``folder``: generate a directory tree listing
    - ``git-diff``: fetch staged + unstaged diffs
    - ``terminal``: last N lines of terminal output
    - ``url``: passthrough URL for the AI
    - ``problems``: current diagnostic errors/warnings
    - ``current-file``: resolve using the currently viewed file path

    Args:
        type: Reference kind, determines the resolution strategy.
        path: File/folder path or URL. Empty string for types that
            don't require a path (terminal, problems, git-diff).
        line_range: Optional line range for file references. When set,
            only the specified lines are included in the resolved output.
    """

    type: Literal[
        "file", "folder", "git-diff", "terminal",
        "url", "problems", "current-file",
    ]
    path: str = ""
    line_range: Optional[LineRangeModel] = None

# File extension → language identifier for fenced code blocks.
# Language detection — shared utility (no circular import risk)
from ..utils.lang import LANG_MAP as _LANG_MAP

# First 8 KB are sampled for null-byte binary detection.
_BINARY_CHECK_SIZE = 8192

# UTF-8 BOM prefix (EF BB BF).
_UTF8_BOM = b"\xef\xbb\xbf"


class ContextResolver:
    """Resolve context references into formatted text for AI prompts.

    Stateless service that reads file content, generates folder trees,
    fetches git diffs, and serializes everything into a markdown-formatted
    text block prepended to the user message.

    All errors are caught and logged — the resolver never aborts the
    message. Unresolvable references produce descriptive skip notes so
    the AI still sees what was intended.

    Args:
        config: Context resolution settings (token budget, limits).
        file_service: File system abstraction for reading files.
        git_service: Git operations for fetching diffs.
        terminal_outputs: Mapping of terminal ID → list of output lines,
            maintained by the terminal manager.
        work_dir: Absolute path to the project working directory, used
            for symlink escape detection.
    """

    def __init__(
        self,
        config: ContextConfig,
        file_service: FileService,
        git_service: GitService,
        terminal_outputs: dict[str, list[str]],
        work_dir: Path,
    ) -> None:
        self._config = config
        self._file_service = file_service
        self._git_service = git_service
        self._terminal_outputs = terminal_outputs
        self._work_dir = work_dir.resolve()

    # ── Public API ──

    async def resolve(
        self,
        references: list[ContextReferenceModel],
        current_file: str | None = None,
    ) -> str:
        """Resolve all references and return formatted context text.

        Processes references in declaration order, resolves each one to
        a markdown text block, then applies the token budget by truncating
        from the last reference when the total exceeds the limit.

        Args:
            references: Ordered list of context reference descriptors
                from the ``chat.send`` payload.
            current_file: Path of the file currently viewed in the App
                editor, used to resolve ``current-file`` references.

        Returns:
            Combined markdown text ready to prepend to the user message.
            Empty string when no references resolve successfully.
        """
        logger.debug(
            f"上下文解析开始: references={len(references)}, "
            f"current_file={current_file!r}"
        )

        # Cap references to configured maximum
        refs = references[: self._config.max_references]
        if len(references) > self._config.max_references:
            logger.warning(
                f"上下文引用超出上限，截断: "
                f"received={len(references)}, max={self._config.max_references}"
            )

        # Resolve all references in parallel — each resolver handles its
        # own errors so gather(return_exceptions=True) catches only
        # unexpected failures (e.g. cancelled tasks).
        async def _resolve_with_index(i: int, ref: ContextReferenceModel) -> tuple[int, str]:
            logger.debug(f"解析引用 {i + 1}/{len(refs)}: type={ref.type}, path={ref.path!r}")
            text = await self._resolve_single(ref, current_file)
            if text:
                logger.debug(f"引用 {i + 1} 解析完成: tokens={self._estimate_tokens(text)}")
            return (i, text)

        results = await asyncio.gather(
            *[_resolve_with_index(i, ref) for i, ref in enumerate(refs)],
            return_exceptions=True,
        )

        # Collect results in original order (important for deterministic
        # token budget truncation — first-declared references win).
        # asyncio.gather preserves order, but we sort by index explicitly
        # to be robust against future refactors.
        items: list[tuple[str, int]] = []
        valid_results = sorted(
            [r for r in results if not isinstance(r, Exception)],
            key=lambda r: r[0],
        )
        for result in results:
            if isinstance(result, Exception):
                logger.warning(f"上下文引用并行解析异常: error={result}")
                continue
        for idx, text in valid_results:
            if text:
                tokens = self._estimate_tokens(text)
                items.append((text, tokens))

        if not items:
            logger.debug("无有效上下文引用，返回空字符串")
            return ""

        # Apply token budget
        result = self._apply_token_budget(items)
        total_tokens = self._estimate_tokens(result)
        logger.info(f"上下文解析完成: blocks={len(items)}, tokens≈{total_tokens}")
        return result

    # ── Dispatch ──

    async def _resolve_single(
        self,
        ref: ContextReferenceModel,
        current_file: str | None,
    ) -> str:
        """Dispatch a single reference to the appropriate resolver.

        Never raises — all exceptions are caught and converted to
        descriptive skip notes.

        Args:
            ref: The context reference to resolve.
            current_file: Currently viewed file path (for current-file type).

        Returns:
            Formatted markdown block, or empty string on failure.
        """
        try:
            match ref.type:
                case "file":
                    return await self._resolve_file(ref)
                case "folder":
                    return await self._resolve_folder(ref)
                case "git-diff":
                    return await self._resolve_git_diff(ref)
                case "terminal":
                    return self._resolve_terminal(ref)
                case "url":
                    return self._resolve_url(ref)
                case "problems":
                    return self._resolve_problems(ref)
                case "current-file":
                    return await self._resolve_current_file(ref, current_file)
                case _:
                    logger.warning(f"未知引用类型: type={ref.type}")
                    return ""
        except Exception as e:
            logger.warning(f"上下文引用解析失败: type={ref.type}, path={ref.path!r}, error={e}")
            return ""

    # ── Per-type resolvers ──

    async def _resolve_file(self, ref: ContextReferenceModel) -> str:
        """Resolve a file reference to formatted markdown.

        Handles binary detection, BOM stripping, encoding fallback,
        line range extraction, symlink escape, empty files, large file
        truncation, permission errors, and missing files.

        Args:
            ref: File context reference with path and optional line_range.

        Returns:
            Serialized markdown block, or a skip-note block on error.
        """
        path_str = ref.path
        if not path_str:
            return ""

        target = self._work_dir / path_str

        # Symlink escape check — resolve to real path and verify it
        # stays within the project root to prevent data exfiltration.
        try:
            real_path = target.resolve()
        except OSError as e:
            logger.warning(f"路径解析失败: path={path_str!r}, error={e}")
            return self._serialize("file", path_str, f"⚠ File not found: {path_str}")

        if not self._is_within_work_dir(real_path):
            logger.warning(f"符号链接逃逸项目根目录: path={path_str!r}, real={real_path}")
            return self._serialize("file", path_str, f"⚠ Symlink outside project: {path_str}")

        # Read raw bytes — offload to thread pool to avoid blocking
        # the event loop on large files or slow filesystems.
        try:
            raw = await asyncio.to_thread(real_path.read_bytes)
        except PermissionError:
            logger.warning(f"文件权限不足: path={path_str!r}")
            return self._serialize("file", path_str, f"⚠ Permission denied: {path_str}")
        except FileNotFoundError:
            logger.warning(f"文件不存在: path={path_str!r}")
            return self._serialize("file", path_str, f"⚠ File not found: {path_str}")
        except OSError as e:
            logger.warning(f"文件读取失败: path={path_str!r}, error={e}")
            return self._serialize("file", path_str, f"⚠ File not found: {path_str}")

        # Empty file
        if len(raw) == 0:
            lang = self._detect_language(path_str)
            return self._serialize("file", path_str, "(empty file)", language=lang)

        # Binary detection — check first 8 KB for null bytes.
        # Null bytes are a reliable indicator of binary content
        # (images, compiled artifacts, etc.) that would pollute the prompt.
        if b"\x00" in raw[:_BINARY_CHECK_SIZE]:
            logger.debug(f"二进制文件跳过: path={path_str!r}")
            return self._serialize("file", path_str, f"⚠ Binary file, content not included: {path_str}")

        # Large file truncation — cap at max_file_size to prevent
        # a single huge file from consuming the entire token budget.
        truncated = False
        if len(raw) > self._config.max_file_size:
            raw = raw[: self._config.max_file_size]
            truncated = True
            logger.debug(f"大文件截断: path={path_str!r}, size={len(raw)}")

        # BOM stripping — UTF-8 BOM is common in Windows-edited files
        # and would appear as garbage characters in the prompt.
        if raw.startswith(_UTF8_BOM):
            raw = raw[len(_UTF8_BOM):]

        # Decode: try UTF-8 first, fallback to latin-1 (never fails),
        # skip only if both somehow fail (shouldn't happen with latin-1).
        content: str | None = None
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            try:
                content = raw.decode("latin-1")
                logger.debug(f"UTF-8 解码失败，使用 latin-1: path={path_str!r}")
            except Exception as e:
                logger.warning(f"文件编码解析失败: path={path_str!r}, error={e}")
                return self._serialize(
                    "file", path_str,
                    f"⚠ Unable to read file (encoding error): {path_str}",
                )

        if content is None:
            return self._serialize(
                "file", path_str,
                f"⚠ Unable to read file (encoding error): {path_str}",
            )

        # Line range extraction — 1-indexed inclusive on both ends,
        # matching editor line numbers shown to the user.
        if ref.line_range is not None:
            lines = content.splitlines(keepends=True)
            start = max(1, ref.line_range.start) - 1  # convert to 0-indexed
            end = min(len(lines), ref.line_range.end)
            content = "".join(lines[start:end])
            path_display = f"{path_str} (lines {ref.line_range.start}-{ref.line_range.end})"
        else:
            path_display = path_str

        if truncated:
            content += "\n... (truncated, file exceeds size limit)"

        lang = self._detect_language(path_str)
        return self._serialize("file", path_display, content, language=lang)

    async def _resolve_folder(self, ref: ContextReferenceModel) -> str:
        """Resolve a folder reference to a directory tree listing.

        Generates an indented tree structure using os.walk, respecting
        the configured max_folder_depth. Hidden directories and common
        noise directories (.git, node_modules, __pycache__) are excluded
        via FileService's ignore rules.

        The synchronous directory walk is offloaded to a thread pool
        via asyncio.to_thread to avoid blocking the event loop on
        large directory trees or network-mounted filesystems.

        Args:
            ref: Folder context reference with path.

        Returns:
            Serialized markdown block with the directory tree.
        """
        path_str = ref.path
        if not path_str:
            return ""

        target = self._work_dir / path_str

        if not target.is_dir():
            logger.warning(f"文件夹不存在: path={path_str!r}")
            return self._serialize("folder", path_str, f"⚠ Folder not found: {path_str}")

        try:
            # Offload synchronous directory walk to thread pool
            tree = await asyncio.to_thread(
                self._build_tree, target, self._config.max_folder_depth
            )
        except PermissionError:
            logger.warning(f"文件夹权限不足: path={path_str!r}")
            return self._serialize("folder", path_str, f"⚠ Permission denied: {path_str}")
        except Exception as e:
            logger.warning(f"文件夹树生成失败: path={path_str!r}, error={e}")
            return self._serialize("folder", path_str, f"⚠ Unable to list folder: {path_str}")

        return self._serialize("folder", path_str, tree)

    def _build_tree(self, root: Path, max_depth: int) -> str:
        """Build an indented directory tree string.

        Uses os.walk with depth tracking. Entries at each level are
        sorted alphabetically (directories first, then files) for
        deterministic output.

        Args:
            root: Absolute path to the directory root.
            max_depth: Maximum depth to recurse (0 = root only).

        Returns:
            Indented tree string with ├── and └── connectors.
        """
        lines: list[str] = [root.name + "/"]
        self._walk_tree(root, "", max_depth, 0, lines)
        return "\n".join(lines)

    def _walk_tree(
        self,
        directory: Path,
        prefix: str,
        max_depth: int,
        current_depth: int,
        lines: list[str],
    ) -> None:
        """Recursively walk a directory and append tree lines.

        Args:
            directory: Current directory to list.
            prefix: Indentation prefix for the current level.
            max_depth: Maximum depth to recurse.
            current_depth: Current recursion depth (0 = root children).
            lines: Accumulator list for tree lines.
        """
        if current_depth >= max_depth:
            return

        try:
            entries = sorted(directory.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower()))
        except PermissionError:
            return

        # Filter out ignored entries using FileService's ignore logic
        visible = [
            e for e in entries
            if not self._file_service._should_ignore(e.name, is_dir=e.is_dir())
        ]

        for i, entry in enumerate(visible):
            is_last = i == len(visible) - 1
            connector = "└── " if is_last else "├── "
            suffix = "/" if entry.is_dir() else ""
            lines.append(f"{prefix}{connector}{entry.name}{suffix}")

            if entry.is_dir():
                # Extend prefix for children: use space if last, else vertical bar
                extension = "    " if is_last else "│   "
                self._walk_tree(entry, prefix + extension, max_depth, current_depth + 1, lines)

    async def _resolve_git_diff(self, ref: ContextReferenceModel) -> str:
        """Resolve a git-diff reference to staged and unstaged diffs.

        Fetches both staged and unstaged diffs in parallel via
        asyncio.gather to halve the wall-clock time. Each diff is
        independent so parallel execution is safe.

        Args:
            ref: Git-diff context reference (path is ignored).

        Returns:
            Serialized markdown block with both diff sections.
        """
        # Fetch both diffs in parallel — they are independent git operations
        unstaged_task = self._git_service.diff_all(staged=False)
        staged_task = self._git_service.diff_all(staged=True)

        unstaged_result, staged_result = await asyncio.gather(
            unstaged_task, staged_task, return_exceptions=True
        )

        parts: list[str] = []

        # Process unstaged changes
        if isinstance(unstaged_result, Exception):
            logger.warning(f"Git unstaged diff 获取失败: error={unstaged_result}")
            parts.append(self._serialize(
                "git-diff-unstaged", "", f"⚠ Git diff unavailable: {unstaged_result}"
            ))
        else:
            unstaged_diff = unstaged_result.get("diff", "")
            unstaged_err = unstaged_result.get("error", "")
            if unstaged_err:
                logger.warning(f"Git unstaged diff 错误: {unstaged_err}")
            if unstaged_diff:
                parts.append(self._serialize("git-diff-unstaged", "", unstaged_diff))
            else:
                parts.append(self._serialize("git-diff-unstaged", "", "(no unstaged changes)"))

        # Process staged changes
        if isinstance(staged_result, Exception):
            logger.warning(f"Git staged diff 获取失败: error={staged_result}")
            parts.append(self._serialize(
                "git-diff-staged", "", f"⚠ Git diff unavailable: {staged_result}"
            ))
        else:
            staged_diff = staged_result.get("diff", "")
            staged_err = staged_result.get("error", "")
            if staged_err:
                logger.warning(f"Git staged diff 错误: {staged_err}")
            if staged_diff:
                parts.append(self._serialize("git-diff-staged", "", staged_diff))
            else:
                parts.append(self._serialize("git-diff-staged", "", "(no staged changes)"))

        return "\n".join(parts)

    def _resolve_terminal(self, ref: ContextReferenceModel) -> str:
        """Resolve a terminal reference to the last N output lines.

        Collects output from all terminal sessions and takes the last
        ``max_terminal_lines`` lines. If no terminal output exists,
        returns a note indicating empty output.

        Args:
            ref: Terminal context reference (path is ignored).

        Returns:
            Serialized markdown block with terminal output.
        """
        # Collect all terminal output lines across sessions
        all_lines: list[str] = []
        for _tid, lines in self._terminal_outputs.items():
            all_lines.extend(lines)

        if not all_lines:
            return self._serialize("terminal", "", "(no terminal output)")

        # Take last N lines as configured
        max_lines = self._config.max_terminal_lines
        tail = all_lines[-max_lines:] if len(all_lines) > max_lines else all_lines
        content = "\n".join(tail)
        return self._serialize("terminal", "", content)

    def _resolve_url(self, ref: ContextReferenceModel) -> str:
        """Resolve a URL reference as a passthrough.

        The URL is included as-is for the AI to reference or fetch.
        No HTTP request is made on the Agent side.

        Args:
            ref: URL context reference with the URL in path field.

        Returns:
            Serialized markdown block with the URL.
        """
        url = ref.path
        if not url:
            return ""
        return self._serialize("url", url, url)

    def _resolve_problems(self, ref: ContextReferenceModel) -> str:
        """Resolve a problems/diagnostics reference.

        Currently a placeholder that returns a note. Full diagnostic
        integration requires LSP or build tool output, which will be
        added when the diagnostics pipeline is implemented.

        Args:
            ref: Problems context reference (path is ignored).

        Returns:
            Serialized markdown block with diagnostic info or placeholder.
        """
        return self._serialize(
            "problems", "",
            "(diagnostics not yet available — feature pending)",
        )

    async def _resolve_current_file(
        self,
        ref: ContextReferenceModel,
        current_file: str | None,
    ) -> str:
        """Resolve a current-file reference by delegating to _resolve_file.

        Uses the currently viewed file path from the App. If no current
        file is known, returns a descriptive note.

        Args:
            ref: Current-file context reference.
            current_file: Path of the file currently open in the App editor.

        Returns:
            Serialized markdown block with the file content.
        """
        if not current_file:
            logger.debug("当前文件引用无法解析: current_file 为空")
            return self._serialize(
                "file", "(current file)",
                "⚠ No file currently open in editor",
            )

        # Delegate to _resolve_file with the current file path
        file_ref = ContextReferenceModel(
            type="file",
            path=current_file,
            line_range=ref.line_range,
        )
        return await self._resolve_file(file_ref)

    # ── Serialization ──

    def _serialize(
        self,
        ref_type: str,
        path: str,
        content: str,
        language: str = "",
    ) -> str:
        """Format a resolved reference as a markdown block.

        Each reference type has a distinct header and body format so the
        AI can reliably parse the context structure.

        Args:
            ref_type: Reference type string (file, folder, git-diff-*, etc.).
            path: Display path or URL for the header.
            content: Resolved content body.
            language: Language identifier for fenced code blocks (files only).

        Returns:
            Formatted markdown string.
        """
        if ref_type == "file":
            return f"## File: {path}\n\n```{language}\n{content}\n```\n"

        if ref_type == "folder":
            return f"## Folder: {path}\n\n{content}\n"

        if ref_type == "git-diff-unstaged":
            return f"## Git Diff (unstaged)\n\n```diff\n{content}\n```\n"

        if ref_type == "git-diff-staged":
            return f"## Git Diff (staged)\n\n```diff\n{content}\n```\n"

        if ref_type == "terminal":
            return f"## Terminal Output\n\n```\n{content}\n```\n"

        if ref_type == "url":
            return f"## URL: {path}\n\nReference: {path}\n"

        if ref_type == "problems":
            return f"## Diagnostics\n\n```\n{content}\n```\n"

        # Fallback for unknown types
        return f"## {ref_type}: {path}\n\n{content}\n"

    # ── Token budget ──

    def _estimate_tokens(self, text: str) -> int:
        """Estimate token count from text length.

        Uses a simple characters-per-token ratio from config. This is
        intentionally approximate — exact tokenization would require
        loading a model-specific tokenizer, which is overkill for
        budget enforcement.

        Args:
            text: Text to estimate tokens for.

        Returns:
            Estimated token count (always ≥ 0).
        """
        if not text:
            return 0
        return math.ceil(len(text) / self._config.chars_per_token)

    def _apply_token_budget(self, items: list[tuple[str, int]]) -> str:
        """Apply token budget by truncating from the last reference.

        Processes items in order, accumulating tokens. When the budget
        would be exceeded, remaining items are dropped and a truncation
        note is appended to the last included item.

        Args:
            items: List of (text, estimated_tokens) tuples in reference order.

        Returns:
            Combined text fitting within the token budget.
        """
        budget = self._config.token_budget
        result_parts: list[str] = []
        used_tokens = 0

        for text, tokens in items:
            if used_tokens + tokens <= budget:
                result_parts.append(text)
                used_tokens += tokens
            else:
                # Remaining budget in characters
                remaining_chars = int((budget - used_tokens) * self._config.chars_per_token)
                if remaining_chars > 0:
                    # Truncate this block to fit remaining budget
                    truncated_text = text[:remaining_chars]
                    truncated_text += "\n\n... (truncated due to token budget)\n"
                    result_parts.append(truncated_text)
                    logger.debug(
                        f"Token 预算截断: used={used_tokens}, budget={budget}, "
                        f"truncated_block_chars={remaining_chars}"
                    )
                else:
                    # No room left — add a note about skipped references
                    result_parts.append(
                        "\n... (remaining context references truncated due to token budget)\n"
                    )
                    logger.debug(f"Token 预算耗尽，跳过剩余引用: used={used_tokens}, budget={budget}")
                # Stop processing further items
                break

        return "\n".join(result_parts)

    # ── Helpers ──

    def _detect_language(self, path: str) -> str:
        """Detect programming language from file extension.

        Used to set the language identifier on fenced code blocks so
        the AI (and any markdown renderer) can apply syntax highlighting.

        Args:
            path: File path (only the extension is used).

        Returns:
            Language identifier string, or empty string if unknown.
        """
        ext = Path(path).suffix.lower()
        return _LANG_MAP.get(ext, "")

    def _is_within_work_dir(self, resolved_path: Path) -> bool:
        """Check whether a resolved path is within the project root.

        Used to detect symlink escape attacks where a symlink inside
        the project points to a file outside (e.g., /etc/passwd).

        Args:
            resolved_path: Fully resolved (real) path to check.

        Returns:
            True if the path is within or equal to work_dir.
        """
        try:
            resolved_path.relative_to(self._work_dir)
            return True
        except ValueError:
            return False
