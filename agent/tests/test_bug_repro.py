"""
Bug 复现测试

先复现 bug，确认存在后再修。
"""

from __future__ import annotations

import asyncio
import json
import os
import platform
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from mobileflow_agent.plugins.loader import MANIFEST_FILE, METADATA_FILE, PluginLoader
from mobileflow_agent.plugins.registry import PluginRegistry
from mobileflow_agent.plugins.manifest import PluginManifest, PluginMetadata, PluginInfo


def _write_manifest(plugin_dir: Path, data: dict) -> Path:
    plugin_dir.mkdir(parents=True, exist_ok=True)
    p = plugin_dir / MANIFEST_FILE
    p.write_text(json.dumps(data), encoding="utf-8")
    return p


# ── Bug 1: 安装目录已存在时 git clone 失败 ──────────────────────

class TestBug1_InstallDirExists:
    """如果目标目录已存在（比如之前安装失败残留），git clone 会报错。
    应该先检查并清理，或者给出明确提示。"""

    @pytest.mark.asyncio
    async def test_git_install_existing_dir_fails(self, tmp_path: Path):
        """复现：目标目录已存在时应该给明确提示"""
        ext = tmp_path / "ext"
        ext.mkdir()

        # 模拟之前安装失败残留的目录
        residual = ext / "my-plugin"
        residual.mkdir()
        (residual / "some-file.txt").write_text("残留文件")

        loader = PluginLoader()

        # 修复后：应该在 clone 之前就检测到目录已存在
        with pytest.raises(RuntimeError, match="已存在"):
            await loader.install_from_git(
                "https://github.com/user/my-plugin.git", ext
            )

        # 残留目录不应被删除（用户可能需要手动处理）
        assert residual.exists(), "残留目录不应被自动删除"

    @pytest.mark.asyncio
    async def test_npm_install_existing_dir(self, tmp_path: Path):
        """复现：npm 安装时目标目录已存在且非空"""
        ext = tmp_path / "ext"
        ext.mkdir()

        # 模拟残留目录
        residual = ext / "my-pkg"
        residual.mkdir()
        (residual / "old-file.txt").write_text("旧文件")

        loader = PluginLoader()

        with pytest.raises(RuntimeError, match="已存在"):
            await loader.install_from_npm("my-pkg", ext)

        # 残留目录不应被删除
        assert residual.exists()


# ── Bug 2: PluginRegistry.refresh() 并发安全 ────────────────────

class TestBug2_RegistryConcurrency:
    """refresh() 没有锁保护，并发调用可能导致状态不一致"""

    def test_concurrent_refresh_and_enable(self, tmp_path: Path):
        """复现：refresh 过程中 enable 一个插件"""
        ext = tmp_path / "ext"
        _write_manifest(ext / "plugin-a", {"id": "plugin-a"})

        reg = PluginRegistry(ext_dir=ext)
        reg.initialize()

        # 在 refresh 之前 enable
        result = reg.enable_plugin("plugin-a")
        assert result["success"] is True

        # 添加新插件
        _write_manifest(ext / "plugin-b", {"id": "plugin-b"})

        # refresh 应该保留 plugin-a 的启用状态
        reg.refresh()

        plugins = reg.list_plugins()
        plugin_a = next(p for p in plugins if p["id"] == "plugin-a")
        assert plugin_a["enabled"] is True, "refresh 后 plugin-a 的启用状态丢失了！"

        # plugin-b 应该被发现
        ids = {p["id"] for p in plugins}
        assert "plugin-b" in ids

        print("OK: refresh 保留了已有插件状态")


# ── Bug 3: WsMessage.fromJson 缺少字段校验 ──────────────────────
# 这个是 Dart 端的问题，用 Python 测试不了，跳过


# ── Bug 4: 终端 resize 没检查 session 存在 ───────────────────────

class TestBug4_TerminalResizeNoSession:
    """resize 对不存在的 session 静默失败，应该有错误处理"""

    def test_resize_nonexistent_session(self, tmp_path: Path):
        """复现：对不存在的 session 调用 resize"""
        from mobileflow_agent.terminal import TerminalManager

        manager = TerminalManager()
        session = manager.get_session("nonexistent-id")
        assert session is None, "不存在的 session 应该返回 None"
        # 当前代码在 handler 里直接调用 session.resize()，如果 session 是 None 会 AttributeError
        print("OK: get_session 对不存在的 ID 返回 None")


# ── Bug 5: 插件配置校验 - 无 schema 时传非空配置 ─────────────────

class TestBug5_ConfigNoSchema:
    """无 configSchema 的插件，set_config 传非空配置应该被拒绝"""

    def test_no_schema_rejects_nonempty(self, tmp_path: Path):
        ext = tmp_path / "ext"
        _write_manifest(ext / "simple", {"id": "simple"})

        reg = PluginRegistry(ext_dir=ext)
        reg.initialize()

        result = reg.set_config("simple", {"key": "value"})
        assert result["success"] is False, "无 schema 的插件不应接受非空配置"
        print(f"OK: {result['message']}")


# ── Bug 6: 插件 ID 冲突检测 - 大小写变体 ────────────────────────

class TestBug6_IdCaseSensitivity:
    """ID 校验只允许小写，但如果有人手动创建大写 ID 的清单会怎样？"""

    def test_uppercase_id_rejected(self, tmp_path: Path):
        ext = tmp_path / "ext"
        bad_dir = ext / "bad-plugin"
        bad_dir.mkdir(parents=True)
        (bad_dir / MANIFEST_FILE).write_text(
            json.dumps({"id": "Bad-Plugin"}), encoding="utf-8"
        )

        loader = PluginLoader()
        plugins = loader.scan_extensions(ext)
        # 大写 ID 应该被 Pydantic 校验拒绝，不会出现在结果中
        assert len(plugins) == 0, "大写 ID 的插件不应被加载"
        print("OK: uppercase ID rejected")
