"""Plugin registry: manages state and configuration for all discovered plugins.

Module: plugins/
Responsibility:
    Maintain the plugin registry (``_plugins``), manage enable/disable state,
    persist ``plugin_state.json``, provide a unified query interface, and
    integrate with ProviderRegistry (Agent injection / removal).

Called by:
    - server/handlers/plugin_handler.py (WebSocket message handling).
    - server/websocket.py (initialisation on startup).
"""

from __future__ import annotations

import shutil
from pathlib import Path

import jsonschema
from loguru import logger

from ..utils.i18n import t
from ..utils.json_file import load_json_file, save_json_file
from .loader import PluginLoader
from .manifest import PluginInfo


class PluginRegistry:
    """Central registry managing all discovered plugins and their runtime state.

    Attributes:
        _ext_dir: Path to the extensions directory.
        _provider_registry: Optional ProviderRegistry for Agent injection.
        _plugins: Mapping of plugin_id to PluginInfo.
    """

    def __init__(self, ext_dir: Path, provider_registry=None):
        self._ext_dir = ext_dir
        self._provider_registry = provider_registry
        self._loader = PluginLoader()
        self._plugins: dict[str, PluginInfo] = {}
        # plugin_state.json lives in the parent of ext_dir (~/.mobileflow/)
        self._state_path = ext_dir.parent / "plugin_state.json"

    def initialize(self):
        """Scan the extensions directory, load persisted state, and register enabled plugins."""
        logger.info("初始化插件注册表...")
        discovered = self._loader.scan_extensions(self._ext_dir)
        state = self._load_state()

        for plugin in discovered:
            if plugin.id in self._plugins:
                logger.warning(
                    f"插件 {plugin.id} 与已加载的插件冲突，已跳过"
                )
                continue

            # Determine enabled state: persisted state takes priority over manifest default
            if plugin.id in state:
                plugin.enabled = state[plugin.id].get(
                    "enabled", plugin.manifest.enabled_by_default
                )
            else:
                plugin.enabled = plugin.manifest.enabled_by_default

            if plugin.enabled:
                plugin.status = "active"
                self._inject_agents(plugin)
            else:
                plugin.status = "disabled"

            self._plugins[plugin.id] = plugin

        self._save_state()
        logger.info(f"插件注册表初始化完成: {len(self._plugins)} 个插件")

    def refresh(self):
        """Re-scan the extensions directory and update the registry.

        Preserves user state (enabled/disabled) for existing plugins,
        adds newly discovered plugins, and removes deleted ones.
        """
        old_state = {
            pid: {"enabled": p.enabled}
            for pid, p in self._plugins.items()
        }

        # Eject all old plugin Agents
        for plugin in self._plugins.values():
            if plugin.enabled:
                self._eject_agents(plugin)

        self._plugins.clear()

        discovered = self._loader.scan_extensions(self._ext_dir)
        state = self._load_state()
        # Merge persisted state with in-memory state (in-memory takes priority)
        merged_state = {**state, **old_state}

        for plugin in discovered:
            if plugin.id in self._plugins:
                logger.warning(
                    f"插件 {plugin.id} 与已加载的插件冲突，已跳过"
                )
                continue

            if plugin.id in merged_state:
                plugin.enabled = merged_state[plugin.id].get(
                    "enabled", plugin.manifest.enabled_by_default
                )
            else:
                plugin.enabled = plugin.manifest.enabled_by_default

            if plugin.enabled:
                plugin.status = "active"
                self._inject_agents(plugin)
            else:
                plugin.status = "disabled"

            self._plugins[plugin.id] = plugin

        self._save_state()

    def list_plugins(self, capability: str | None = None) -> list[dict]:
        """List plugins, optionally filtered by capability type.

        When ``capability`` is ``"agent"``, only plugins with providers are returned.

        Args:
            capability: Optional capability filter string.

        Returns:
            List of serialisable plugin dicts.
        """
        result: list[dict] = []

        for plugin in self._plugins.values():
            caps = self._get_capabilities(plugin)
            if capability is not None and capability not in caps:
                continue
            result.append(self._plugin_to_dict(plugin, caps))

        return result

    def enable_plugin(self, plugin_id: str) -> dict:
        """Enable a plugin and inject its Agents.

        Args:
            plugin_id: Plugin identifier.

        Returns:
            Operation result dict.
        """
        plugin = self._plugins.get(plugin_id)
        if plugin is None:
            return {
                "success": False,
                "message": t("backend.pluginNotFound", id=plugin_id),
            }

        plugin.enabled = True
        plugin.status = "active"
        self._inject_agents(plugin)
        self._save_state()

        return {
            "success": True,
            "message": t("backend.pluginEnabled", id=plugin_id),
            "plugin_id": plugin_id,
            "status": plugin.status,
            "enabled": plugin.enabled,
        }

    def disable_plugin(self, plugin_id: str) -> dict:
        """Disable a plugin while preserving its files and configuration.

        Args:
            plugin_id: Plugin identifier.

        Returns:
            Operation result dict.
        """
        plugin = self._plugins.get(plugin_id)
        if plugin is None:
            return {
                "success": False,
                "message": t("backend.pluginNotFound", id=plugin_id),
            }

        self._eject_agents(plugin)
        plugin.enabled = False
        plugin.status = "disabled"
        self._save_state()

        return {
            "success": True,
            "message": t("backend.pluginDisabled", id=plugin_id),
            "plugin_id": plugin_id,
            "status": plugin.status,
            "enabled": plugin.enabled,
        }

    def uninstall_plugin(self, plugin_id: str) -> dict:
        """Uninstall a plugin: eject Agents, delete directory, remove from registry.

        Args:
            plugin_id: Plugin identifier.

        Returns:
            Operation result dict.
        """
        plugin = self._plugins.get(plugin_id)
        if plugin is None:
            return {
                "success": False,
                "message": t("backend.pluginNotFound", id=plugin_id),
            }

        # Eject Agents first
        if plugin.enabled:
            self._eject_agents(plugin)

        # Delete the plugin directory
        plugin_dir = plugin.directory
        try:
            if plugin_dir.exists():
                shutil.rmtree(plugin_dir)
        except Exception as exc:
            logger.error(f"删除插件目录 {plugin_dir} 失败：{exc}")
            return {
                "success": False,
                "message": t("backend.pluginDirDeleteFailed", path=str(plugin_dir)),
            }

        del self._plugins[plugin_id]
        self._save_state()
        logger.info(f"插件已卸载: {plugin_id}")

        return {
            "success": True,
            "message": t("backend.pluginUninstalled", id=plugin_id),
            "plugin_id": plugin_id,
        }

    # ── Configuration management ──

    def get_config(self, plugin_id: str) -> dict:
        """Get plugin configuration including schema and UI hints for App rendering.

        Args:
            plugin_id: Plugin identifier.

        Returns:
            Dict with config, config_schema, ui_hints, and config_contracts.
        """
        plugin = self._plugins.get(plugin_id)
        if plugin is None:
            return {
                "plugin_id": plugin_id,
                "config": {},
                "config_schema": None,
                "ui_hints": {},
                "config_contracts": None,
                "error": t("backend.pluginNotFound", id=plugin_id),
            }

        config = self._load_config(plugin_id)
        manifest = plugin.manifest

        return {
            "plugin_id": plugin_id,
            "config": config,
            "config_schema": manifest.config_schema,
            "ui_hints": {
                k: v.model_dump(by_alias=True)
                for k, v in manifest.ui_hints.items()
            },
            "config_contracts": (
                manifest.config_contracts.model_dump(by_alias=True)
                if manifest.config_contracts
                else None
            ),
        }

    def set_config(self, plugin_id: str, config: dict) -> dict:
        """Validate and save plugin configuration.

        Args:
            plugin_id: Plugin identifier.
            config: Configuration dict to validate and persist.

        Returns:
            Operation result dict with ``success``, ``message``, and ``errors``.
        """
        plugin = self._plugins.get(plugin_id)
        if plugin is None:
            return {
                "success": False,
                "message": t("backend.pluginNotFound", id=plugin_id),
                "errors": [],
            }

        schema = plugin.manifest.config_schema

        # No configSchema: only accept empty config
        if schema is None:
            if config:
                return {
                    "success": False,
                    "message": t("backend.pluginNoConfig"),
                    "errors": [t("backend.pluginNoConfigSchema")],
                }
            self._save_config(plugin_id, config)
            return {
                "success": True,
                "message": t("backend.configSaved"),
                "errors": [],
            }

        # Validate against JSON Schema
        errors = self._validate_config(schema, config)
        if errors:
            return {
                "success": False,
                "message": t("backend.configValidationFailed"),
                "errors": errors,
            }

        self._save_config(plugin_id, config)
        return {
            "success": True,
            "message": t("backend.configSaved"),
            "errors": [],
        }

    def _validate_config(self, schema: dict, config: dict) -> list[str]:
        """Validate config against a JSON Schema, returning localised error messages.

        Args:
            schema: JSON Schema dict.
            config: Configuration dict to validate.

        Returns:
            List of error message strings (empty if valid).
        """
        errors: list[str] = []
        try:
            validator = jsonschema.Draft7Validator(schema)
            for error in sorted(
                validator.iter_errors(config), key=lambda e: list(e.path)
            ):
                path = ".".join(str(p) for p in error.absolute_path)
                if path:
                    errors.append(t("backend.configFieldInvalid", path=path, error=error.message))
                else:
                    errors.append(t("backend.configInvalid", error=error.message))
        except jsonschema.SchemaError as exc:
            logger.error(f"插件 configSchema 本身有误：{exc}")
            errors.append(t("backend.configSchemaError"))
        return errors

    # ── Agent injection / removal ──

    def _inject_agents(self, plugin: PluginInfo):
        """Inject the plugin's Agent providers into the ProviderRegistry.

        Args:
            plugin: Plugin whose providers should be registered.
        """
        if self._provider_registry is None:
            return

        for provider in plugin.manifest.providers:
            config = {
                "command": provider.command,
                "args": list(provider.args),
                "display_name": provider.display_name,
                "terminal_cmd": provider.terminal_cmd,
                "install_hint": provider.install_hint,
                "install_npm": provider.install_npm,
            }
            ok = self._provider_registry.inject_plugin_agent(
                provider.name, config
            )
            if not ok:
                logger.warning(
                    f"插件 {plugin.id} 的 Agent '{provider.name}' "
                    f"注入失败（名称冲突），已跳过"
                )

    def _eject_agents(self, plugin: PluginInfo):
        """Remove the plugin's Agent providers from the ProviderRegistry.

        Args:
            plugin: Plugin whose providers should be unregistered.
        """
        if self._provider_registry is None:
            return

        for provider in plugin.manifest.providers:
            self._provider_registry.eject_plugin_agent(provider.name)

    # ── State persistence ──

    @property
    def _config_dir(self) -> Path:
        """Plugin configuration directory (auto-created if missing)."""
        d = self._ext_dir.parent / "plugin_configs"
        d.mkdir(parents=True, exist_ok=True)
        return d

    def _load_config(self, plugin_id: str) -> dict:
        """Load a plugin's configuration file.

        Returns an empty dict if the file is missing or corrupted.

        Args:
            plugin_id: Plugin identifier.

        Returns:
            Configuration dict.
        """
        try:
            path = self._config_dir / f"{plugin_id}.json"
            data = load_json_file(path, default={})
            if not isinstance(data, dict):
                return {}
            return data
        except Exception as exc:
            logger.warning(f"加载插件 {plugin_id} 配置失败：{exc}")
            return {}

    def _save_config(self, plugin_id: str, config: dict):
        """Persist a plugin's configuration to its JSON file.

        Args:
            plugin_id: Plugin identifier.
            config: Configuration dict to save.
        """
        path = self._config_dir / f"{plugin_id}.json"
        if not save_json_file(path, config):
            logger.error(f"保存插件 {plugin_id} 配置失败")

    def _load_state(self) -> dict:
        """Load ``plugin_state.json``.

        Returns an empty dict if the file is missing or corrupted.

        Returns:
            State dict mapping plugin_id to ``{enabled, status}``.
        """
        data = load_json_file(self._state_path, default={})
        if not isinstance(data, dict):
            return {}
        return data

    def _save_state(self):
        """Persist the enabled/disabled state of all plugins to ``plugin_state.json``."""
        state: dict[str, dict] = {}
        for pid, plugin in self._plugins.items():
            state[pid] = {
                "enabled": plugin.enabled,
                "status": plugin.status,
            }
        if not save_json_file(self._state_path, state):
            logger.error("保存插件状态文件失败")

    # ── Internal helpers ──

    @staticmethod
    def _get_capabilities(plugin: PluginInfo) -> list[str]:
        """Infer capability types from the plugin manifest.

        Args:
            plugin: Plugin to inspect.

        Returns:
            List of capability strings (e.g. ``["agent"]``).
        """
        caps: list[str] = []
        if plugin.manifest.providers:
            caps.append("agent")
        return caps

    @staticmethod
    def _plugin_to_dict(plugin: PluginInfo, caps: list[str]) -> dict:
        """Serialise a PluginInfo to a JSON-compatible dict for the App.

        Args:
            plugin: Plugin to serialise.
            caps: Pre-computed capability list.

        Returns:
            Serialisable dict.
        """
        meta = plugin.metadata
        return {
            "id": plugin.id,
            "name": meta.name if meta else "",
            "version": meta.version if meta else "",
            "description": meta.description if meta else "",
            "author": meta.author if meta else "",
            "capabilities": caps,
            "enabled": plugin.enabled,
            "status": plugin.status,
            "providers": [
                p.model_dump(by_alias=True) for p in plugin.manifest.providers
            ],
            "config_schema": plugin.manifest.config_schema,
            "ui_hints": {
                k: v.model_dump(by_alias=True)
                for k, v in plugin.manifest.ui_hints.items()
            },
            "source": "plugin",
            "error": plugin.error,
        }
