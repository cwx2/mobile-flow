/// session_handler.dart — Handler for session list result messages.
library;

import '../../models/protocol.dart';
import '../websocket_service.dart';
import 'message_handler.dart';

/// Handles session list results.
///
/// Message types: sessionListResult.
/// Results are already on messageStream (added before handler dispatch)
/// for UI stream listeners. No additional processing needed.
class SessionHandler extends MessageHandler {
  @override
  void handle(WsMessage msg, WebSocketService ws) {
    // sessionListResult is consumed by SessionPicker via messageStream.
    // Already added to messageStream in _onMessage before dispatch.
  }
}
