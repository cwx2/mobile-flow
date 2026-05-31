/// project_operations.dart — Project list, search, browse, add, remove, switch operations.
///
/// Holds a [WebSocketService] reference for [switchProject] which needs
/// to clear messages and reset CLI state before sending.
library;

import '../../models/protocol.dart';
import '../../models/payloads/project_payloads.g.dart';
import '../websocket_service.dart';

/// Domain operations for project management.
///
/// Most methods are pure senders, but [switchProject] needs
/// WebSocketService access for state mutation before sending.
class ProjectOperations {
  final WebSocketService _ws;

  ProjectOperations(this._ws);

  /// Request the list of projects.
  void requestProjectList() => _ws.send(WsMessage(
      type: MessageType.projectList,
      payload: const ProjectListPayload().toJson()));

  /// Search for projects by name across configured search roots.
  ///
  /// Results arrive via [MessageType.projectSearchResult] messages on
  /// messageStream. The UI should debounce (300ms) before calling this.
  /// Pass an empty [query] to retrieve recent projects instead.
  void searchProjects(String query, {int? maxResults}) =>
      _ws.send(WsMessage(
          type: MessageType.projectSearch,
          payload: ProjectSearchPayload(
            query: query,
            maxResults: maxResults,
          ).toJson()));

  /// Browse a directory's subdirectories for the project picker.
  ///
  /// Pass "~" or an empty [path] to start from the home directory.
  /// On Windows, pass "" to get drive letter listing.
  /// Results arrive as projectSearchResult with `is_browsing: true`.
  void browseDirectory(String path) => _ws.send(WsMessage(
      type: MessageType.projectSearch,
      payload: ProjectSearchPayload(path: path).toJson()));

  /// Add a project by [path] with optional display [name].
  void addProject(String path, {String? name}) => _ws.send(WsMessage(
      type: MessageType.projectAdd,
      payload: ProjectAddPayload(path: path, name: name).toJson()));

  /// Remove a project by [path].
  void removeProject(String path) => _ws.send(WsMessage(
      type: MessageType.projectRemove,
      payload: ProjectRemovePayload(path: path).toJson()));

  /// Switch to a different project, clearing current messages.
  void switchProject(String path) {
    _ws.messages.clear();
    _ws.resetCliState();
    _ws.notifyUI();
    _ws.send(WsMessage(
        type: MessageType.projectSwitch,
        payload: ProjectSwitchPayload(path: path).toJson()));
  }

  /// Request the current active project info.
  void requestCurrentProject() => _ws.send(WsMessage(
      type: MessageType.projectCurrent,
      payload: const ProjectCurrentPayload().toJson()));
}
