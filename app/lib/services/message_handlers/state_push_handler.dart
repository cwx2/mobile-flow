/// state_push_handler.dart — Handler for state.push messages from the Agent cache layer.
library;

import '../../core/event_bus.dart';
import '../../models/protocol.dart';
import '../../models/payloads/state_payloads.g.dart';
import '../../utils/logger.dart';
import '../websocket_service.dart';
import 'message_handler.dart';

final _log = getLogger('StatePushHandler');

/// Handles state.push messages from the Agent's cache layer.
///
/// The Agent pushes fresh state after write operations complete or
/// file system changes are detected. This eliminates the need for
/// screens to poll — they subscribe to EventBus events instead.
///
/// For git state pushes, synthetic messages are injected into
/// messageStream so GitStateProvider picks them up.
class StatePushHandler extends MessageHandler {
  @override
  void handle(WsMessage msg, WebSocketService ws) {
    final p = StatePushPayload.fromJson(msg.payload);
    final key = p.key;
    final data = p.data;
    if (key.isEmpty || data == null) return;

    switch (key) {
      case 'git.status':
        // Inject as git.status.result so GitScreen's existing listener picks it up
        ws.messageController.add(WsMessage(
          type: MessageType.gitStatusResult,
          payload: data is Map<String, dynamic> ? data : {},
        ));
        ws.eventBus?.emit(AppEvents.gitStatusPush, p.toJson());
        _log.fine('[StatePush] git.status 已更新');

      case 'git.branches':
        ws.messageController.add(WsMessage(
          type: MessageType.gitBranchesResult,
          payload: data is Map<String, dynamic> ? data : {},
        ));
        ws.eventBus?.emit(AppEvents.gitBranchesPush, p.toJson());
        _log.fine('[StatePush] git.branches 已更新');

      case 'git.log':
        ws.messageController.add(WsMessage(
          type: MessageType.gitLogResult,
          payload: data is Map<String, dynamic> ? data : {},
        ));
        ws.eventBus?.emit(AppEvents.gitLogPush, p.toJson());
        _log.fine('[StatePush] git.log 已更新');

      case 'git.progress':
        ws.eventBus?.emit(AppEvents.gitProgressPush,
            data is Map<String, dynamic> ? data : {});

      default:
        _log.fine('[StatePush] 未知 key: $key');
    }
  }
}
