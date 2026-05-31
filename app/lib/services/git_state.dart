/// git_state.dart — Unified git state provider for the App.
///
/// Module: services/
/// Responsibility:
///   Single source of truth for all git data in the App. Subscribes to
///   Agent's state.push events via AppEventBus and exposes cached state
///   to all screens via Provider. Screens read from this provider instead
///   of sending their own WebSocket requests.
///
///   Mirrors the Agent's GitStateManager: Agent caches git state in
///   memory and pushes updates; this provider caches the pushed state
///   and notifies UI via ChangeNotifier.
///
/// Data flow:
///   Agent state.push → WebSocketService._handleStatePush()
///   → AppEventBus.emit(gitStatusPush) → GitStateProvider._onStatusPush()
///   → notifyListeners() → UI rebuilds
///
/// Used by:
///   - screens/git_screen.dart (reads all git state)
///   - widgets/git_changes_tab.dart, git_commit_tab.dart, etc.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/event_bus.dart';
import '../models/payloads/git_payloads.g.dart';
import '../models/protocol.dart';
import '../utils/logger.dart';
import 'websocket_service.dart';
import 'ws_operations/git_operations.dart';

final _log = getLogger('GitState');

/// Unified git state provider — single source of truth for all git data.
///
/// Subscribes to Agent's state.push events and WebSocket result messages.
/// All git screens read from this provider instead of managing their own
/// state or sending duplicate requests.
class GitStateProvider extends ChangeNotifier {
  // ── Cached state (populated by state.push from Agent) ──

  String branch = '';
  int ahead = 0;
  int behind = 0;
  List<Map<String, dynamic>> staged = [];
  List<Map<String, dynamic>> unstaged = [];
  List<Map<String, dynamic>> untracked = [];
  List<Map<String, dynamic>> logEntries = [];
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> repos = [];
  String error = '';

  // ── Operation state ──

  bool committing = false;
  bool pushing = false;
  bool pulling = false;
  bool agentBusy = false;
  String agentOperation = '';

  // ── Shell history (local to App, not pushed by Agent) ──

  final List<Map<String, dynamic>> shellHistory = [];

  // ── Loading state ──

  bool _initialized = false;
  bool get isInitialized => _initialized;

  // ── Dependencies ──

  WebSocketService? _ws;
  GitOperations? _gitOps;
  AppEventBus? _eventBus;
  StreamSubscription? _msgSub;

  // ── Request dedup ──

  DateTime? _lastRequestTime;

  /// Total change count for tab badge.
  int get totalChanges => staged.length + unstaged.length + untracked.length;

  /// Active repository name from repos list.
  String get activeRepoName {
    for (final repo in repos) {
      if (repo['is_current'] == true) {
        return repo['name'] as String? ?? '';
      }
    }
    return '';
  }

  /// Bind to WebSocketService and EventBus.
  ///
  /// Called by ProxyProvider in main.dart whenever dependencies change.
  /// Subscribes to EventBus for state.push events and to messageStream
  /// for operation result messages (commit/push/pull results).
  void bind(WebSocketService ws, AppEventBus eventBus) {
    if (_ws == ws && _eventBus == eventBus) return;

    // Unsubscribe old listeners
    _dispose();

    _ws = ws;
    _gitOps = ws.gitOps;
    _eventBus = eventBus;

    // Subscribe to state.push events from Agent
    eventBus.on(AppEvents.gitStatusPush, _onStatusPush);
    eventBus.on(AppEvents.gitBranchesPush, _onBranchesPush);
    eventBus.on(AppEvents.gitLogPush, _onLogPush);
    eventBus.on(AppEvents.gitProgressPush, _onProgressPush);
    eventBus.on(AppEvents.projectSwitched, _onProjectSwitched);

    // Subscribe to operation result messages
    _msgSub = ws.messageStream.listen(_onMessage);

    _log.info('GitStateProvider 已绑定');
  }

  /// Request initial git data from Agent.
  ///
  /// Called once after connection + auth. Deduplicates requests within
  /// 2 seconds to prevent multiple screens from triggering redundant
  /// requests on the same connection event.
  void requestInitialData() {
    final now = DateTime.now();
    if (_lastRequestTime != null &&
        now.difference(_lastRequestTime!).inMilliseconds < 2000) {
      _log.fine('requestInitialData: 跳过（2s 内已请求）');
      return;
    }
    _lastRequestTime = now;
    _log.info('请求初始 Git 数据');
    _gitOps?.requestGitStatus();
    _gitOps?.gitLog();
    _gitOps?.gitBranches();
    _gitOps?.requestGitRepos();
  }

  /// Force refresh all git data (user-triggered pull-to-refresh).
  void refresh() {
    _log.fine('手动刷新 Git 状态');
    _initialized = false;
    error = '';
    notifyListeners();
    _gitOps?.requestGitStatus();
    _gitOps?.gitLog();
    _gitOps?.gitBranches();
    _gitOps?.requestGitRepos();
  }

  /// Clear all state on project switch or disconnect.
  void clear() {
    _log.fine('清除 Git 状态缓存');
    branch = '';
    ahead = 0;
    behind = 0;
    staged = [];
    unstaged = [];
    untracked = [];
    logEntries = [];
    branches = [];
    repos = [];
    error = '';
    committing = false;
    pushing = false;
    pulling = false;
    agentBusy = false;
    agentOperation = '';
    shellHistory.clear();
    _initialized = false;
    _lastRequestTime = null;
    notifyListeners();
  }

  // ── Write operations (delegate to WebSocketService) ──

  /// Stage specific files.
  void stage(List<String> paths) => _gitOps?.gitStage(paths);

  /// Stage all changed files.
  void stageAll() => _gitOps?.gitStageAll();

  /// Unstage specific files.
  void unstageFiles(List<String> paths) => _gitOps?.gitUnstage(paths);

  /// Unstage all staged files.
  void unstageAll() => _gitOps?.gitUnstageAll();

  /// Commit staged changes.
  void commit(String message) {
    committing = true;
    notifyListeners();
    _gitOps?.gitCommit(message);
  }

  /// Push to remote.
  void push() {
    pushing = true;
    notifyListeners();
    _gitOps?.gitPush();
  }

  /// Pull from remote.
  void pull() {
    pulling = true;
    notifyListeners();
    _gitOps?.gitPull();
  }

  /// Checkout a branch.
  void checkout(String branchName) => _gitOps?.gitCheckout(branchName);

  /// Discard changes for a file.
  void discard(String path) => _gitOps?.gitDiscard(path);

  /// Switch active git repository.
  void switchRepo(String path) {
    _gitOps?.switchGitRepo(path);
    refresh();
  }

  /// Execute a git shell command.
  void execCommand(String cmd, {bool confirmed = false}) =>
      _gitOps?.execGitCommand(cmd, confirmed: confirmed);

  /// Request diff for a specific file.
  void requestDiff(String path, {bool isStaged = false}) =>
      _gitOps?.gitDiffFile(path, staged: isStaged);

  // ── EventBus handlers (state.push from Agent) ──

  void _onStatusPush(Map<String, dynamic> data) {
    final payload = data['data'];
    if (payload is! Map<String, dynamic>) return;
    _updateStatus(payload);
  }

  void _onBranchesPush(Map<String, dynamic> data) {
    final payload = data['data'];
    if (payload is! Map<String, dynamic>) return;
    branches = (payload['branches'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    _log.fine('state.push → branches: ${branches.length} 个');
    notifyListeners();
  }

  void _onLogPush(Map<String, dynamic> data) {
    final payload = data['data'];
    if (payload is! Map<String, dynamic>) return;
    logEntries = (payload['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    _log.fine('state.push → log: ${logEntries.length} 条');
    notifyListeners();
  }

  void _onProgressPush(Map<String, dynamic> data) {
    agentBusy = data['busy'] as bool? ?? false;
    agentOperation = data['operation'] as String? ?? '';
    notifyListeners();
  }

  void _onProjectSwitched(Map<String, dynamic> _) {
    _log.info('项目切换，清除 Git 状态');
    clear();
    if (_ws != null && _ws!.currentProjectPath.isNotEmpty) {
      requestInitialData();
    }
  }

  // ── WebSocket message handler (operation results) ──

  void _onMessage(WsMessage msg) {
    switch (msg.type) {
      // Read results (from direct requests, not state.push)
      case MessageType.gitStatusResult:
        _updateStatus(msg.payload);

      case MessageType.gitLogResult:
        final p = GitLogResultPayload.fromJson(msg.payload);
        logEntries = p.entries;
        notifyListeners();

      case MessageType.gitBranchesResult:
        final p = GitBranchesResultPayload.fromJson(msg.payload);
        branches = p.branches;
        notifyListeners();

      case MessageType.gitReposResult:
        final p = GitReposResultPayload.fromJson(msg.payload);
        repos = p.repos;
        if (repos.isNotEmpty) {
          _initialized = true;
          // Sub-repos found — clear "not a git repo" error
          if (error.isNotEmpty) error = '';
        }
        _log.fine('repos: ${repos.length} 个仓库');
        notifyListeners();

      // Write operation results
      case MessageType.gitCommitResult:
        committing = false;
        final p = GitCommitResultPayload.fromJson(msg.payload);
        _log.info('commit 完成: error=${p.error ?? '无'}');
        notifyListeners();

      case MessageType.gitPushResult:
        pushing = false;
        final p = GitPushResultPayload.fromJson(msg.payload);
        _log.info('push 完成: error=${p.error ?? '无'}');
        notifyListeners();

      case MessageType.gitPullResult:
        pulling = false;
        final p = GitPullResultPayload.fromJson(msg.payload);
        _log.info('pull 完成: error=${p.error ?? '无'}');
        notifyListeners();

      case MessageType.gitStageResult:
      case MessageType.gitUnstageResult:
      case MessageType.gitDiscardResult:
      case MessageType.gitCheckoutResult:
        _log.fine('操作完成: ${msg.type}');
        // State will be updated by state.push, no action needed here

      case MessageType.gitExecResult:
        // Keep raw Map for shell history display
        shellHistory.add(msg.payload);
        final p = GitExecResultPayload.fromJson(msg.payload);
        _log.fine('shell 命令完成: success=${p.success}');
        notifyListeners();

      default:
        break;
    }
  }

  /// Update status fields from a status payload (shared by state.push and direct result).
  void _updateStatus(Map<String, dynamic> payload) {
    branch = payload['branch'] as String? ?? '';
    ahead = payload['ahead'] as int? ?? 0;
    behind = payload['behind'] as int? ?? 0;
    staged = _parseFileList(payload['staged']);
    unstaged = _parseFileList(payload['unstaged']);
    untracked = _parseFileList(payload['untracked']);
    final err = payload['error'] as String? ?? '';
    // If sub-repos were found, suppress "not a git repo" error
    error = (repos.isNotEmpty && err.isNotEmpty) ? '' : err;
    _initialized = true;
    _log.fine(
        'status 更新: branch=$branch, staged=${staged.length}, '
        'unstaged=${unstaged.length}, untracked=${untracked.length}');
    notifyListeners();
  }

  List<Map<String, dynamic>> _parseFileList(dynamic data) {
    if (data is List) return data.cast<Map<String, dynamic>>();
    return [];
  }

  void _dispose() {
    _msgSub?.cancel();
    _msgSub = null;
    _eventBus?.off(AppEvents.gitStatusPush, _onStatusPush);
    _eventBus?.off(AppEvents.gitBranchesPush, _onBranchesPush);
    _eventBus?.off(AppEvents.gitLogPush, _onLogPush);
    _eventBus?.off(AppEvents.gitProgressPush, _onProgressPush);
    _eventBus?.off(AppEvents.projectSwitched, _onProjectSwitched);
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }
}
