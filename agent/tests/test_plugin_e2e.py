"""
插件系统端到端测试

实际测试：创建插件目录 → 初始化 PluginRegistry → 验证发现、注册、
启用/禁用、配置管理、卸载的完整流程。
"""

from __future__ import annotations

import json
from pathlib import Path

from mobileflow_agent.plugins.loader import MANIFEST_FILE, METADATA_FILE, PluginLoader
from mobileflow_agent.plugins.registry import PluginRegistry
from mobileflow_agent.providers.registry import ProviderRegistry


def _create_plugin(ext_dir: Path, plugin_id: str, manifest: dict, metadata: dict | None = None):
    """在扩展目录中创建一个完整的插件"""
    plugin_dir = ext_dir / plugin_id
    plugin_dir.mkdir(parents=True, exist_ok=True)
    (plugin_dir / MANIFEST_FILE).write_text(
        json.dumps(manifest, ensure_ascii=False), encoding="utf-8"
    )
    if metadata:
        (plugin_dir / METADATA_FILE).write_text(
            json.dumps(metadata, ensure_ascii=False), encoding="utf-8"
        )


class TestPluginE2E:
    """端到端测试：完整的插件生命周期"""

    def test_full_lifecycle(self, tmp_path: Path):
        """测试完整流程：发现 → 注册 → 启用 → 配置 → 禁用 → 卸载"""
        ext_dir = tmp_path / "extensions"

        # 1. 创建两个测试插件
        _create_plugin(ext_dir, "agent-alpha", {
            "id": "agent-alpha",
            "enabledByDefault": True,
            "providers": [{
                "name": "alpha-cli",
                "command": "alpha",
                "args": ["acp"],
                "displayName": "Alpha Agent",
                "installHint": "npm i -g alpha-cli",
            }],
            "configSchema": {
                "type": "object",
                "properties": {
                    "model": {"type": "string", "enum": ["fast", "smart"]},
                },
            },
            "uiHints": {
                "model": {"label": "模型选择", "help": "选择运行模型"},
            },
        }, {"name": "alpha-plugin", "version": "1.0.0", "description": "Alpha 测试插件"})

        _create_plugin(ext_dir, "agent-beta", {
            "id": "agent-beta",
            "enabledByDefault": False,
            "providers": [{
                "name": "beta-cli",
                "command": "beta",
                "displayName": "Beta Agent",
            }],
        }, {"name": "beta-plugin", "version": "2.0.0"})

        # 2. 初始化 PluginRegistry（带 ProviderRegistry）
        provider_reg = ProviderRegistry()
        registry = PluginRegistry(ext_dir=ext_dir, provider_registry=provider_reg)
        registry.initialize()

        # 3. 验证发现
        all_plugins = registry.list_plugins()
        assert len(all_plugins) == 2
        ids = {p["id"] for p in all_plugins}
        assert ids == {"agent-alpha", "agent-beta"}

        # 4. 验证默认启用状态
        alpha = next(p for p in all_plugins if p["id"] == "agent-alpha")
        beta = next(p for p in all_plugins if p["id"] == "agent-beta")
        assert alpha["enabled"] is True
        assert alpha["status"] == "active"
        assert beta["enabled"] is False
        assert beta["status"] == "disabled"

        # 5. 验证元数据合并
        assert alpha["name"] == "alpha-plugin"
        assert alpha["version"] == "1.0.0"
        assert alpha["description"] == "Alpha 测试插件"

        # 6. 验证能力过滤
        agent_plugins = registry.list_plugins(capability="agent")
        assert len(agent_plugins) == 2  # 两个都有 providers

        # 7. 验证 Agent 注入到 ProviderRegistry
        all_agents = provider_reg.list_all()
        agent_names = [a["name"] for a in all_agents]
        assert "alpha-cli" in agent_names  # alpha 启用了
        # beta 禁用了，不应该注入
        assert "beta-cli" not in agent_names

        # 8. 验证 source 字段
        alpha_agent = next(a for a in all_agents if a["name"] == "alpha-cli")
        assert alpha_agent["source"] == "plugin"

        # 9. 测试配置管理
        # 获取配置（初始为空）
        config_result = registry.get_config("agent-alpha")
        assert config_result["config"] == {}
        assert config_result["config_schema"] is not None
        assert "model" in config_result["ui_hints"]

        # 设置合法配置
        set_result = registry.set_config("agent-alpha", {"model": "fast"})
        assert set_result["success"] is True
        assert set_result["errors"] == []

        # 验证配置持久化
        config_result = registry.get_config("agent-alpha")
        assert config_result["config"] == {"model": "fast"}

        # 设置非法配置
        set_result = registry.set_config("agent-alpha", {"model": "invalid"})
        assert set_result["success"] is False
        assert len(set_result["errors"]) > 0
        assert "model" in set_result["errors"][0]

        # 10. 测试启用 beta
        enable_result = registry.enable_plugin("agent-beta")
        assert enable_result["success"] is True
        assert enable_result["enabled"] is True

        # beta 的 Agent 现在应该出现在 ProviderRegistry
        all_agents = provider_reg.list_all()
        agent_names = [a["name"] for a in all_agents]
        assert "beta-cli" in agent_names

        # 11. 测试禁用 alpha
        disable_result = registry.disable_plugin("agent-alpha")
        assert disable_result["success"] is True
        assert disable_result["enabled"] is False

        # alpha 的 Agent 应该从 ProviderRegistry 移除
        all_agents = provider_reg.list_all()
        agent_names = [a["name"] for a in all_agents]
        assert "alpha-cli" not in agent_names

        # 12. 测试重新启用 alpha
        enable_result = registry.enable_plugin("agent-alpha")
        assert enable_result["success"] is True
        all_agents = provider_reg.list_all()
        agent_names = [a["name"] for a in all_agents]
        assert "alpha-cli" in agent_names

        # 13. 测试卸载 beta
        uninstall_result = registry.uninstall_plugin("agent-beta")
        assert uninstall_result["success"] is True
        assert not (ext_dir / "agent-beta").exists()

        # beta 应该从注册表和 ProviderRegistry 中消失
        all_plugins = registry.list_plugins()
        assert len(all_plugins) == 1
        assert all_plugins[0]["id"] == "agent-alpha"

        all_agents = provider_reg.list_all()
        agent_names = [a["name"] for a in all_agents]
        assert "beta-cli" not in agent_names

        # 14. 测试状态持久化
        state_path = ext_dir.parent / "plugin_state.json"
        assert state_path.exists()
        state = json.loads(state_path.read_text(encoding="utf-8"))
        assert "agent-alpha" in state
        assert state["agent-alpha"]["enabled"] is True

        print("✅ 端到端测试全部通过！")

    def test_refresh_detects_new_plugin(self, tmp_path: Path):
        """测试刷新能发现新添加的插件"""
        ext_dir = tmp_path / "extensions"

        # 初始只有一个插件
        _create_plugin(ext_dir, "original", {"id": "original"})

        registry = PluginRegistry(ext_dir=ext_dir)
        registry.initialize()
        assert len(registry.list_plugins()) == 1

        # 添加新插件
        _create_plugin(ext_dir, "new-one", {"id": "new-one"})

        # 刷新
        registry.refresh()
        all_plugins = registry.list_plugins()
        assert len(all_plugins) == 2
        ids = {p["id"] for p in all_plugins}
        assert ids == {"original", "new-one"}

        print("✅ 刷新检测新插件测试通过！")

    def test_duplicate_id_rejection(self, tmp_path: Path):
        """测试重复 ID 被拒绝"""
        ext_dir = tmp_path / "extensions"

        # 两个目录声明相同 ID
        _create_plugin(ext_dir, "dir-a", {"id": "same-id"})
        _create_plugin(ext_dir, "dir-b", {"id": "same-id"})

        registry = PluginRegistry(ext_dir=ext_dir)
        registry.initialize()

        # 只应该注册一个
        all_plugins = registry.list_plugins()
        assert len(all_plugins) == 1
        assert all_plugins[0]["id"] == "same-id"

        print("✅ 重复 ID 拒绝测试通过！")

    def test_builtin_agent_conflict(self, tmp_path: Path):
        """测试插件 Agent 与内置 Agent 冲突时内置优先"""
        ext_dir = tmp_path / "extensions"

        # 创建一个与内置 claude-code 冲突的插件
        _create_plugin(ext_dir, "fake-claude", {
            "id": "fake-claude",
            "providers": [{
                "name": "claude-code",  # 与内置冲突！
                "command": "fake-claude",
                "displayName": "Fake Claude",
            }],
        })

        provider_reg = ProviderRegistry()
        registry = PluginRegistry(ext_dir=ext_dir, provider_registry=provider_reg)
        registry.initialize()

        # 插件应该被注册，但 Agent 注入应该失败（内置优先）
        all_plugins = registry.list_plugins()
        assert len(all_plugins) == 1

        # ProviderRegistry 中不应该有 fake-claude 的 plugin source agent
        all_agents = provider_reg.list_all()
        plugin_agents = [a for a in all_agents if a.get("source") == "plugin"]
        assert len(plugin_agents) == 0

        print("✅ 内置 Agent 优先测试通过！")

    def test_error_handling_bad_manifest(self, tmp_path: Path):
        """测试损坏清单的错误处理"""
        ext_dir = tmp_path / "extensions"

        # 一个好的，一个坏的
        _create_plugin(ext_dir, "good", {"id": "good"})
        bad_dir = ext_dir / "bad"
        bad_dir.mkdir(parents=True)
        (bad_dir / MANIFEST_FILE).write_text("NOT VALID JSON")

        registry = PluginRegistry(ext_dir=ext_dir)
        registry.initialize()

        # 好的应该正常加载
        all_plugins = registry.list_plugins()
        assert len(all_plugins) == 1
        assert all_plugins[0]["id"] == "good"

        print("✅ 错误处理测试通过！")
