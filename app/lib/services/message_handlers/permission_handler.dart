/// permission_handler.dart — Handler for permission request messages.
library;

import '../../core/event_bus.dart';
import '../../models/protocol.dart';
import '../websocket_service.dart';
import 'message_handler.dart';

/// Handles incoming permission requests from the Agent.
///
/// Message types: permissionRequest.
class PermissionHandler extends MessageHandler {
  @override
  void handle(WsMessage msg, WebSocketService ws) {
    ws.pendingPermission = msg.payload;
    ws.permissionController.add(msg.payload);
    ws.eventBus?.emit(AppEvents.permissionRequest, msg.payload);
    ws.notifyUI();
  }
}
