/// file_operations.dart — File tree, read, search, CRUD, write, and diff operations.
///
/// Depends on [MessageSender] interface only — no WebSocketService coupling.
/// All methods construct a [WsMessage] with the correct type and payload,
/// then call [MessageSender.send] exactly once.
library;

import '../../models/protocol.dart';
import '../../models/payloads/diff_payloads.g.dart';
import '../../models/payloads/file_payloads.g.dart';
import '../ws_message_sender.dart';

/// Domain operations for file system interactions.
///
/// Stateless sender — constructs and sends messages but does not
/// handle responses. File results arrive via message handlers.
class FileOperations {
  final MessageSender _sender;

  FileOperations(this._sender);

  /// Request the file tree from the agent.
  void requestFileTree({String path = '/', int depth = 2}) =>
      _sender.send(WsMessage(
          type: MessageType.fileTree,
          payload: FileTreePayload(path: path, depth: depth).toJson()));

  /// Request file content by [path].
  void requestFileRead(String path) => _sender.send(WsMessage(
      type: MessageType.fileRead,
      payload: FileReadPayload(path: path).toJson()));

  /// Search files by [query] with optional content search flags.
  void requestFileSearch(String query, {
    bool searchContent = false,
    bool isRegex = false,
    bool caseSensitive = false,
    bool wholeWord = false,
  }) =>
      _sender.send(WsMessage(
          type: MessageType.fileSearch,
          payload: FileSearchPayload(
            query: query,
            searchContent: searchContent,
            isRegex: isRegex,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
          ).toJson()));

  /// Create a file or directory at [path] with [name].
  void createFile(String path, String name, String type) =>
      _sender.send(WsMessage(
          type: MessageType.fileCreate,
          payload:
              FileCreatePayload(path: path, name: name, type: type).toJson()));

  /// Rename a file at [path] to [newName].
  void renameFile(String path, String newName) => _sender.send(WsMessage(
      type: MessageType.fileRename,
      payload: FileRenamePayload(path: path, newName: newName).toJson()));

  /// Delete a file at [path].
  void deleteFile(String path) => _sender.send(WsMessage(
      type: MessageType.fileDelete,
      payload: FileDeletePayload(path: path).toJson()));

  /// Write file content (used by the code editor save action).
  void writeFile(String path, String content) => _sender.send(WsMessage(
      type: MessageType.fileWrite,
      payload: FileWritePayload(path: path, content: content).toJson()));

  /// Apply a diff (accept file edit).
  void applyDiff(String path, String content) => _sender.send(WsMessage(
      type: MessageType.diffApply,
      payload:
          DiffApplyPayload(filePath: path, newContent: content).toJson()));

  /// Reject a diff (discard file edit).
  void rejectDiff(String path) => _sender.send(WsMessage(
      type: MessageType.diffReject,
      payload: DiffRejectPayload(filePath: path).toJson()));
}
