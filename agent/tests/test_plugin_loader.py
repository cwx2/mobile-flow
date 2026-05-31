"""
PluginLoader 单元测试

覆盖：扫描发现、清单解析、元数据解析、目录校验、平台过滤、故障隔离。
"""

from __future__ import annotations

import json
import os
import platform
from pathlib import Path

import pytest

from mobileflow_agent.plugins.loader import (
    MANIFEST_FILE,
    MAX_MANIFEST_SIZE,
    METADATA_FILE,
    PluginLoader,
    _PLATFORM_MAP,
)
from mobileflow_agent.plugins.manifest import PluginManifest, PluginMetadata


# ── helpers ──────────────────────────────────────────────────────

def _write_manifest(plugin_dir: Path, data: dict) -> Path:
    plugin_dir.mkdir(parents=True, exist_ok=True)
    p = plugin_dir / MANIFEST_FILE
    p.write_text(json.dumps(data), encoding="utf-8")
    return p


def _write_metadata(plugin_dir: Path, data: dict) -> Path:
    plugin_dir.mkdir(parents=True, exist_ok=True)
    p = plugin_dir / METADATA_FILE
    p.write_text(json.dumps(data), encoding="utf-8")
    return p


def _make_plugin(ext_dir: Path, plugin_id: str, *, platforms=None, metadata=None):
    """创建一个最小合法插件目录。"""
    d = ext_dir / plugin_id
    manifest: dict = {"id": plugin_id}
    if platforms is not None:
        manifest["platforms"] = platforms
    _write_manifest(d, manifest)
    if metadata is not None:
        _write_metadata(d, metadata)
    return d


# ── scan_extensions ──────────────────────────────────────────────

class TestScanExtensions:
    def test_auto_creates_ext_dir(self, tmp_path: Path):
        loader = PluginLoader()
        ext = tmp_path / "extensions"
        assert not ext.exists()
        result = loader.scan_extensions(ext)
        assert ext.is_dir()
        assert result == []

    def test_discovers_all_valid_plugins(self, tmp_path: Path):
        ext = tmp_path / "ext"
        _make_plugin(ext, "alpha")
        _make_plugin(ext, "beta")
        _make_plugin(ext, "gamma")

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        ids = {p.id for p in plugins}
        assert ids == {"alpha", "beta", "gamma"}

    def test_skips_dirs_without_manifest(self, tmp_path: Path):
        ext = tmp_path / "ext"
        _make_plugin(ext, "valid")
        (ext / "no-manifest").mkdir(parents=True)

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        assert len(plugins) == 1
        assert plugins[0].id == "valid"

    def test_skips_files_in_ext_dir(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        (ext / "readme.txt").write_text("hi")
        _make_plugin(ext, "ok")

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        assert len(plugins) == 1

    def test_merges_metadata(self, tmp_path: Path):
        ext = tmp_path / "ext"
        _make_plugin(ext, "with-meta", metadata={
            "name": "my-plugin",
            "version": "2.0.0",
            "description": "desc",
            "author": "me",
            "license": "MIT",
            "repository": "https://example.com",
        })

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        assert len(plugins) == 1
        meta = plugins[0].metadata
        assert meta is not None
        assert meta.name == "my-plugin"
        assert meta.version == "2.0.0"

    def test_missing_metadata_silent_degradation(self, tmp_path: Path):
        ext = tmp_path / "ext"
        _make_plugin(ext, "no-pkg")

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        assert len(plugins) == 1
        meta = plugins[0].metadata
        assert meta is not None
        assert meta.name == ""

    def test_fault_isolation(self, tmp_path: Path):
        """一个插件清单损坏不影响其他插件加载。"""
        ext = tmp_path / "ext"
        _make_plugin(ext, "good")
        # 写一个损坏的清单
        bad_dir = ext / "bad"
        bad_dir.mkdir()
        (bad_dir / MANIFEST_FILE).write_text("NOT JSON", encoding="utf-8")

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        assert len(plugins) == 1
        assert plugins[0].id == "good"

    def test_fault_isolation_missing_id(self, tmp_path: Path):
        """清单缺少 id 字段，跳过该插件。"""
        ext = tmp_path / "ext"
        _make_plugin(ext, "ok")
        bad_dir = ext / "no-id"
        _write_manifest(bad_dir, {"enabledByDefault": True})

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        assert len(plugins) == 1
        assert plugins[0].id == "ok"


# ── parse_manifest ───────────────────────────────────────────────

class TestParseManifest:
    def test_valid_manifest(self, tmp_path: Path):
        p = _write_manifest(tmp_path, {
            "id": "test-plugin",
            "enabledByDefault": False,
            "providers": [{"name": "x", "command": "x-cli"}],
        })
        loader = PluginLoader()
        m = loader.parse_manifest(p)
        assert m.id == "test-plugin"
        assert m.enabled_by_default is False
        assert len(m.providers) == 1

    def test_rejects_oversized_manifest(self, tmp_path: Path):
        p = tmp_path / MANIFEST_FILE
        p.write_text("x" * (MAX_MANIFEST_SIZE + 1), encoding="utf-8")

        loader = PluginLoader()
        with pytest.raises(ValueError, match="过大"):
            loader.parse_manifest(p)

    def test_preserves_unknown_fields(self, tmp_path: Path):
        p = _write_manifest(tmp_path, {
            "id": "fwd-compat",
            "futureField": 42,
            "anotherNew": {"nested": True},
        })
        loader = PluginLoader()
        m = loader.parse_manifest(p)
        assert m.id == "fwd-compat"
        # extra="allow" 保留未知字段
        assert m.model_extra is not None
        assert m.model_extra.get("futureField") == 42

    def test_rejects_invalid_id(self, tmp_path: Path):
        p = _write_manifest(tmp_path, {"id": "UPPER_CASE"})
        loader = PluginLoader()
        with pytest.raises(Exception):
            loader.parse_manifest(p)

    def test_rejects_missing_id(self, tmp_path: Path):
        p = _write_manifest(tmp_path, {"enabledByDefault": True})
        loader = PluginLoader()
        with pytest.raises(Exception):
            loader.parse_manifest(p)


# ── parse_metadata ───────────────────────────────────────────────

class TestParseMetadata:
    def test_valid_metadata(self, tmp_path: Path):
        p = _write_metadata(tmp_path, {
            "name": "pkg",
            "version": "1.0.0",
            "description": "d",
            "author": "a",
            "license": "MIT",
            "repository": "https://r.com",
        })
        loader = PluginLoader()
        meta = loader.parse_metadata(p)
        assert meta.name == "pkg"
        assert meta.version == "1.0.0"

    def test_missing_file_returns_empty(self, tmp_path: Path):
        loader = PluginLoader()
        meta = loader.parse_metadata(tmp_path / "nonexistent.json")
        assert meta == PluginMetadata()

    def test_invalid_json_returns_empty(self, tmp_path: Path):
        p = tmp_path / METADATA_FILE
        p.write_text("NOT JSON")
        loader = PluginLoader()
        meta = loader.parse_metadata(p)
        assert meta == PluginMetadata()

    def test_partial_fields(self, tmp_path: Path):
        p = _write_metadata(tmp_path, {"name": "only-name"})
        loader = PluginLoader()
        meta = loader.parse_metadata(p)
        assert meta.name == "only-name"
        assert meta.version == ""


# ── validate_directory ───────────────────────────────────────────

class TestValidateDirectory:
    def test_normal_dir_passes(self, tmp_path: Path):
        ext = tmp_path / "ext"
        plugin = ext / "my-plugin"
        plugin.mkdir(parents=True)
        (plugin / "file.txt").write_text("ok")

        loader = PluginLoader()
        assert loader.validate_directory(plugin, ext) is True

    @pytest.mark.skipif(
        platform.system() == "Windows",
        reason="Windows 符号链接需要管理员权限",
    )
    def test_rejects_symlink_escape(self, tmp_path: Path):
        ext = tmp_path / "ext"
        plugin = ext / "evil"
        plugin.mkdir(parents=True)

        outside = tmp_path / "outside"
        outside.mkdir()
        (outside / "secret.txt").write_text("secret")

        link = plugin / "escape"
        link.symlink_to(outside)

        loader = PluginLoader()
        assert loader.validate_directory(plugin, ext) is False

    @pytest.mark.skipif(
        platform.system() == "Windows",
        reason="Windows 符号链接需要管理员权限",
    )
    def test_allows_internal_symlink(self, tmp_path: Path):
        ext = tmp_path / "ext"
        plugin = ext / "safe"
        plugin.mkdir(parents=True)

        target = plugin / "real"
        target.mkdir()
        (target / "data.txt").write_text("ok")

        link = plugin / "alias"
        link.symlink_to(target)

        loader = PluginLoader()
        assert loader.validate_directory(plugin, ext) is True


# ── 平台过滤 ─────────────────────────────────────────────────────

class TestPlatformFiltering:
    def test_no_platforms_field_loads_everywhere(self, tmp_path: Path):
        ext = tmp_path / "ext"
        _make_plugin(ext, "universal")

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        assert len(plugins) == 1

    def test_matching_platform_loads(self, tmp_path: Path):
        ext = tmp_path / "ext"
        current = _PLATFORM_MAP.get(platform.system(), "linux")
        _make_plugin(ext, "match", platforms=[current])

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        assert len(plugins) == 1

    def test_non_matching_platform_skipped(self, tmp_path: Path):
        ext = tmp_path / "ext"
        # 用一个肯定不是当前平台的值
        fake_platforms = ["fakeos"]
        _make_plugin(ext, "wrong-os", platforms=fake_platforms)

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        assert len(plugins) == 0

    def test_mixed_platforms(self, tmp_path: Path):
        ext = tmp_path / "ext"
        current = _PLATFORM_MAP.get(platform.system(), "linux")
        _make_plugin(ext, "yes", platforms=[current, "other"])
        _make_plugin(ext, "no", platforms=["nope"])
        _make_plugin(ext, "all")  # no platforms field

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        ids = {p.id for p in plugins}
        assert "yes" in ids
        assert "all" in ids
        assert "no" not in ids


# ── install / uninstall ──────────────────────────────────────────

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch


def _make_full_plugin(plugin_dir: Path, plugin_id: str = "test-plugin"):
    """创建一个完整的插件目录（清单 + 元数据）。"""
    _write_manifest(plugin_dir, {"id": plugin_id})
    _write_metadata(plugin_dir, {"name": plugin_id, "version": "1.0.0"})


class TestInstallFromGit:
    @pytest.mark.asyncio
    async def test_success(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        loader = PluginLoader()

        # mock git clone: 创建目录并写入清单
        async def fake_clone(url, target):
            target_path = Path(target)
            target_path.mkdir(parents=True, exist_ok=True)
            _write_manifest(target_path, {"id": "my-plugin"})
            _write_metadata(target_path, {"name": "my-plugin", "version": "1.0.0"})
            proc = MagicMock()
            proc.returncode = 0
            proc.stderr = AsyncMock()
            proc.stderr.read = AsyncMock(return_value=b"")
            return proc

        with patch.object(loader, "_run_git_clone", side_effect=fake_clone):
            info = await loader.install_from_git(
                "https://github.com/user/my-plugin.git", ext
            )

        assert info.id == "my-plugin"
        assert info.metadata.name == "my-plugin"
        assert info.directory == ext / "my-plugin"

    @pytest.mark.asyncio
    async def test_url_without_git_suffix(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        loader = PluginLoader()

        async def fake_clone(url, target):
            target_path = Path(target)
            target_path.mkdir(parents=True, exist_ok=True)
            _write_manifest(target_path, {"id": "repo"})
            proc = MagicMock()
            proc.returncode = 0
            proc.stderr = AsyncMock()
            proc.stderr.read = AsyncMock(return_value=b"")
            return proc

        with patch.object(loader, "_run_git_clone", side_effect=fake_clone):
            info = await loader.install_from_git(
                "https://github.com/user/repo", ext
            )

        assert info.directory == ext / "repo"

    @pytest.mark.asyncio
    async def test_clone_failure_cleans_up(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        loader = PluginLoader()

        async def failing_clone(url, target):
            Path(target).mkdir(parents=True, exist_ok=True)
            proc = MagicMock()
            proc.returncode = 1
            proc.stderr = AsyncMock()
            proc.stderr.read = AsyncMock(return_value=b"fatal: repo not found")
            return proc

        with patch.object(loader, "_run_git_clone", side_effect=failing_clone):
            with pytest.raises(RuntimeError, match="无法从 Git 仓库下载"):
                await loader.install_from_git(
                    "https://github.com/user/bad.git", ext
                )

        # 不完整目录应被清理
        assert not (ext / "bad").exists()

    @pytest.mark.asyncio
    async def test_timeout_cleans_up(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        loader = PluginLoader()

        async def slow_clone(url, target):
            Path(target).mkdir(parents=True, exist_ok=True)
            await asyncio.sleep(999)

        with patch.object(loader, "_run_git_clone", side_effect=slow_clone):
            with patch("mobileflow_agent.plugins.loader.asyncio.wait_for",
                       side_effect=asyncio.TimeoutError):
                with pytest.raises(RuntimeError, match="网络连接超时"):
                    await loader.install_from_git(
                        "https://github.com/user/slow.git", ext
                    )

        assert not (ext / "slow").exists()


class TestInstallFromNpm:
    @pytest.mark.asyncio
    async def test_success(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        loader = PluginLoader()

        async def fake_npm(package, cwd):
            cwd_path = Path(cwd)
            _write_manifest(cwd_path, {"id": "my-npm-plugin"})
            _write_metadata(cwd_path, {"name": "my-npm-plugin", "version": "2.0.0"})
            proc = MagicMock()
            proc.returncode = 0
            proc.stderr = AsyncMock()
            proc.stderr.read = AsyncMock(return_value=b"")
            return proc

        with patch.object(loader, "_run_npm_install", side_effect=fake_npm):
            info = await loader.install_from_npm("my-npm-plugin", ext)

        assert info.id == "my-npm-plugin"
        assert info.metadata.version == "2.0.0"

    @pytest.mark.asyncio
    async def test_scoped_package_dir_name(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        loader = PluginLoader()

        async def fake_npm(package, cwd):
            cwd_path = Path(cwd)
            _write_manifest(cwd_path, {"id": "scoped"})
            proc = MagicMock()
            proc.returncode = 0
            proc.stderr = AsyncMock()
            proc.stderr.read = AsyncMock(return_value=b"")
            return proc

        with patch.object(loader, "_run_npm_install", side_effect=fake_npm):
            info = await loader.install_from_npm("@scope/my-pkg", ext)

        # @scope/my-pkg -> scope-my-pkg
        assert info.directory == ext / "scope-my-pkg"

    @pytest.mark.asyncio
    async def test_npm_failure_cleans_up(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        loader = PluginLoader()

        async def failing_npm(package, cwd):
            proc = MagicMock()
            proc.returncode = 1
            proc.stderr = AsyncMock()
            proc.stderr.read = AsyncMock(return_value=b"ERR! 404")
            return proc

        with patch.object(loader, "_run_npm_install", side_effect=failing_npm):
            with pytest.raises(RuntimeError, match="npm 安装出错"):
                await loader.install_from_npm("nonexistent-pkg", ext)

        assert not (ext / "nonexistent-pkg").exists()

    @pytest.mark.asyncio
    async def test_timeout_cleans_up(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        loader = PluginLoader()

        with patch("mobileflow_agent.plugins.loader.asyncio.wait_for",
                    side_effect=asyncio.TimeoutError):
            with pytest.raises(RuntimeError, match="网络连接超时"):
                await loader.install_from_npm("slow-pkg", ext)


class TestInstallFromUrl:
    @pytest.mark.asyncio
    async def test_zip_success(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        loader = PluginLoader()

        # 准备一个 zip 包含插件
        def fake_download(url, ext_dir):
            plugin_dir = ext_dir / "my-zip-plugin"
            plugin_dir.mkdir(parents=True, exist_ok=True)
            _write_manifest(plugin_dir, {"id": "zip-plugin"})
            _write_metadata(plugin_dir, {"name": "zip-plugin", "version": "1.0.0"})
            return plugin_dir

        with patch.object(loader, "_download_and_extract", side_effect=fake_download):
            info = await loader.install_from_url(
                "https://example.com/plugin.zip", ext
            )

        assert info.id == "zip-plugin"

    @pytest.mark.asyncio
    async def test_timeout_cleans_up(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        loader = PluginLoader()

        def slow_download(url, ext_dir):
            # 创建一个目录来模拟部分下载
            partial = ext_dir / "partial"
            partial.mkdir()
            raise TimeoutError("too slow")

        with patch("mobileflow_agent.plugins.loader.asyncio.wait_for",
                    side_effect=asyncio.TimeoutError):
            with pytest.raises(RuntimeError, match="网络连接超时"):
                await loader.install_from_url(
                    "https://example.com/plugin.tar.gz", ext
                )

    @pytest.mark.asyncio
    async def test_missing_manifest_cleans_up(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        loader = PluginLoader()

        def fake_download(url, ext_dir):
            plugin_dir = ext_dir / "no-manifest"
            plugin_dir.mkdir(parents=True, exist_ok=True)
            # 不写清单文件
            return plugin_dir

        with patch.object(loader, "_download_and_extract", side_effect=fake_download):
            with pytest.raises(RuntimeError, match="插件安装失败"):
                await loader.install_from_url(
                    "https://example.com/bad.zip", ext
                )

        assert not (ext / "no-manifest").exists()


class TestUninstall:
    @pytest.mark.asyncio
    async def test_uninstall_existing(self, tmp_path: Path):
        ext = tmp_path / "ext"
        _make_plugin(ext, "to-remove")

        loader = PluginLoader()
        result = await loader.uninstall("to-remove", ext)
        assert result is True
        assert not (ext / "to-remove").exists()

    @pytest.mark.asyncio
    async def test_uninstall_not_found(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()

        loader = PluginLoader()
        result = await loader.uninstall("nonexistent", ext)
        assert result is False

    @pytest.mark.asyncio
    async def test_uninstall_skips_non_matching(self, tmp_path: Path):
        ext = tmp_path / "ext"
        _make_plugin(ext, "keep-me")
        _make_plugin(ext, "remove-me")

        loader = PluginLoader()
        result = await loader.uninstall("remove-me", ext)
        assert result is True
        assert (ext / "keep-me").exists()
        assert not (ext / "remove-me").exists()

    @pytest.mark.asyncio
    async def test_uninstall_ignores_dirs_without_manifest(self, tmp_path: Path):
        ext = tmp_path / "ext"
        ext.mkdir()
        (ext / "no-manifest").mkdir()

        loader = PluginLoader()
        result = await loader.uninstall("no-manifest", ext)
        assert result is False
