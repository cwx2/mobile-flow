/// file_handler.dart — Handler for file tree, file changed, and file search messages.
library;

import '../../core/event_bus.dart';
import '../../models/protocol.dart';
import '../../models/payloads/file_payloads.g.dart';
import '../../utils/logger.dart';
import '../websocket_service.dart';
import 'message_handler.dart';

final _log = getLogger('FileHandler');

/// Handles file tree results, file change notifications, and search results.
///
/// Message types: fileTreeResult, fileChanged.
/// fileSearchResult and fileReadResult are forwarded via messageStream
/// (added before handler dispatch) for UI stream listeners.
class FileHandler extends MessageHandler {
  @override
  void handle(WsMessage msg, WebSocketService ws) {
    switch (msg.type) {
      case MessageType.fileTreeResult:
        _handleFileTreeResult(msg, ws);
      case MessageType.fileChanged:
        _handleFileChanged(msg, ws);
    }
  }

  void _handleFileTreeResult(WsMessage msg, WebSocketService ws) {
    final p = FileTreeResultPayload.fromJson(msg.payload);
    ws.cachedFileTreeData = _flattenFileTree(p.data);
    ws.fileTreeCacheTime = DateTime.now();
    _log.fine('文件树缓存更新: ${ws.cachedFileTree?.length ?? 0} entries');
  }

  void _handleFileChanged(WsMessage msg, WebSocketService ws) {
    // Invalidate file tree cache on any file change so the next
    // autocomplete open fetches a fresh tree.
    ws.cachedFileTreeData = null;

    final p = FileChangedPayload.fromJson(msg.payload);
    final change = p.change.isEmpty ? 'modified' : p.change;
    final event = {
      'created': AppEvents.fileCreated,
      'deleted': AppEvents.fileDeleted,
      'modified': AppEvents.fileModified,
    }[change];
    if (event != null) ws.eventBus?.emit(event, msg.payload);
  }

  /// Flatten a nested file tree into a flat list for autocomplete.
  ///
  /// Produces entries with shape:
  /// `{'name': String, 'path': String, 'type': 'file'|'dir'}`.
  static List<Map<String, dynamic>> _flattenFileTree(
      List<dynamic> nodes, [String prefix = '']) {
    final result = <Map<String, dynamic>>[];
    for (final node in nodes) {
      if (node is! Map<String, dynamic>) continue;
      final name = node['name'] as String? ?? '';
      final type = node['type'] as String? ?? '';
      final path = prefix.isEmpty ? name : '$prefix/$name';

      result.add({'name': name, 'path': path, 'type': type});

      if (type == 'dir') {
        final children = node['children'] as List? ?? [];
        result.addAll(_flattenFileTree(children, path));
      }
    }
    return result;
  }
}
