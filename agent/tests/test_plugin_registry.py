"""
PluginRegistry 单元测试 — 配置管理

覆盖：get_config、set_config、_validate_config、_config_dir、
      _load_config、_save_config。
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from mobileflow_agent.plugins.manifest import (
    PluginInfo,
    PluginManifest,
    PluginMetadata,
)
from mobileflow_agent.plugins.registry import PluginRegistry


# ── helpers ──────────────────────────────────────────────────────


def _make_registry(tmp_path: Path) -> PluginRegistry:
    """创建一个使用临时目录的 PluginRegistry。"""
    ext_dir = tmp_path / "extensions"
    ext_dir.mkdir(parents=True)
    return PluginRegistry(ext_dir=ext_dir)


def _register_plugin(
    registry: PluginRegistry,
    plugin_id: str,
    *,
    config_schema: dict | None = None,
    ui_hints: dict | None = None,
    config_contracts=None,
) -> PluginInfo:
    """手动向注册表中注入一个插件（跳过 loader 扫描）。"""
    manifest = PluginManifest(
        id=plugin_id,
        config_schema=config_schema,
        **({"config_contracts": config_contracts} if config_contracts else {}),
    )
    # 手动设置 ui_hints（需要通过 UiHint 对象）
    if ui_hints:
        from mobileflow_agent.plugins.manifest import UiHint

        manifest.ui_hints = {k: UiHint(**v) for k, v in ui_hints.items()}

    plugin = PluginInfo(
        id=plugin_id,
        manifest=manifest,
        metadata=PluginMetadata(name=plugin_id),
        directory=Path("/fake"),
        enabled=True,
        status="active",
    )
    registry._plugins[plugin_id] = plugin
    return plugin


# ── _config_dir ──────────────────────────────────────────────────


class TestConfigDir:
    def test_returns_correct_path(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        assert reg._config_dir == tmp_path / "plugin_configs"

    def test_auto_creates_directory(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        d = reg._config_dir
        assert d.is_dir()


# ── _load_config / _save_config ──────────────────────────────────


class TestLoadSaveConfig:
    def test_load_missing_file_returns_empty(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        assert reg._load_config("nonexistent") == {}

    def test_save_then_load_roundtrip(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        cfg = {"model": "gpt-4", "temperature": 0.7}
        reg._save_config("test-plugin", cfg)
        loaded = reg._load_config("test-plugin")
        assert loaded == cfg

    def test_load_corrupted_file_returns_empty(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        path = reg._config_dir / "bad.json"
        path.write_text("NOT JSON", encoding="utf-8")
        assert reg._load_config("bad") == {}

    def test_load_non_dict_returns_empty(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        path = reg._config_dir / "arr.json"
        path.write_text("[1,2,3]", encoding="utf-8")
        assert reg._load_config("arr") == {}

    def test_save_creates_config_dir(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        # 确保 plugin_configs 目录还不存在
        config_dir = tmp_path / "plugin_configs"
        assert not config_dir.exists() or config_dir.is_dir()
        reg._save_config("new-plugin", {"key": "val"})
        assert (config_dir / "new-plugin.json").exists()

    def test_save_unicode_content(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        cfg = {"名称": "测试插件", "描述": "中文内容"}
        reg._save_config("unicode-test", cfg)
        loaded = reg._load_config("unicode-test")
        assert loaded == cfg


# ── _validate_config ─────────────────────────────────────────────


class TestValidateConfig:
    def test_valid_config_returns_empty(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        schema = {
            "type": "object",
            "properties": {
                "model": {"type": "string", "enum": ["gpt-4", "gpt-3.5"]},
            },
        }
        errors = reg._validate_config(schema, {"model": "gpt-4"})
        assert errors == []

    def test_invalid_config_returns_errors(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        schema = {
            "type": "object",
            "properties": {
                "model": {"type": "string", "enum": ["gpt-4", "gpt-3.5"]},
            },
        }
        errors = reg._validate_config(schema, {"model": "invalid-model"})
        assert len(errors) == 1
        assert "model" in errors[0]
        assert "不合法" in errors[0]

    def test_multiple_errors(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        schema = {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "age": {"type": "integer"},
            },
            "required": ["name", "age"],
        }
        errors = reg._validate_config(schema, {})
        assert len(errors) == 2

    def test_root_level_error(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        schema = {"type": "object"}
        errors = reg._validate_config(schema, "not-an-object")
        assert len(errors) == 1
        assert "配置不合法" in errors[0]

    def test_empty_config_against_empty_schema(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        schema = {"type": "object"}
        errors = reg._validate_config(schema, {})
        assert errors == []


# ── get_config ───────────────────────────────────────────────────


class TestGetConfig:
    def test_unknown_plugin_returns_error(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        result = reg.get_config("nonexistent")
        assert result["plugin_id"] == "nonexistent"
        assert "error" in result
        assert "找不到" in result["error"]

    def test_returns_empty_config_when_no_file(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        _register_plugin(reg, "my-plugin")
        result = reg.get_config("my-plugin")
        assert result["plugin_id"] == "my-plugin"
        assert result["config"] == {}
        assert result["config_schema"] is None

    def test_returns_saved_config(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        _register_plugin(reg, "my-plugin", config_schema={"type": "object"})
        reg._save_config("my-plugin", {"key": "value"})

        result = reg.get_config("my-plugin")
        assert result["config"] == {"key": "value"}
        assert result["config_schema"] == {"type": "object"}

    def test_includes_ui_hints(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        _register_plugin(
            reg,
            "hinted",
            ui_hints={"model": {"label": "模型", "help": "选择模型"}},
        )
        result = reg.get_config("hinted")
        assert "model" in result["ui_hints"]
        assert result["ui_hints"]["model"]["label"] == "模型"

    def test_includes_config_contracts(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        _register_plugin(
            reg,
            "contracted",
            config_contracts={
                "dangerous_flags": [{"path": "debug", "equals": True}],
            },
        )
        result = reg.get_config("contracted")
        assert result["config_contracts"] is not None
        assert len(result["config_contracts"]["dangerousFlags"]) == 1

    def test_no_config_contracts_returns_none(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        _register_plugin(reg, "simple")
        result = reg.get_config("simple")
        assert result["config_contracts"] is None


# ── set_config ───────────────────────────────────────────────────


class TestSetConfig:
    def test_unknown_plugin_returns_failure(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        result = reg.set_config("ghost", {"key": "val"})
        assert result["success"] is False
        assert "找不到" in result["message"]

    def test_no_schema_accepts_empty_config(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        _register_plugin(reg, "no-schema")
        result = reg.set_config("no-schema", {})
        assert result["success"] is True
        assert result["errors"] == []

    def test_no_schema_rejects_nonempty_config(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        _register_plugin(reg, "no-schema")
        result = reg.set_config("no-schema", {"key": "val"})
        assert result["success"] is False
        assert len(result["errors"]) == 1

    def test_valid_config_saves_successfully(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        schema = {
            "type": "object",
            "properties": {
                "model": {"type": "string", "enum": ["a", "b"]},
            },
        }
        _register_plugin(reg, "configurable", config_schema=schema)

        result = reg.set_config("configurable", {"model": "a"})
        assert result["success"] is True
        assert result["message"] == "配置已保存"
        assert result["errors"] == []

        # 验证持久化
        loaded = reg._load_config("configurable")
        assert loaded == {"model": "a"}

    def test_invalid_config_returns_errors(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        schema = {
            "type": "object",
            "properties": {
                "model": {"type": "string", "enum": ["a", "b"]},
            },
        }
        _register_plugin(reg, "strict", config_schema=schema)

        result = reg.set_config("strict", {"model": "invalid"})
        assert result["success"] is False
        assert len(result["errors"]) > 0
        assert "model" in result["errors"][0]

    def test_invalid_config_not_persisted(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        schema = {
            "type": "object",
            "properties": {"x": {"type": "integer"}},
        }
        _register_plugin(reg, "guarded", config_schema=schema)

        reg.set_config("guarded", {"x": "not-int"})
        # 配置文件不应被创建
        assert reg._load_config("guarded") == {}

    def test_overwrite_existing_config(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        schema = {"type": "object"}
        _register_plugin(reg, "updatable", config_schema=schema)

        reg.set_config("updatable", {"v": 1})
        reg.set_config("updatable", {"v": 2})
        assert reg._load_config("updatable") == {"v": 2}


# ── _inject_agents / _eject_agents ───────────────────────────────

from mobileflow_agent.plugins.manifest import ProviderDecl
from mobileflow_agent.providers.registry import ProviderRegistry


def _make_registry_with_provider(tmp_path: Path) -> tuple[PluginRegistry, ProviderRegistry]:
    """创建带 ProviderRegistry 的 PluginRegistry。"""
    ext_dir = tmp_path / "extensions"
    ext_dir.mkdir(parents=True)
    pr = ProviderRegistry()
    return PluginRegistry(ext_dir=ext_dir, provider_registry=pr), pr


def _make_agent_plugin(
    plugin_id: str,
    providers: list[dict],
) -> PluginInfo:
    """创建一个带 providers 的 PluginInfo。"""
    decls = [ProviderDecl(**p) for p in providers]
    manifest = PluginManifest(id=plugin_id, providers=decls)
    return PluginInfo(
        id=plugin_id,
        manifest=manifest,
        metadata=PluginMetadata(name=plugin_id),
        directory=Path("/fake"),
        enabled=True,
        status="active",
    )


class TestInjectAgents:
    def test_injects_provider_into_registry(self, tmp_path: Path):
        reg, pr = _make_registry_with_provider(tmp_path)
        plugin = _make_agent_plugin("test-plugin", [
            {
                "name": "my-agent",
                "command": "my-agent-cli",
                "args": ["acp"],
                "display_name": "My Agent",
                "terminal_cmd": "my-agent-cli",
                "install_hint": "npm i -g my-agent",
                "install_npm": "my-agent",
            },
        ])
        reg._inject_agents(plugin)

        # Agent 应出现在 ProviderRegistry 的 detected 列表中
        all_agents = pr.list_all()
        names = [a["name"] for a in all_agents]
        assert "my-agent" in names

        found = next(a for a in all_agents if a["name"] == "my-agent")
        assert found["source"] == "plugin"

    def test_noop_when_no_provider_registry(self, tmp_path: Path):
        reg = _make_registry(tmp_path)  # provider_registry=None
        plugin = _make_agent_plugin("test-plugin", [
            {"name": "x", "command": "x", "display_name": "X"},
        ])
        # 不应抛异常
        reg._inject_agents(plugin)

    def test_conflict_with_builtin_logs_warning(self, tmp_path: Path):
        reg, pr = _make_registry_with_provider(tmp_path)
        # "claude-code" 是内置 Agent
        plugin = _make_agent_plugin("bad-plugin", [
            {
                "name": "claude-code",
                "command": "claude",
                "display_name": "Fake Claude",
            },
        ])
        reg._inject_agents(plugin)

        # 内置 Agent 不应被覆盖，插件 Agent 不应出现
        all_agents = pr.list_all()
        claude_agents = [a for a in all_agents if a["name"] == "claude-code"]
        # inject 返回 False 时不会添加 source="plugin" 的条目
        plugin_claudes = [a for a in claude_agents if a.get("source") == "plugin"]
        assert len(plugin_claudes) == 0

    def test_multiple_providers_injected(self, tmp_path: Path):
        reg, pr = _make_registry_with_provider(tmp_path)
        plugin = _make_agent_plugin("multi-plugin", [
            {"name": "agent-a", "command": "a-cli", "display_name": "Agent A"},
            {"name": "agent-b", "command": "b-cli", "display_name": "Agent B"},
        ])
        reg._inject_agents(plugin)

        names = [a["name"] for a in pr.list_all()]
        assert "agent-a" in names
        assert "agent-b" in names

    def test_partial_conflict_continues(self, tmp_path: Path):
        """一个 provider 冲突不影响其他 provider 注入"""
        reg, pr = _make_registry_with_provider(tmp_path)
        plugin = _make_agent_plugin("mixed-plugin", [
            {"name": "claude-code", "command": "claude", "display_name": "Conflict"},
            {"name": "new-agent", "command": "new-cli", "display_name": "New Agent"},
        ])
        reg._inject_agents(plugin)

        names = [a["name"] for a in pr.list_all()]
        assert "new-agent" in names

    def test_no_providers_is_noop(self, tmp_path: Path):
        reg, pr = _make_registry_with_provider(tmp_path)
        plugin = _make_agent_plugin("empty-plugin", [])
        reg._inject_agents(plugin)
        assert pr.list_all() == []


class TestEjectAgents:
    def test_ejects_provider_from_registry(self, tmp_path: Path):
        reg, pr = _make_registry_with_provider(tmp_path)
        plugin = _make_agent_plugin("test-plugin", [
            {"name": "my-agent", "command": "my-cli", "display_name": "My Agent"},
        ])
        reg._inject_agents(plugin)
        assert any(a["name"] == "my-agent" for a in pr.list_all())

        reg._eject_agents(plugin)
        assert not any(a["name"] == "my-agent" for a in pr.list_all())

    def test_noop_when_no_provider_registry(self, tmp_path: Path):
        reg = _make_registry(tmp_path)
        plugin = _make_agent_plugin("test-plugin", [
            {"name": "x", "command": "x", "display_name": "X"},
        ])
        # 不应抛异常
        reg._eject_agents(plugin)

    def test_eject_nonexistent_is_safe(self, tmp_path: Path):
        reg, pr = _make_registry_with_provider(tmp_path)
        plugin = _make_agent_plugin("ghost", [
            {"name": "nonexistent", "command": "nope", "display_name": "Ghost"},
        ])
        # 不应抛异常
        reg._eject_agents(plugin)

    def test_eject_multiple_providers(self, tmp_path: Path):
        reg, pr = _make_registry_with_provider(tmp_path)
        plugin = _make_agent_plugin("multi", [
            {"name": "a", "command": "a", "display_name": "A"},
            {"name": "b", "command": "b", "display_name": "B"},
        ])
        reg._inject_agents(plugin)
        reg._eject_agents(plugin)
        assert pr.list_all() == []

    def test_no_providers_is_noop(self, tmp_path: Path):
        reg, pr = _make_registry_with_provider(tmp_path)
        plugin = _make_agent_plugin("empty", [])
        reg._eject_agents(plugin)
        assert pr.list_all() == []
