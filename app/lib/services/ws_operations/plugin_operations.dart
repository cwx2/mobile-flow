/// plugin_operations.dart — Plugin list, enable, disable, install, config operations.
///
/// Depends on [MessageSender] interface only — no WebSocketService coupling.
library;

import '../../models/protocol.dart';
import '../../models/payloads/plugin_payloads.g.dart';
import '../ws_message_sender.dart';

/// Domain operations for plugin management.
///
/// Stateless sender — constructs and sends messages but does not
/// handle responses. Plugin results arrive via PluginHandler.
class PluginOperations {
  final MessageSender _sender;

  PluginOperations(this._sender);

  /// Request the plugin list, optionally filtered by [capability].
  void requestPluginList({String? capability}) => _sender.send(WsMessage(
      type: MessageType.pluginList,
      payload: PluginListPayload(capability: capability).toJson()));

  /// Enable a plugin by [pluginId].
  void enablePlugin(String pluginId) => _sender.send(WsMessage(
      type: MessageType.pluginEnable,
      payload: PluginEnablePayload(pluginId: pluginId).toJson()));

  /// Disable a plugin by [pluginId].
  void disablePlugin(String pluginId) => _sender.send(WsMessage(
      type: MessageType.pluginDisable,
      payload: PluginDisablePayload(pluginId: pluginId).toJson()));

  /// Install a plugin from [sourceUrl] of [sourceType].
  void installPlugin(
          {required String sourceType, required String sourceUrl}) =>
      _sender.send(WsMessage(
          type: MessageType.pluginInstall,
          payload: PluginInstallPayload(
            sourceType: sourceType,
            sourceUrl: sourceUrl,
          ).toJson()));

  /// Uninstall a plugin by [pluginId].
  void uninstallPlugin(String pluginId) => _sender.send(WsMessage(
      type: MessageType.pluginUninstall,
      payload: PluginUninstallPayload(pluginId: pluginId).toJson()));

  /// Get configuration for a plugin by [pluginId].
  void getPluginConfig(String pluginId) => _sender.send(WsMessage(
      type: MessageType.pluginConfigGet,
      payload: PluginConfigGetPayload(pluginId: pluginId).toJson()));

  /// Set configuration for a plugin.
  void setPluginConfig(String pluginId, Map<String, dynamic> config) =>
      _sender.send(WsMessage(
          type: MessageType.pluginConfigSet,
          payload: PluginConfigSetPayload(
            pluginId: pluginId,
            config: config,
          ).toJson()));
}
