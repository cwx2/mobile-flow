"""Plugin domain payload models for the MobileFlow WebSocket protocol.

Defines typed Pydantic models for the twelve plugin-related message types:
  - plugin.list              (PLUGIN_LIST)              — list installed plugins
  - plugin.list.result       (PLUGIN_LIST_RESULT)       — plugin list
  - plugin.enable            (PLUGIN_ENABLE)            — enable a plugin
  - plugin.disable           (PLUGIN_DISABLE)           — disable a plugin
  - plugin.uninstall         (PLUGIN_UNINSTALL)         — uninstall a plugin
  - plugin.state_changed     (PLUGIN_STATE_CHANGED)     — plugin state change
  - plugin.install           (PLUGIN_INSTALL)           — install a plugin
  - plugin.install.result    (PLUGIN_INSTALL_RESULT)    — install outcome
  - plugin.config.get        (PLUGIN_CONFIG_GET)        — get plugin config
  - plugin.config.get.result (PLUGIN_CONFIG_GET_RESULT) — plugin config
  - plugin.config.set        (PLUGIN_CONFIG_SET)        — set plugin config
  - plugin.config.set.result (PLUGIN_CONFIG_SET_RESULT) — set result

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Any, Optional

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


class PluginListPayload(PayloadBase):
    """Payload for ``plugin.list`` — list installed plugins.

    Sent by the App to request the list of installed plugins,
    optionally filtered by capability type.

    Attributes:
        capability: Optional capability filter (e.g. "provider").
    """

    capability: Optional[str] = None


class PluginListResultPayload(PayloadBase):
    """Payload for ``plugin.list.result`` — plugin list.

    Sent by the Agent with the list of installed plugins.

    Attributes:
        plugins: List of plugin info dicts.
    """

    plugins: list[dict[str, Any]] = []


class PluginEnablePayload(PayloadBase):
    """Payload for ``plugin.enable`` — enable a plugin.

    Sent by the App to activate a disabled plugin.

    Attributes:
        plugin_id: Identifier of the plugin to enable.
    """

    plugin_id: str


class PluginDisablePayload(PayloadBase):
    """Payload for ``plugin.disable`` — disable a plugin.

    Sent by the App to deactivate an enabled plugin.

    Attributes:
        plugin_id: Identifier of the plugin to disable.
    """

    plugin_id: str


class PluginUninstallPayload(PayloadBase):
    """Payload for ``plugin.uninstall`` — uninstall a plugin.

    Sent by the App to remove a plugin from the system.

    Attributes:
        plugin_id: Identifier of the plugin to uninstall.
    """

    plugin_id: str


class PluginStateChangedPayload(PayloadBase):
    """Payload for ``plugin.state_changed`` — plugin state change.

    Sent by the Agent when a plugin's state changes (enabled,
    disabled, error, etc.).

    Attributes:
        plugin_id: Identifier of the affected plugin.
        state: New state string (e.g. "enabled", "disabled", "error").
        error: Error description if the state change failed.
    """

    plugin_id: str
    state: str
    error: Optional[str] = None


class PluginInstallPayload(PayloadBase):
    """Payload for ``plugin.install`` — install a plugin.

    Sent by the App to install a plugin from a remote source.

    Attributes:
        source_type: Installation source type ("git", "npm", "url").
        source_url: URL or package identifier for the plugin source.
    """

    source_type: str
    source_url: str


class PluginInstallResultPayload(PayloadBase):
    """Payload for ``plugin.install.result`` — install outcome.

    Sent by the Agent after a plugin installation attempt.

    Attributes:
        success: Whether the installation succeeded.
        message: Human-readable result or error message.
        plugin_id: Identifier of the installed plugin (on success).
    """

    success: bool
    message: str = ""
    plugin_id: Optional[str] = None


class PluginConfigGetPayload(PayloadBase):
    """Payload for ``plugin.config.get`` — get plugin configuration.

    Sent by the App to retrieve a plugin's current configuration.

    Attributes:
        plugin_id: Identifier of the plugin.
    """

    plugin_id: str


class PluginConfigGetResultPayload(PayloadBase):
    """Payload for ``plugin.config.get.result`` — plugin configuration.

    Sent by the Agent with the plugin's current configuration.

    Attributes:
        plugin_id: Identifier of the plugin.
        config: Configuration key-value pairs.
    """

    plugin_id: str
    config: dict[str, Any] = {}


class PluginConfigSetPayload(PayloadBase):
    """Payload for ``plugin.config.set`` — set plugin configuration.

    Sent by the App to update a plugin's configuration.

    Attributes:
        plugin_id: Identifier of the plugin.
        config: New configuration key-value pairs.
    """

    plugin_id: str
    config: dict[str, Any]


class PluginConfigSetResultPayload(PayloadBase):
    """Payload for ``plugin.config.set.result`` — set result.

    Sent by the Agent after a plugin configuration update attempt.

    Attributes:
        success: Whether the update succeeded.
        error: Error description if the update failed.
    """

    success: bool
    error: Optional[str] = None


# ── Registry wiring ──

register_payload(MessageType.PLUGIN_LIST, PluginListPayload)
register_payload(MessageType.PLUGIN_LIST_RESULT, PluginListResultPayload)
register_payload(MessageType.PLUGIN_ENABLE, PluginEnablePayload)
register_payload(MessageType.PLUGIN_DISABLE, PluginDisablePayload)
register_payload(MessageType.PLUGIN_UNINSTALL, PluginUninstallPayload)
register_payload(MessageType.PLUGIN_STATE_CHANGED, PluginStateChangedPayload)
register_payload(MessageType.PLUGIN_INSTALL, PluginInstallPayload)
register_payload(MessageType.PLUGIN_INSTALL_RESULT, PluginInstallResultPayload)
register_payload(MessageType.PLUGIN_CONFIG_GET, PluginConfigGetPayload)
register_payload(MessageType.PLUGIN_CONFIG_GET_RESULT, PluginConfigGetResultPayload)
register_payload(MessageType.PLUGIN_CONFIG_SET, PluginConfigSetPayload)
register_payload(MessageType.PLUGIN_CONFIG_SET_RESULT, PluginConfigSetResultPayload)
