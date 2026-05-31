/// git_handler.dart — Handler for git result messages.
library;

import '../../models/protocol.dart';
import '../websocket_service.dart';
import 'message_handler.dart';

/// Handles git result messages by forwarding to messageStream.
///
/// Git messages are consumed by GitStateProvider and UI stream listeners
/// via messageStream. The actual state management lives in
/// GitStateProvider which subscribes to messageStream. This handler
/// exists for consistency and future extensibility — currently a no-op
/// because messages are already added to messageStream before handler
/// dispatch (Requirement 15.2).
class GitHandler extends MessageHandler {
  @override
  void handle(WsMessage msg, WebSocketService ws) {
    // Git result messages are already on messageStream (added in
    // _onMessage before _routeMessage). GitStateProvider and UI
    // stream listeners consume them directly. No additional
    // processing needed here.
  }
}
