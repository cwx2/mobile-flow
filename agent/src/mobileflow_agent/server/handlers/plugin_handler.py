"""Plugin management handler.

Module: server/handlers/
Responsibility:
    Handle all ``plugin.*`` WebSocket messages:
    - plugin.list → list installed plugins (with optional capability filter).
    - plugin.enable / plugin.disable → toggle plugin state.
    - plugin.uninstall → remove a plugin.
    - plugin.install → install a plugin from git / npm / URL.
    - plugin.config.get / plugin.config.set → read and write plugin configuration.

Dependencies:
    PluginRegistry (accessed via ``server.plugin_registry``).
"""

from __future__ import annotations

from loguru import logger

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.payloads.plugin import (
    PluginConfigGetPayload,
    PluginConfigGetResultPayload,
    PluginConfigSetPayload,
    PluginConfigSetResultPayload,
    PluginDisablePayload,
    PluginEnablePayload,
    PluginInstallPayload,
    PluginInstallResultPayload,
    PluginListPayload,
    PluginListResultPayload,
    PluginStateChangedPayload,
    PluginUninstallPayload,
)
from mobileflow_protocol.types import MessageType

from ...utils.i18n import t
from .base import BaseHandler


class PluginHandler(BaseHandler):
    """Handles all plugin lifecycle and configuration messages over WebSocket."""

    @property
    def plugin_registry(self):
        """Shortcut to the plugin registry."""
        return self.server.plugin_registry

    async def handle_plugin_list(self, client_id, ws, msg):
        """List installed plugins, optionally filtered by capability type.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``capability`` filter.
        """
        p = msg.typed_payload(PluginListPayload)
        capability = p.capability
        logger.debug(f"plugin.list: capability={capability}")
        plugins = self.plugin_registry.list_plugins(capability)
        logger.debug(f"plugin.list: 返回 {len(plugins)} 个插件")
        await self.send(ws, Message.from_typed(
            MessageType.PLUGIN_LIST_RESULT,
            PluginListResultPayload(plugins=plugins),
        ))

    async def handle_plugin_enable(self, client_id, ws, msg):
        """Enable a plugin and broadcast the state change.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``plugin_id``.
        """
        p = msg.typed_payload(PluginEnablePayload)
        plugin_id = p.plugin_id
        logger.info(f"plugin.enable: {plugin_id}")
        result = self.plugin_registry.enable_plugin(plugin_id)
        await self.broadcast(Message.from_typed(
            MessageType.PLUGIN_STATE_CHANGED,
            PluginStateChangedPayload(**result),
        ))

    async def handle_plugin_disable(self, client_id, ws, msg):
        """Disable a plugin and broadcast the state change.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``plugin_id``.
        """
        p = msg.typed_payload(PluginDisablePayload)
        plugin_id = p.plugin_id
        logger.info(f"plugin.disable: {plugin_id}")
        result = self.plugin_registry.disable_plugin(plugin_id)
        await self.broadcast(Message.from_typed(
            MessageType.PLUGIN_STATE_CHANGED,
            PluginStateChangedPayload(**result),
        ))

    async def handle_plugin_uninstall(self, client_id, ws, msg):
        """Uninstall a plugin and broadcast the state change.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``plugin_id``.
        """
        p = msg.typed_payload(PluginUninstallPayload)
        plugin_id = p.plugin_id
        logger.info(f"plugin.uninstall: {plugin_id}")
        result = self.plugin_registry.uninstall_plugin(plugin_id)
        await self.broadcast(Message.from_typed(
            MessageType.PLUGIN_STATE_CHANGED,
            PluginStateChangedPayload(**result),
        ))

    async def handle_plugin_install(self, client_id, ws, msg):
        """Install a plugin from a given source and refresh the registry.

        Supports ``git``, ``npm``, and ``url`` source types.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``source_type`` and ``source_url``.
        """
        p = msg.typed_payload(PluginInstallPayload)
        source_type = p.source_type
        source_url = p.source_url
        logger.info(f"plugin.install: type={source_type}, url={source_url[:60]}")
        ext_dir = self.plugin_registry._ext_dir
        loader = self.plugin_registry._loader

        try:
            if source_type == "git":
                info = await loader.install_from_git(source_url, ext_dir)
            elif source_type == "npm":
                info = await loader.install_from_npm(source_url, ext_dir)
            elif source_type == "url":
                info = await loader.install_from_url(source_url, ext_dir)
            else:
                await self.send(ws, Message.from_typed(
                    MessageType.PLUGIN_INSTALL_RESULT,
                    PluginInstallResultPayload(
                        success=False,
                        plugin_id=None,
                        message=t("backend.pluginSourceUnsupported", type=source_type),
                    ),
                ))
                return

            self.plugin_registry.refresh()

            await self.send(ws, Message.from_typed(
                MessageType.PLUGIN_INSTALL_RESULT,
                PluginInstallResultPayload(
                    success=True,
                    plugin_id=info.id,
                    message=t("backend.pluginInstallSuccess", id=info.id),
                ),
            ))

        except Exception as exc:
            logger.error(f"插件安装失败: {exc}")
            await self.send(ws, Message.from_typed(
                MessageType.PLUGIN_INSTALL_RESULT,
                PluginInstallResultPayload(
                    success=False,
                    plugin_id=None,
                    message=t("backend.pluginInstallFailed", error=str(exc)),
                ),
            ))

    async def handle_plugin_config_get(self, client_id, ws, msg):
        """Retrieve the configuration for a specific plugin.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``plugin_id``.
        """
        p = msg.typed_payload(PluginConfigGetPayload)
        plugin_id = p.plugin_id
        result = self.plugin_registry.get_config(plugin_id)
        await self.send(ws, Message.from_typed(
            MessageType.PLUGIN_CONFIG_GET_RESULT,
            PluginConfigGetResultPayload(**result),
        ))

    async def handle_plugin_config_set(self, client_id, ws, msg):
        """Update the configuration for a specific plugin.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``plugin_id`` and ``config`` dict.
        """
        p = msg.typed_payload(PluginConfigSetPayload)
        plugin_id = p.plugin_id
        config = p.config
        logger.debug(f"plugin.config.set: plugin={plugin_id}")
        result = self.plugin_registry.set_config(plugin_id, config)
        await self.send(ws, Message.from_typed(
            MessageType.PLUGIN_CONFIG_SET_RESULT,
            PluginConfigSetResultPayload(**result),
        ))
