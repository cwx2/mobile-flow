"""ProjectScanner property-based and unit tests.

Tests cover:
  P1: Search results match query (case-insensitive substring)
  P2: Search depth constraint (no result deeper than max_depth)
  P3: Search result sort order (project_type first, then alphabetical)
  P4: Result entry schema completeness (all required keys present)
  P5: Max results limit (never exceeds configured max_results)
  P6: Hidden directory exclusion (no dotfiles in results)
  P7: Path security validation (system dirs blocked, home allowed)
  P8: Browse returns only sorted directories (no files, alphabetical)
  P10: Search mode dispatch (path → is_browsing=True, no path → False)

Unit tests:
  - Project type detection for each marker file
  - Windows drive detection (mocked)
  - Auto-detect search roots (mocked)

# Feature: project-browser-enhance
"""

from __future__ import annotations

import asyncio
import os
import sys
import tempfile
import shutil
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest
from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st

from mobileflow_agent.core.config import ProjectScannerConfig
from mobileflow_agent.services.project_scanner import ProjectScanner


# ═══════════════════════════════════════════════════════════════
# Fixtures
# ═══════════════════════════════════════════════════════════════


@pytest.fixture
def scanner(tmp_path: Path) -> ProjectScanner:
    """Create a ProjectScanner with tmp_path as the only search root."""
    config = ProjectScannerConfig(
        search_roots=[str(tmp_path)],
        max_depth=3,
        search_timeout=5.0,
        max_results=20,
        recent_projects_limit=10,
    )
    return ProjectScanner(config)


# ═══════════════════════════════════════════════════════════════
# Property-based tests (Hypothesis)
# ═══════════════════════════════════════════════════════════════


# Feature: project-browser-enhance, Property 1: Search results match query
class TestSearchResultsMatchQuery:
    """For any non-empty query, every result name contains the query
    as a case-insensitive substring."""

    @given(
        query=st.text(
            min_size=1, max_size=10,
            alphabet=st.characters(whitelist_categories=("L", "N")),
        ),
    )
    @settings(max_examples=100)
    @pytest.mark.asyncio
    async def test_all_results_contain_query(self, query: str):
        assume(query.strip())
        td = tempfile.mkdtemp()
        try:
            matching_dir = Path(td) / f"proj-{query}-app"
            matching_dir.mkdir(parents=True, exist_ok=True)
            non_matching = Path(td) / "zzz-unrelated"
            non_matching.mkdir(parents=True, exist_ok=True)

            config = ProjectScannerConfig(
                search_roots=[td],
                max_depth=2,
                search_timeout=5.0,
                max_results=20,
            )
            scanner = ProjectScanner(config)
            results = await scanner.search(query)

            for r in results:
                assert query.lower() in r["name"].lower(), (
                    f"Result name {r['name']!r} does not contain query {query!r}"
                )
        finally:
            shutil.rmtree(td, ignore_errors=True)


# Feature: project-browser-enhance, Property 2: Search depth constraint
class TestSearchDepthConstraint:
    """No search result is located deeper than max_depth levels below
    any search root."""

    @given(max_depth=st.integers(min_value=1, max_value=4))
    @settings(max_examples=100)
    @pytest.mark.asyncio
    async def test_depth_limit_respected(self, max_depth: int):
        td = tempfile.mkdtemp()
        try:
            for depth in range(max_depth + 3):
                parts = [f"d{i}" for i in range(depth)]
                parent = Path(td).joinpath(*parts) if parts else Path(td)
                target = parent / "target"
                target.mkdir(parents=True, exist_ok=True)

            config = ProjectScannerConfig(
                search_roots=[td],
                max_depth=max_depth,
                search_timeout=5.0,
                max_results=50,
            )
            scanner = ProjectScanner(config)
            results = await scanner.search("target")

            root = Path(td).resolve()
            for r in results:
                result_path = Path(r["path"]).resolve()
                try:
                    relative = result_path.relative_to(root)
                    depth = len(relative.parts)
                    assert depth <= max_depth + 1, (
                        f"Result at depth {depth} exceeds max_depth {max_depth}: {r['path']}"
                    )
                except ValueError:
                    pass
        finally:
            shutil.rmtree(td, ignore_errors=True)


# Feature: project-browser-enhance, Property 3: Search result sort order
class TestSearchResultSortOrder:
    """Results with project_type come before those without, and within
    each group entries are sorted alphabetically by name (case-insensitive)."""

    @given(
        names=st.lists(
            st.text(min_size=1, max_size=8, alphabet=st.characters(
                whitelist_categories=("L", "N"),
            )).filter(lambda n: n.upper() not in {
                "CON", "PRN", "AUX", "NUL",
                "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
                "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
            }),
            min_size=2, max_size=10, unique=True,
        ),
    )
    @settings(max_examples=100)
    @pytest.mark.asyncio
    async def test_sort_order_invariant(self, names: list[str]):
        td = tempfile.mkdtemp()
        try:
            for i, name in enumerate(names):
                d = Path(td) / name
                d.mkdir(exist_ok=True)
                if i % 2 == 0:
                    (d / "package.json").touch()

            config = ProjectScannerConfig(
                search_roots=[td],
                max_depth=1,
                search_timeout=5.0,
                max_results=50,
            )
            scanner = ProjectScanner(config)
            results = await scanner.search("")

            has_type = [r for r in results if r["project_type"]]
            no_type = [r for r in results if not r["project_type"]]

            if has_type and no_type:
                last_typed_idx = max(results.index(r) for r in has_type)
                first_untyped_idx = min(results.index(r) for r in no_type)
                assert last_typed_idx < first_untyped_idx

            for group in [has_type, no_type]:
                group_names = [r["name"].lower() for r in group]
                assert group_names == sorted(group_names)
        finally:
            shutil.rmtree(td, ignore_errors=True)


# Feature: project-browser-enhance, Property 4: Result entry schema completeness
class TestResultEntrySchema:
    """Every result entry contains all required keys with correct types."""

    REQUIRED_KEYS = {"path", "name", "project_type", "has_git", "exists"}

    @given(
        name=st.text(
            min_size=1, max_size=12,
            alphabet=st.characters(whitelist_categories=("L", "N")),
        ),
    )
    @settings(max_examples=100)
    @pytest.mark.asyncio
    async def test_schema_completeness(self, name: str):
        td = tempfile.mkdtemp()
        try:
            d = Path(td) / name
            d.mkdir(exist_ok=True)

            config = ProjectScannerConfig(
                search_roots=[td],
                max_depth=1,
                search_timeout=5.0,
                max_results=20,
            )
            scanner = ProjectScanner(config)
            results = await scanner.search(name)

            for r in results:
                missing = self.REQUIRED_KEYS - set(r.keys())
                assert not missing, f"Missing keys: {missing} in {r}"
                assert isinstance(r["path"], str) and r["path"]
                assert isinstance(r["name"], str) and r["name"]
                assert isinstance(r["has_git"], bool)
                assert isinstance(r["exists"], bool)
                assert r["project_type"] is None or isinstance(r["project_type"], str)
        finally:
            shutil.rmtree(td, ignore_errors=True)


# Feature: project-browser-enhance, Property 5: Max results limit
class TestMaxResultsLimit:
    """The number of results never exceeds max_results."""

    @given(max_results=st.integers(min_value=1, max_value=10))
    @settings(max_examples=100)
    @pytest.mark.asyncio
    async def test_result_count_within_limit(self, max_results: int):
        td = tempfile.mkdtemp()
        try:
            for i in range(max_results + 5):
                (Path(td) / f"proj{i}").mkdir(exist_ok=True)

            config = ProjectScannerConfig(
                search_roots=[td],
                max_depth=1,
                search_timeout=5.0,
                max_results=max_results,
            )
            scanner = ProjectScanner(config)
            results = await scanner.search("proj")

            assert len(results) <= max_results
        finally:
            shutil.rmtree(td, ignore_errors=True)


# Feature: project-browser-enhance, Property 6: Hidden directory exclusion
class TestHiddenDirectoryExclusion:
    """No hidden directory (name starting with '.') appears in search results,
    but .git detection within non-hidden directories still works."""

    @given(
        visible_name=st.text(
            min_size=1, max_size=8,
            alphabet=st.characters(whitelist_categories=("L", "N")),
        ).filter(lambda n: n.upper() not in {
            "CON", "PRN", "AUX", "NUL",
            "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
            "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
        }),
    )
    @settings(max_examples=100)
    @pytest.mark.asyncio
    async def test_no_hidden_dirs_in_results(self, visible_name: str):
        td = tempfile.mkdtemp()
        try:
            hidden = Path(td) / f".{visible_name}"
            hidden.mkdir(exist_ok=True)
            visible = Path(td) / visible_name
            visible.mkdir(exist_ok=True)
            (visible / ".git").mkdir(exist_ok=True)

            config = ProjectScannerConfig(
                search_roots=[td],
                max_depth=2,
                search_timeout=5.0,
                max_results=50,
            )
            scanner = ProjectScanner(config)
            results = await scanner.search(visible_name)

            for r in results:
                assert not r["name"].startswith("."), (
                    f"Hidden directory in results: {r['name']}"
                )

            visible_results = [r for r in results if r["name"] == visible_name]
            if visible_results:
                assert visible_results[0]["has_git"] is True
        finally:
            shutil.rmtree(td, ignore_errors=True)


# Feature: project-browser-enhance, Property 7: Path security validation
class TestPathSecurityValidation:
    """System directories are blocked, home directory descendants are allowed."""

    @given(
        subdir=st.text(
            min_size=1, max_size=8,
            alphabet=st.characters(whitelist_categories=("L", "N")),
        ),
    )
    @settings(max_examples=100)
    def test_home_descendants_allowed(self, subdir: str):
        config = ProjectScannerConfig(search_roots=[], max_depth=3)
        scanner = ProjectScanner(config)
        home = Path.home()
        test_path = home / subdir
        assert scanner._is_allowed_path(test_path) is True

    @given(
        system_dir=st.sampled_from(
            list(ProjectScanner.SYSTEM_DIRS_UNIX)
            if sys.platform != "win32"
            else list(ProjectScanner.SYSTEM_DIRS_WIN)
        ),
    )
    @settings(max_examples=100)
    def test_system_dirs_blocked(self, system_dir: str):
        config = ProjectScannerConfig(search_roots=[], max_depth=3)
        scanner = ProjectScanner(config)
        assert scanner._is_allowed_path(Path(system_dir)) is False

    def test_system_dir_descendants_blocked(self):
        """Subdirectories of system dirs are also blocked."""
        config = ProjectScannerConfig(search_roots=[], max_depth=3)
        scanner = ProjectScanner(config)
        if sys.platform == "win32":
            assert scanner._is_allowed_path(Path("C:\\Windows\\System32")) is False
        else:
            assert scanner._is_allowed_path(Path("/etc/nginx")) is False


# Feature: project-browser-enhance, Property 8: Browse returns only sorted directories
class TestBrowseDirectoriesOnly:
    """list_directory returns only directories (no files), sorted
    alphabetically by name (case-insensitive)."""

    @given(
        dir_names=st.lists(
            st.text(min_size=1, max_size=8, alphabet=st.characters(
                whitelist_categories=("L", "N"),
            )),
            min_size=1, max_size=10, unique=True,
        ),
        file_names=st.lists(
            st.text(min_size=1, max_size=8, alphabet=st.characters(
                whitelist_categories=("L", "N"),
            )).map(lambda s: s + ".txt"),
            min_size=0, max_size=5,
        ),
    )
    @settings(max_examples=100)
    @pytest.mark.asyncio
    async def test_only_dirs_sorted(
        self, dir_names: list[str], file_names: list[str]
    ):
        td = tempfile.mkdtemp()
        try:
            for name in dir_names:
                (Path(td) / name).mkdir(exist_ok=True)
            for name in file_names:
                (Path(td) / name).touch()

            config = ProjectScannerConfig(
                search_roots=[td],
                max_depth=1,
                search_timeout=5.0,
                max_results=50,
            )
            scanner = ProjectScanner(config)

            with patch.object(scanner, '_is_allowed_path', return_value=True):
                results = await scanner.list_directory(td)

            result_names = [r["name"] for r in results]
            for name in file_names:
                assert name not in result_names, f"File {name!r} found in browse results"

            lower_names = [n.lower() for n in result_names]
            assert lower_names == sorted(lower_names)
        finally:
            shutil.rmtree(td, ignore_errors=True)


# Feature: project-browser-enhance, Property 10: Search mode dispatch
class TestSearchModeDispatch:
    """search() returns a list, list_directory() returns a list.
    The handler wraps them with is_browsing accordingly."""

    @pytest.mark.asyncio
    async def test_search_returns_list(self, tmp_path: Path):
        (tmp_path / "myproject").mkdir()
        config = ProjectScannerConfig(
            search_roots=[str(tmp_path)],
            max_depth=1,
            search_timeout=5.0,
            max_results=20,
        )
        scanner = ProjectScanner(config)
        results = await scanner.search("myproject")
        assert isinstance(results, list)

    @pytest.mark.asyncio
    async def test_list_directory_returns_list(self, tmp_path: Path):
        (tmp_path / "subdir").mkdir()
        config = ProjectScannerConfig(
            search_roots=[str(tmp_path)],
            max_depth=1,
            search_timeout=5.0,
            max_results=20,
        )
        scanner = ProjectScanner(config)
        with patch.object(scanner, '_is_allowed_path', return_value=True):
            results = await scanner.list_directory(str(tmp_path))
        assert isinstance(results, list)

    @pytest.mark.asyncio
    async def test_list_directory_rejects_disallowed_path(self, tmp_path: Path):
        config = ProjectScannerConfig(
            search_roots=[str(tmp_path)],
            max_depth=1,
            search_timeout=5.0,
            max_results=20,
        )
        scanner = ProjectScanner(config)
        with patch.object(scanner, '_is_allowed_path', return_value=False):
            with pytest.raises(ValueError, match="无法访问"):
                await scanner.list_directory(str(tmp_path))


# ═══════════════════════════════════════════════════════════════
# Unit tests — project type detection
# ═══════════════════════════════════════════════════════════════


class TestProjectTypeDetection:
    """Verify _detect_project_type for each known marker file."""

    @pytest.mark.parametrize("marker,expected", [
        ("pyproject.toml", "python"),
        ("setup.py", "python"),
        ("requirements.txt", "python"),
        ("package.json", "node"),
        ("pubspec.yaml", "flutter"),
        ("Cargo.toml", "rust"),
        ("go.mod", "go"),
        ("pom.xml", "java"),
        ("build.gradle", "java"),
        ("build.gradle.kts", "java"),
        ("CMakeLists.txt", "cpp"),
        ("Makefile", "unknown"),
    ])
    def test_detect_known_markers(self, tmp_path: Path, marker: str, expected: str):
        (tmp_path / marker).touch()
        assert ProjectScanner._detect_project_type(tmp_path) == expected

    def test_detect_no_marker(self, tmp_path: Path):
        assert ProjectScanner._detect_project_type(tmp_path) is None

    def test_detect_priority_order(self, tmp_path: Path):
        """When multiple markers exist, first match wins."""
        (tmp_path / "pyproject.toml").touch()
        (tmp_path / "package.json").touch()
        assert ProjectScanner._detect_project_type(tmp_path) == "python"


class TestHasGit:
    """Verify _has_git detection."""

    def test_has_git_true(self, tmp_path: Path):
        (tmp_path / ".git").mkdir()
        assert ProjectScanner._has_git(tmp_path) is True

    def test_has_git_false(self, tmp_path: Path):
        assert ProjectScanner._has_git(tmp_path) is False

    def test_has_git_file_not_dir(self, tmp_path: Path):
        (tmp_path / ".git").touch()
        assert ProjectScanner._has_git(tmp_path) is False


class TestWindowsDriveDetection:
    """Windows drive detection with mocked ctypes."""

    def test_non_windows_returns_empty(self):
        config = ProjectScannerConfig(search_roots=[], max_depth=3)
        scanner = ProjectScanner(config)
        with patch.object(sys, 'platform', 'linux'):
            assert scanner.get_windows_drives() == []

    @patch('sys.platform', 'win32')
    def test_windows_drives_mocked(self):
        """Mock GetLogicalDrives bitmask: C (bit 2) + D (bit 3) = 0b1100 = 12."""
        config = ProjectScannerConfig(search_roots=[], max_depth=3)
        scanner = ProjectScanner(config)

        mock_kernel32 = MagicMock()
        mock_kernel32.GetLogicalDrives.return_value = 12

        with patch.dict('sys.modules', {'ctypes': MagicMock()}):
            import ctypes
            ctypes.windll = MagicMock()
            ctypes.windll.kernel32 = mock_kernel32
            drives = scanner.get_windows_drives()

        assert "C:\\" in drives
        assert "D:\\" in drives
        assert "A:\\" not in drives


class TestAutoDetectSearchRoots:
    """Auto-detect search roots when config.search_roots is empty."""

    def test_auto_detect_includes_home(self):
        config = ProjectScannerConfig(search_roots=[], max_depth=3)
        scanner = ProjectScanner(config)
        roots = scanner._resolve_search_roots()
        home = Path.home().resolve()
        assert home in roots

    def test_configured_roots_used_directly(self, tmp_path: Path):
        config = ProjectScannerConfig(
            search_roots=[str(tmp_path)],
            max_depth=3,
        )
        scanner = ProjectScanner(config)
        roots = scanner._resolve_search_roots()
        assert tmp_path.resolve() in roots

    def test_nonexistent_configured_root_skipped(self, tmp_path: Path):
        fake_path = str(tmp_path / "nonexistent")
        config = ProjectScannerConfig(
            search_roots=[fake_path],
            max_depth=3,
        )
        scanner = ProjectScanner(config)
        roots = scanner._resolve_search_roots()
        assert len(roots) == 0
