"""Unit tests for ContextResolver — context reference resolution service.

Covers all resolver types (file, folder, git-diff, terminal, url),
parallel resolution, token budget enforcement, and async I/O behavior.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from mobileflow_agent.core.config import ContextConfig
from mobileflow_agent.services.context_resolver import (
    ContextReferenceModel,
    ContextResolver,
    LineRangeModel,
)


# ── Helpers ──


def _make_config(**overrides) -> ContextConfig:
    """Build a ContextConfig with small test-friendly defaults."""
    defaults = dict(
        token_budget=500,
        chars_per_token=4.0,
        max_folder_depth=2,
        max_file_size=200,
        max_references=10,
        max_terminal_lines=5,
    )
    defaults.update(overrides)
    return ContextConfig(**defaults)


def _make_file_service() -> MagicMock:
    """Minimal FileService stub — only _should_ignore is used by the resolver."""
    svc = MagicMock()
    # Never ignore anything by default; tests can override per-case
    svc._should_ignore = MagicMock(return_value=False)
    return svc


def _make_git_service() -> AsyncMock:
    """Mock GitService with async diff_all."""
    svc = AsyncMock()
    svc.diff_all = AsyncMock(return_value={"diff": "", "error": ""})
    return svc


def _make_resolver(
    tmp_path: Path,
    config: ContextConfig | None = None,
    terminal_outputs: dict[str, list[str]] | None = None,
    git_service: AsyncMock | None = None,
) -> ContextResolver:
    """Construct a ContextResolver wired to tmp_path."""
    return ContextResolver(
        config=config or _make_config(),
        file_service=_make_file_service(),
        git_service=git_service or _make_git_service(),
        terminal_outputs=terminal_outputs or {},
        work_dir=tmp_path,
    )


# ═══════════════════════════════════════════════════════════════════
# 1. File resolution
# ═══════════════════════════════════════════════════════════════════


class TestFileResolution:
    """Tests for _resolve_file and its edge cases."""

    @pytest.mark.asyncio
    async def test_normal_python_file(self, tmp_path: Path):
        """Normal .py file → markdown block with python language identifier."""
        (tmp_path / "hello.py").write_text("print('hi')\n", encoding="utf-8")
        resolver = _make_resolver(tmp_path)

        ref = ContextReferenceModel(type="file", path="hello.py")
        result = await resolver._resolve_file(ref)

        assert "## File: hello.py" in result
        assert "```python" in result
        assert "print('hi')" in result

    @pytest.mark.asyncio
    async def test_binary_file_skipped(self, tmp_path: Path):
        """File containing null bytes → skip note with 'Binary file'."""
        (tmp_path / "image.png").write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00")
        resolver = _make_resolver(tmp_path)

        ref = ContextReferenceModel(type="file", path="image.png")
        result = await resolver._resolve_file(ref)

        assert "Binary file" in result

    @pytest.mark.asyncio
    async def test_empty_file(self, tmp_path: Path):
        """Zero-length file → '(empty file)' note."""
        (tmp_path / "blank.ts").write_bytes(b"")
        resolver = _make_resolver(tmp_path)

        ref = ContextReferenceModel(type="file", path="blank.ts")
        result = await resolver._resolve_file(ref)

        assert "(empty file)" in result
        assert "```typescript" in result

    @pytest.mark.asyncio
    async def test_file_not_found(self, tmp_path: Path):
        """Non-existent path → 'File not found' note."""
        resolver = _make_resolver(tmp_path)

        ref = ContextReferenceModel(type="file", path="ghost.txt")
        result = await resolver._resolve_file(ref)

        assert "File not found" in result

    @pytest.mark.asyncio
    async def test_large_file_truncation(self, tmp_path: Path):
        """File exceeding max_file_size → truncated with note."""
        cfg = _make_config(max_file_size=100)
        content = "x" * 200
        (tmp_path / "big.txt").write_text(content, encoding="utf-8")
        resolver = _make_resolver(tmp_path, config=cfg)

        ref = ContextReferenceModel(type="file", path="big.txt")
        result = await resolver._resolve_file(ref)

        assert "truncated" in result.lower()
        # The full 200 chars should NOT appear
        assert content not in result

    @pytest.mark.asyncio
    async def test_line_range(self, tmp_path: Path):
        """Line range extraction → only specified lines included."""
        lines = "\n".join(f"line{i}" for i in range(1, 11))
        (tmp_path / "multi.py").write_text(lines, encoding="utf-8")
        resolver = _make_resolver(tmp_path)

        ref = ContextReferenceModel(
            type="file",
            path="multi.py",
            line_range=LineRangeModel(start=3, end=5),
        )
        result = await resolver._resolve_file(ref)

        assert "line3" in result
        assert "line4" in result
        assert "line5" in result
        # Lines outside the range should not appear
        assert "line1\n" not in result
        assert "line9" not in result
        # Header should show the line range
        assert "lines 3-5" in result

    @pytest.mark.asyncio
    async def test_bom_stripping(self, tmp_path: Path):
        """UTF-8 BOM prefix (EF BB BF) → stripped from output."""
        bom = b"\xef\xbb\xbf"
        (tmp_path / "bom.js").write_bytes(bom + b"const x = 1;\n")
        resolver = _make_resolver(tmp_path)

        ref = ContextReferenceModel(type="file", path="bom.js")
        result = await resolver._resolve_file(ref)

        # BOM bytes should not appear as garbage in the output
        assert "\ufeff" not in result
        assert "const x = 1;" in result

    @pytest.mark.asyncio
    async def test_encoding_fallback_latin1(self, tmp_path: Path):
        """Non-UTF-8 bytes (latin-1) → decoded successfully via fallback."""
        # 0xe9 = 'é' in latin-1, invalid as standalone UTF-8 byte
        (tmp_path / "latin.txt").write_bytes(b"caf\xe9\n")
        resolver = _make_resolver(tmp_path)

        ref = ContextReferenceModel(type="file", path="latin.txt")
        result = await resolver._resolve_file(ref)

        assert "café" in result
        # Should NOT contain an encoding error note
        assert "encoding error" not in result.lower()

    @pytest.mark.asyncio
    async def test_symlink_outside_project(self, tmp_path: Path):
        """Symlink pointing outside work_dir → 'Symlink outside project' note."""
        # Create a file outside the project directory
        outside = tmp_path.parent / "outside_secret.txt"
        outside.write_text("secret data", encoding="utf-8")

        link = tmp_path / "escape.txt"
        try:
            link.symlink_to(outside)
        except OSError:
            pytest.skip("Symlinks not supported on this platform")

        resolver = _make_resolver(tmp_path)
        ref = ContextReferenceModel(type="file", path="escape.txt")
        result = await resolver._resolve_file(ref)

        assert "Symlink outside project" in result
        # The secret content must NOT leak
        assert "secret data" not in result

    @pytest.mark.asyncio
    async def test_empty_path_returns_empty(self, tmp_path: Path):
        """Empty path string → empty string (no crash)."""
        resolver = _make_resolver(tmp_path)
        ref = ContextReferenceModel(type="file", path="")
        result = await resolver._resolve_file(ref)
        assert result == ""


# ═══════════════════════════════════════════════════════════════════
# 2. Folder resolution
# ═══════════════════════════════════════════════════════════════════


class TestFolderResolution:
    """Tests for _resolve_folder and tree generation."""

    @pytest.mark.asyncio
    async def test_normal_folder(self, tmp_path: Path):
        """Folder with files → tree output containing file names."""
        sub = tmp_path / "src"
        sub.mkdir()
        (sub / "main.py").write_text("pass", encoding="utf-8")
        (sub / "utils.py").write_text("pass", encoding="utf-8")

        resolver = _make_resolver(tmp_path)
        ref = ContextReferenceModel(type="folder", path="src")
        result = await resolver._resolve_folder(ref)

        assert "## Folder: src" in result
        assert "main.py" in result
        assert "utils.py" in result

    @pytest.mark.asyncio
    async def test_depth_limit(self, tmp_path: Path):
        """Nested directories beyond max_folder_depth → tree stops at limit."""
        cfg = _make_config(max_folder_depth=1)
        # Create: src/a/b/deep.txt (3 levels deep)
        deep = tmp_path / "src" / "a" / "b"
        deep.mkdir(parents=True)
        (deep / "deep.txt").write_text("hidden", encoding="utf-8")
        (tmp_path / "src" / "top.txt").write_text("visible", encoding="utf-8")

        resolver = _make_resolver(tmp_path, config=cfg)
        ref = ContextReferenceModel(type="folder", path="src")
        result = await resolver._resolve_folder(ref)

        # top.txt is at depth 1 (direct child) — should appear
        assert "top.txt" in result
        # deep.txt is at depth 3 — should NOT appear with max_depth=1
        assert "deep.txt" not in result

    @pytest.mark.asyncio
    async def test_empty_folder(self, tmp_path: Path):
        """Empty directory → tree with just the folder name."""
        (tmp_path / "empty_dir").mkdir()
        resolver = _make_resolver(tmp_path)

        ref = ContextReferenceModel(type="folder", path="empty_dir")
        result = await resolver._resolve_folder(ref)

        assert "## Folder: empty_dir" in result
        # Should contain the folder name at minimum
        assert "empty_dir" in result

    @pytest.mark.asyncio
    async def test_folder_not_found(self, tmp_path: Path):
        """Non-existent folder → 'Folder not found' note."""
        resolver = _make_resolver(tmp_path)
        ref = ContextReferenceModel(type="folder", path="nope")
        result = await resolver._resolve_folder(ref)

        assert "Folder not found" in result


# ═══════════════════════════════════════════════════════════════════
# 3. Git diff resolution
# ═══════════════════════════════════════════════════════════════════


class TestGitDiffResolution:
    """Tests for _resolve_git_diff with mocked GitService."""

    @pytest.mark.asyncio
    async def test_staged_and_unstaged_diffs(self, tmp_path: Path):
        """Both staged and unstaged diffs present → both appear in output."""
        git_svc = _make_git_service()

        async def mock_diff_all(staged: bool = False):
            if staged:
                return {"diff": "staged-diff-content", "error": ""}
            return {"diff": "unstaged-diff-content", "error": ""}

        git_svc.diff_all = mock_diff_all

        resolver = _make_resolver(tmp_path, git_service=git_svc)
        ref = ContextReferenceModel(type="git-diff")
        result = await resolver._resolve_git_diff(ref)

        assert "unstaged-diff-content" in result
        assert "staged-diff-content" in result
        assert "## Git Diff (unstaged)" in result
        assert "## Git Diff (staged)" in result

    @pytest.mark.asyncio
    async def test_diff_exception(self, tmp_path: Path):
        """GitService.diff_all raises → error note in output."""
        git_svc = _make_git_service()
        git_svc.diff_all = AsyncMock(side_effect=RuntimeError("git broke"))

        resolver = _make_resolver(tmp_path, git_service=git_svc)
        ref = ContextReferenceModel(type="git-diff")
        result = await resolver._resolve_git_diff(ref)

        assert "unavailable" in result.lower() or "git broke" in result

    @pytest.mark.asyncio
    async def test_empty_diffs(self, tmp_path: Path):
        """No changes → '(no unstaged changes)' and '(no staged changes)'."""
        git_svc = _make_git_service()
        git_svc.diff_all = AsyncMock(return_value={"diff": "", "error": ""})

        resolver = _make_resolver(tmp_path, git_service=git_svc)
        ref = ContextReferenceModel(type="git-diff")
        result = await resolver._resolve_git_diff(ref)

        assert "(no unstaged changes)" in result
        assert "(no staged changes)" in result


# ═══════════════════════════════════════════════════════════════════
# 4. Terminal resolution
# ═══════════════════════════════════════════════════════════════════


class TestTerminalResolution:
    """Tests for _resolve_terminal."""

    @pytest.mark.asyncio
    async def test_terminal_with_output(self, tmp_path: Path):
        """Terminal outputs dict with lines → last N lines included."""
        outputs = {"t1": [f"line{i}" for i in range(1, 11)]}
        cfg = _make_config(max_terminal_lines=3)
        resolver = _make_resolver(tmp_path, config=cfg, terminal_outputs=outputs)

        ref = ContextReferenceModel(type="terminal")
        result = resolver._resolve_terminal(ref)

        assert "## Terminal Output" in result
        # Only last 3 lines should appear
        assert "line8" in result
        assert "line9" in result
        assert "line10" in result
        # Earlier lines should be trimmed
        assert "line1\n" not in result

    @pytest.mark.asyncio
    async def test_terminal_empty(self, tmp_path: Path):
        """Empty terminal_outputs → '(no terminal output)' note."""
        resolver = _make_resolver(tmp_path, terminal_outputs={})

        ref = ContextReferenceModel(type="terminal")
        result = resolver._resolve_terminal(ref)

        assert "(no terminal output)" in result

    @pytest.mark.asyncio
    async def test_terminal_multiple_sessions(self, tmp_path: Path):
        """Multiple terminal sessions → lines from all sessions collected."""
        outputs = {
            "t1": ["session1-line1", "session1-line2"],
            "t2": ["session2-line1"],
        }
        cfg = _make_config(max_terminal_lines=50)
        resolver = _make_resolver(tmp_path, config=cfg, terminal_outputs=outputs)

        ref = ContextReferenceModel(type="terminal")
        result = resolver._resolve_terminal(ref)

        assert "session1-line1" in result
        assert "session2-line1" in result


# ═══════════════════════════════════════════════════════════════════
# 5. URL resolution
# ═══════════════════════════════════════════════════════════════════


class TestUrlResolution:
    """Tests for _resolve_url passthrough."""

    @pytest.mark.asyncio
    async def test_url_passthrough(self, tmp_path: Path):
        """URL reference → passthrough format with URL in header and body."""
        resolver = _make_resolver(tmp_path)
        ref = ContextReferenceModel(type="url", path="https://example.com/docs")
        result = resolver._resolve_url(ref)

        assert "## URL: https://example.com/docs" in result
        assert "https://example.com/docs" in result

    @pytest.mark.asyncio
    async def test_url_empty(self, tmp_path: Path):
        """Empty URL → empty string returned."""
        resolver = _make_resolver(tmp_path)
        ref = ContextReferenceModel(type="url", path="")
        result = resolver._resolve_url(ref)

        assert result == ""


# ═══════════════════════════════════════════════════════════════════
# 6. Parallel resolution (resolve() public API)
# ═══════════════════════════════════════════════════════════════════


class TestParallelResolution:
    """Tests for the resolve() method — parallel dispatch and aggregation."""

    @pytest.mark.asyncio
    async def test_five_file_references(self, tmp_path: Path):
        """5 file references → all 5 resolved and present in output."""
        cfg = _make_config(token_budget=50000)
        for i in range(5):
            (tmp_path / f"f{i}.py").write_text(f"content_{i}", encoding="utf-8")

        resolver = _make_resolver(tmp_path, config=cfg)
        refs = [ContextReferenceModel(type="file", path=f"f{i}.py") for i in range(5)]
        result = await resolver.resolve(refs)

        for i in range(5):
            assert f"content_{i}" in result

    @pytest.mark.asyncio
    async def test_no_deadlock(self, tmp_path: Path):
        """Multiple references resolve without deadlock (completes in time)."""
        import asyncio

        cfg = _make_config(token_budget=50000)
        for i in range(3):
            (tmp_path / f"d{i}.txt").write_text(f"data{i}", encoding="utf-8")

        resolver = _make_resolver(tmp_path, config=cfg)
        refs = [ContextReferenceModel(type="file", path=f"d{i}.txt") for i in range(3)]

        # Should complete within 5 seconds — deadlock would hang forever
        result = await asyncio.wait_for(resolver.resolve(refs), timeout=5.0)
        assert len(result) > 0

    @pytest.mark.asyncio
    async def test_mixed_reference_types(self, tmp_path: Path):
        """Mix of file + folder + git-diff → all types resolved."""
        cfg = _make_config(token_budget=50000)
        (tmp_path / "mix.py").write_text("mixed_content", encoding="utf-8")
        sub = tmp_path / "mixdir"
        sub.mkdir()
        (sub / "child.txt").write_text("child", encoding="utf-8")

        git_svc = _make_git_service()
        git_svc.diff_all = AsyncMock(return_value={"diff": "diff-output", "error": ""})

        resolver = _make_resolver(tmp_path, config=cfg, git_service=git_svc)
        refs = [
            ContextReferenceModel(type="file", path="mix.py"),
            ContextReferenceModel(type="folder", path="mixdir"),
            ContextReferenceModel(type="git-diff"),
        ]
        result = await resolver.resolve(refs)

        assert "mixed_content" in result
        assert "child.txt" in result
        assert "## Git Diff" in result

    @pytest.mark.asyncio
    async def test_empty_references_list(self, tmp_path: Path):
        """Empty references list → empty string."""
        resolver = _make_resolver(tmp_path)
        result = await resolver.resolve([])
        assert result == ""

    @pytest.mark.asyncio
    async def test_max_references_cap(self, tmp_path: Path):
        """References exceeding max_references → capped to limit."""
        cfg = _make_config(max_references=2, token_budget=50000)
        for i in range(5):
            (tmp_path / f"cap{i}.txt").write_text(f"cap_content_{i}", encoding="utf-8")

        resolver = _make_resolver(tmp_path, config=cfg)
        refs = [ContextReferenceModel(type="file", path=f"cap{i}.txt") for i in range(5)]
        result = await resolver.resolve(refs)

        # Only first 2 should be resolved
        assert "cap_content_0" in result
        assert "cap_content_1" in result
        assert "cap_content_4" not in result


# ═══════════════════════════════════════════════════════════════════
# 7. Token budget
# ═══════════════════════════════════════════════════════════════════


class TestTokenBudget:
    """Tests for _apply_token_budget and _estimate_tokens."""

    @pytest.mark.asyncio
    async def test_budget_truncation(self, tmp_path: Path):
        """Total content exceeding token_budget → truncation note appears."""
        # With chars_per_token=4 and token_budget=50, budget = 200 chars
        cfg = _make_config(token_budget=50, chars_per_token=4.0, max_file_size=10000)
        # Each file produces ~300+ chars of markdown (header + fenced block)
        (tmp_path / "a.py").write_text("A" * 300, encoding="utf-8")
        (tmp_path / "b.py").write_text("B" * 300, encoding="utf-8")

        resolver = _make_resolver(tmp_path, config=cfg)
        refs = [
            ContextReferenceModel(type="file", path="a.py"),
            ContextReferenceModel(type="file", path="b.py"),
        ]
        result = await resolver.resolve(refs)

        assert "truncated" in result.lower() or "token budget" in result.lower()

    def test_estimate_tokens_empty(self, tmp_path: Path):
        """Empty string → 0 tokens."""
        resolver = _make_resolver(tmp_path)
        assert resolver._estimate_tokens("") == 0

    def test_estimate_tokens_calculation(self, tmp_path: Path):
        """Token estimation uses chars_per_token ratio."""
        cfg = _make_config(chars_per_token=4.0)
        resolver = _make_resolver(tmp_path, config=cfg)
        # 100 chars / 4 chars_per_token = 25 tokens
        assert resolver._estimate_tokens("x" * 100) == 25

    def test_apply_budget_all_fit(self, tmp_path: Path):
        """All items fit within budget → no truncation."""
        cfg = _make_config(token_budget=1000)
        resolver = _make_resolver(tmp_path, config=cfg)

        items = [("block1", 100), ("block2", 100)]
        result = resolver._apply_token_budget(items)

        assert "block1" in result
        assert "block2" in result
        assert "truncated" not in result.lower()

    def test_apply_budget_partial_fit(self, tmp_path: Path):
        """Second item exceeds budget → truncated with note."""
        cfg = _make_config(token_budget=150)
        resolver = _make_resolver(tmp_path, config=cfg)

        items = [("A" * 400, 100), ("B" * 400, 100)]
        result = resolver._apply_token_budget(items)

        # First block should be fully included
        assert "A" * 400 in result
        # Second block should be truncated
        assert "token budget" in result.lower()


# ═══════════════════════════════════════════════════════════════════
# 8. Async IO
# ═══════════════════════════════════════════════════════════════════


class TestAsyncIO:
    """Verify resolvers work correctly in async context (asyncio.to_thread)."""

    @pytest.mark.asyncio
    async def test_resolve_file_async(self, tmp_path: Path):
        """_resolve_file uses asyncio.to_thread — works in async test."""
        (tmp_path / "async_test.py").write_text("async_content", encoding="utf-8")
        resolver = _make_resolver(tmp_path)

        ref = ContextReferenceModel(type="file", path="async_test.py")
        # This exercises the asyncio.to_thread(real_path.read_bytes) path
        result = await resolver._resolve_file(ref)

        assert "async_content" in result

    @pytest.mark.asyncio
    async def test_resolve_folder_async(self, tmp_path: Path):
        """_resolve_folder uses asyncio.to_thread — works in async test."""
        sub = tmp_path / "async_dir"
        sub.mkdir()
        (sub / "item.txt").write_text("data", encoding="utf-8")

        resolver = _make_resolver(tmp_path)
        ref = ContextReferenceModel(type="folder", path="async_dir")
        # This exercises the asyncio.to_thread(self._build_tree, ...) path
        result = await resolver._resolve_folder(ref)

        assert "item.txt" in result

    @pytest.mark.asyncio
    async def test_concurrent_file_reads(self, tmp_path: Path):
        """Multiple files resolved concurrently via asyncio.gather."""
        import asyncio

        cfg = _make_config(token_budget=50000)
        for i in range(10):
            (tmp_path / f"concurrent_{i}.txt").write_text(
                f"concurrent_data_{i}", encoding="utf-8"
            )

        resolver = _make_resolver(tmp_path, config=cfg)
        refs = [
            ContextReferenceModel(type="file", path=f"concurrent_{i}.txt")
            for i in range(10)
        ]

        # All 10 should resolve concurrently without issues
        result = await asyncio.wait_for(resolver.resolve(refs), timeout=10.0)
        for i in range(10):
            assert f"concurrent_data_{i}" in result


# ═══════════════════════════════════════════════════════════════════
# 9. Serialization & helpers
# ═══════════════════════════════════════════════════════════════════


class TestHelpers:
    """Tests for _serialize, _detect_language, _is_within_work_dir."""

    def test_detect_language_python(self, tmp_path: Path):
        resolver = _make_resolver(tmp_path)
        assert resolver._detect_language("foo.py") == "python"

    def test_detect_language_unknown(self, tmp_path: Path):
        resolver = _make_resolver(tmp_path)
        assert resolver._detect_language("foo.xyz") == ""

    def test_detect_language_dart(self, tmp_path: Path):
        resolver = _make_resolver(tmp_path)
        assert resolver._detect_language("main.dart") == "dart"

    def test_is_within_work_dir_true(self, tmp_path: Path):
        resolver = _make_resolver(tmp_path)
        child = (tmp_path / "sub" / "file.txt")
        # Use tmp_path itself (resolved) as a stand-in
        assert resolver._is_within_work_dir(tmp_path / "sub")

    def test_is_within_work_dir_false(self, tmp_path: Path):
        resolver = _make_resolver(tmp_path)
        outside = Path("/tmp/outside_project")
        assert not resolver._is_within_work_dir(outside)

    def test_serialize_file(self, tmp_path: Path):
        resolver = _make_resolver(tmp_path)
        result = resolver._serialize("file", "test.py", "code", language="python")
        assert "## File: test.py" in result
        assert "```python" in result
        assert "code" in result

    def test_serialize_folder(self, tmp_path: Path):
        resolver = _make_resolver(tmp_path)
        result = resolver._serialize("folder", "src", "tree content")
        assert "## Folder: src" in result
        assert "tree content" in result

    def test_serialize_terminal(self, tmp_path: Path):
        resolver = _make_resolver(tmp_path)
        result = resolver._serialize("terminal", "", "output lines")
        assert "## Terminal Output" in result

    def test_serialize_url(self, tmp_path: Path):
        resolver = _make_resolver(tmp_path)
        result = resolver._serialize("url", "https://x.com", "https://x.com")
        assert "## URL: https://x.com" in result

    def test_serialize_unknown_type(self, tmp_path: Path):
        resolver = _make_resolver(tmp_path)
        result = resolver._serialize("custom", "path", "body")
        assert "## custom: path" in result


# ═══════════════════════════════════════════════════════════════════
# 10. Performance benchmarks
# ═══════════════════════════════════════════════════════════════════


class TestPerformanceBenchmarks:
    """Performance benchmarks — assert wall-clock time targets.

    These tests measure actual elapsed time using time.monotonic() and
    assert that operations complete within specified thresholds. They
    validate that parallel IO, concurrent git operations, and budget
    enforcement don't regress in performance.
    """

    @pytest.mark.asyncio
    async def test_parallel_10_files_under_2s(self, tmp_path: Path):
        """10 x 50KB files resolved in parallel should complete under 2 seconds."""
        import asyncio
        import time

        cfg = _make_config(token_budget=500000, max_file_size=100000)
        for i in range(10):
            (tmp_path / f"perf_{i}.py").write_text("x" * 50000, encoding="utf-8")

        resolver = _make_resolver(tmp_path, config=cfg)
        refs = [ContextReferenceModel(type="file", path=f"perf_{i}.py") for i in range(10)]

        start = time.monotonic()
        result = await resolver.resolve(refs)
        elapsed = time.monotonic() - start

        assert elapsed < 2.0, f"Parallel resolution took {elapsed:.2f}s (target: <2s)"
        # Verify all 10 files were resolved
        for i in range(10):
            assert f"## File: perf_{i}.py" in result

    @pytest.mark.asyncio
    async def test_git_diff_parallel_under_300ms(self, tmp_path: Path):
        """Staged + unstaged git diffs in parallel should complete under 300ms."""
        import asyncio
        import time

        async def slow_diff(staged: bool = False):
            """Simulate 100ms git command latency per diff call."""
            await asyncio.sleep(0.1)
            label = "staged" if staged else "unstaged"
            return {"diff": f"{label}-content", "error": ""}

        git_svc = _make_git_service()
        git_svc.diff_all = slow_diff

        resolver = _make_resolver(tmp_path, git_service=git_svc)
        ref = ContextReferenceModel(type="git-diff")

        start = time.monotonic()
        result = await resolver._resolve_git_diff(ref)
        elapsed = time.monotonic() - start

        # Parallel: ~100ms. Serial would be ~200ms.
        assert elapsed < 0.3, f"Git diff took {elapsed:.3f}s (target: <0.3s)"
        assert "unstaged-content" in result
        assert "staged-content" in result

    @pytest.mark.asyncio
    async def test_mixed_refs_parallel_under_500ms(self, tmp_path: Path):
        """5 files + 1 folder + 1 git-diff (100ms mock) resolved together under 500ms."""
        import asyncio
        import time

        cfg = _make_config(token_budget=500000, max_file_size=100000)

        # Create 5 files
        for i in range(5):
            (tmp_path / f"mix_perf_{i}.py").write_text(f"content_{i}" * 100, encoding="utf-8")

        # Create 1 folder with children
        sub = tmp_path / "perf_folder"
        sub.mkdir()
        (sub / "child.txt").write_text("child_data", encoding="utf-8")

        # Git service with 100ms simulated latency
        async def slow_diff(staged: bool = False):
            """Simulate 100ms git command latency."""
            await asyncio.sleep(0.1)
            label = "staged" if staged else "unstaged"
            return {"diff": f"{label}-mixed", "error": ""}

        git_svc = _make_git_service()
        git_svc.diff_all = slow_diff

        resolver = _make_resolver(tmp_path, config=cfg, git_service=git_svc)
        refs = (
            [ContextReferenceModel(type="file", path=f"mix_perf_{i}.py") for i in range(5)]
            + [ContextReferenceModel(type="folder", path="perf_folder")]
            + [ContextReferenceModel(type="git-diff")]
        )

        start = time.monotonic()
        result = await resolver.resolve(refs)
        elapsed = time.monotonic() - start

        # All 7 refs resolved in parallel — git diff is the bottleneck at ~100ms,
        # file IO and folder walk are fast. Total should be well under 500ms.
        assert elapsed < 0.5, f"Mixed refs took {elapsed:.3f}s (target: <0.5s)"
        for i in range(5):
            assert f"## File: mix_perf_{i}.py" in result
        assert "perf_folder" in result
        assert "## Git Diff" in result

    @pytest.mark.asyncio
    async def test_token_budget_no_overhead(self, tmp_path: Path):
        """Token budget enforcement on 10 files should not add significant overhead.

        Budget enforcement is an O(n) linear scan over resolved blocks.
        Comparing 10-file resolution (budget exceeded) vs 2-file resolution
        (budget fits) — the difference should be negligible (<200ms).
        """
        import asyncio
        import time

        # Small budget: only ~2 files worth of tokens fit
        # chars_per_token=4, budget=500 → 2000 chars budget
        cfg_small = _make_config(
            token_budget=500, chars_per_token=4.0, max_file_size=10000,
        )
        # Large budget: all 10 files fit easily
        cfg_large = _make_config(
            token_budget=500000, chars_per_token=4.0, max_file_size=10000,
        )

        for i in range(10):
            (tmp_path / f"budget_{i}.py").write_text("y" * 5000, encoding="utf-8")

        # Measure 2-file resolve (baseline)
        resolver_baseline = _make_resolver(tmp_path, config=cfg_large)
        refs_2 = [ContextReferenceModel(type="file", path=f"budget_{i}.py") for i in range(2)]

        start = time.monotonic()
        await resolver_baseline.resolve(refs_2)
        baseline_elapsed = time.monotonic() - start

        # Measure 10-file resolve with budget truncation
        resolver_budget = _make_resolver(tmp_path, config=cfg_small)
        refs_10 = [ContextReferenceModel(type="file", path=f"budget_{i}.py") for i in range(10)]

        start = time.monotonic()
        result = await resolver_budget.resolve(refs_10)
        budget_elapsed = time.monotonic() - start

        # Budget enforcement overhead should be negligible — the 10-file run
        # does more IO but the budget scan itself is O(n) and near-instant.
        # Allow generous 200ms margin for IO variance.
        assert budget_elapsed < baseline_elapsed + 0.2, (
            f"Budget enforcement added too much overhead: "
            f"baseline={baseline_elapsed:.3f}s, budget={budget_elapsed:.3f}s"
        )
        # Verify truncation actually happened
        assert "truncated" in result.lower() or "token budget" in result.lower()

    def test_autocomplete_filter_5000_entries_under_10ms(self):
        """Filtering 5000 file entries by substring should complete under 10ms.

        Simulates the autocomplete overlay filtering on the App side —
        a linear scan over path strings with substring match, capped
        at 8 results. This must be near-instant for responsive UI.
        """
        import time

        entries = [
            {
                "name": f"file_{i}.py",
                "path": f"src/module_{i % 50}/file_{i}.py",
                "type": "file",
            }
            for i in range(5000)
        ]
        query = "module_25"

        start = time.monotonic()
        matches = [e for e in entries if query in e["path"].lower()][:8]
        elapsed = time.monotonic() - start

        assert elapsed < 0.01, f"Filter took {elapsed * 1000:.1f}ms (target: <10ms)"
        # module_25 matches module_25/ entries: file_25, file_75, file_125, ...
        assert len(matches) == 8
