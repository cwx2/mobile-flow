/// plugin_handler.dart — Handler for plugin list and config result messages.
library;

import '../../models/protocol.dart';
import '../websocket_service.dart';
import 'message_handler.dart';

/// Handles plugin list and config results.
///
/// Message types: pluginListResult, pluginConfigResult.
/// Results are already on messageStream (added before handler dispatch)
/// for UI stream listeners. No additional processing needed.
class PluginHandler extends MessageHandler {
  @override
  void handle(WsMessage msg, WebSocketService ws) {
    // Plugin results are consumed by PluginScreen via messageStream.
    // Already added to messageStream in _onMessage before dispatch.
  }
}
