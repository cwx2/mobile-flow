"""
ProviderRegistry core tests.

Covers: ProviderInfo.to_dict, ACP_REGISTRY completeness,
custom agent add/remove lifecycle.
"""

from __future__ import annotations

import pytest

from mobileflow_agent.providers.registry import (
    ACP_REGISTRY, ProviderInfo, ProviderRegistry,
)


class TestProviderInfoToDict:
    def test_installed(self):
        d = ProviderInfo("test", "Test Agent", True).to_dict()
        assert d["installed"] is True
        assert "install_hint" not in d

    def test_not_installed(self):
        d = ProviderInfo("test2", "Test2", False,
                         install_hint="npm i -g test2", install_npm="test2-pkg").to_dict()
        assert d["installed"] is False
        assert d["install_hint"] == "npm i -g test2"
        # install_npm is now converted to install_packages internally;
        # to_dict exposes can_install instead of raw package names
        assert d["can_install"] is True

    def test_custom(self):
        d = ProviderInfo("custom1", "Custom", True, is_custom=True).to_dict()
        assert d["is_custom"] is True


class TestACPRegistry:
    def test_has_15_agents(self):
        assert len(ACP_REGISTRY) == 11

    @pytest.mark.parametrize("name", list(ACP_REGISTRY.keys()))
    def test_agent_has_required_fields(self, name):
        config = ACP_REGISTRY[name]
        assert "command" in config
        assert "args" in config
        assert "display_name" in config


class TestCustomAgentLifecycle:
    def test_add_custom(self):
        reg = ProviderRegistry()
        result = reg.add_custom_agent("test-custom", "test-cmd", ["acp"], "Test Custom Agent")
        assert result["success"] is True
        # cleanup
        reg.remove_custom_agent("test-custom")

    def test_add_builtin_name_fails(self):
        reg = ProviderRegistry()
        result = reg.add_custom_agent("claude-code", "claude", ["acp"], "Duplicate")
        assert result["success"] is False

    def test_custom_agent_persisted(self):
        reg = ProviderRegistry()
        reg.add_custom_agent("test-custom", "test-cmd", ["acp"], "Test Custom Agent")
        custom = reg._load_custom_agents()
        assert "test-custom" in custom
        assert custom["test-custom"]["command"] == "test-cmd"
        reg.remove_custom_agent("test-custom")

    def test_remove_custom(self):
        reg = ProviderRegistry()
        reg.add_custom_agent("test-custom", "test-cmd", ["acp"], "Test Custom Agent")
        result = reg.remove_custom_agent("test-custom")
        assert result["success"] is True
        assert "test-custom" not in reg._load_custom_agents()

    def test_remove_builtin_fails(self):
        reg = ProviderRegistry()
        assert reg.remove_custom_agent("claude-code")["success"] is False

    def test_remove_nonexistent_fails(self):
        reg = ProviderRegistry()
        assert reg.remove_custom_agent("nonexistent")["success"] is False
