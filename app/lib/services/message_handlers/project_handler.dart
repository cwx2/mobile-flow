/// project_handler.dart — Handler for project current and result messages.
library;

import '../../core/event_bus.dart';
import '../../models/protocol.dart';
import '../../models/payloads/project_payloads.g.dart';
import '../websocket_service.dart';
import 'message_handler.dart';

/// Handles project status updates and result forwarding.
///
/// Message types: projectCurrent.
/// projectListResult and projectSearchResult are forwarded via
/// messageStream for UI stream listeners.
class ProjectHandler extends MessageHandler {
  @override
  void handle(WsMessage msg, WebSocketService ws) {
    switch (msg.type) {
      case MessageType.projectCurrent:
        _handleProjectCurrent(msg, ws);
    }
  }

  void _handleProjectCurrent(WsMessage msg, WebSocketService ws) {
    final p = ProjectCurrentPayload.fromJson(msg.payload);
    final newPath = p.path;
    final oldPath = ws.currentProjectPath;
    ws.currentProjectName = p.name;
    ws.currentProjectPath = newPath;
    ws.eventBus?.emit(AppEvents.projectSwitched, msg.payload);

    // Only reset CLI state on genuine project switches (user action),
    // not on initial sync after connect/reconnect. When oldPath is empty
    // (fresh start or hot restart), this is just the Agent telling us
    // the current project — the CLI is already initialized.
    if (newPath != oldPath && oldPath.isNotEmpty) {
      ws.messages.clear();
      ws.resetCliState();
    }
    if (newPath != oldPath && newPath.isNotEmpty) {
      ws.fileOps.requestFileTree(depth: 1);
      ws.gitOps.requestGitStatus();
      ws.gitOps.gitLog();
      ws.gitOps.gitBranches();
      ws.gitOps.requestGitRepos();
    }
    ws.notifyUI();
  }
}
