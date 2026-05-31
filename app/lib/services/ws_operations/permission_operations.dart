/// permission_operations.dart — Permission response operations.
///
/// Holds a [WebSocketService] reference because [respondPermission]
/// needs to clear the pendingPermission state before sending.
library;

import '../../models/protocol.dart';
import '../../models/payloads/permission_payloads.g.dart';
import '../websocket_service.dart';

/// Domain operations for permission management.
///
/// [respondPermission] clears pendingPermission state on
/// WebSocketService before sending the response message.
class PermissionOperations {
  final WebSocketService _ws;

  PermissionOperations(this._ws);

  /// Respond to a permission request.
  ///
  /// [optionId] can be 'allow_once', 'allow_session', etc.
  void respondPermission(String requestId, bool approved,
      {String optionId = 'allow_once'}) {
    _ws.pendingPermission = null;
    _ws.notifyUI();
    _ws.send(WsMessage(
        type: MessageType.permissionResponse,
        payload: PermissionResponsePayload(
          requestId: requestId,
          approved: approved,
          optionId: optionId,
        ).toJson()));
  }
}
