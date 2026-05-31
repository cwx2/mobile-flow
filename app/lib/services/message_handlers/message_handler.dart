/// message_handler.dart — Abstract base class for WebSocket message handlers.
library;

import '../../models/protocol.dart';
import '../websocket_service.dart';

/// Contract for handling incoming WebSocket messages.
///
/// Each handler processes one or more related message types,
/// updating state on [WebSocketService] and emitting events
/// via [AppEventBus] as needed.
abstract class MessageHandler {
  /// Process [msg] and update state on [ws].
  void handle(WsMessage msg, WebSocketService ws);
}
