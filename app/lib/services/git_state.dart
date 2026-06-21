/// git_state.dart — Multi-repo git state provider.
///
/// Module: services/
/// Responsibility:
///   Single source of truth for all git data. Each repository is an
///   independent RepoState instance — no global mutable fields, no
///   "active repo" concept on the data layer.
///
///   UI selection ("which repo am I looking at") is purely a frontend
///   concern and does not affect data storage or event routing.
///
/// Data flow:
///   Agent state.push (with repo_path) → GitStateProvider._onStatusPush()
///   → _repos[repo_path] updated → notifyListeners() → UI rebuilds
///
/// Architecture:
///   - _repos: Map<path, RepoState> — per-repo isolated state
///   - No global branch/staged/unstaged fields
///   - Write operations require explicit repo path
///   - state.push routed by repo_path — only that repo updated
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/event_bus.dart';
import '../models/payloads/git_payloads.g.dart';
import '../models/protocol.dart';
import '../models/repo_state.dart';
import '../utils/logger.dart';
import 'websocket_service.dart';
import 'ws_operations/git_operations.dart';

final _log = getLogger('GitState');

/// Multi-repo git state provider — all repos tracked independently.
///
/// Each repository is an independent [RepoState] instance stored in [_repos].
/// All git screens read from this provider. No global mutable state.
class GitStateProvider extends ChangeNotifier {
  // ── Per-repository state (the single source of truth) ──

  final Map<String, RepoState> _repos = {};

  /// All repositories sorted: repos with changes first, then alphabetical.
  List<RepoState> get allRepos {
    final list = _repos.values.toList();
    list.sort((a, b) {
      if (a.hasChanges && !b.hasChanges) return -1;
      if (!a.hasChanges && b.hasChanges) return 1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  /// Number of tracked repositories.
  int get repoCount => _repos.length;

  /// Whether multiple repositories are tracked.
  bool get isMultiRepo => _repos.length > 1;

  /// Aggregated totals across all repos.
  int get totalChanges =>
      _repos.values.fold(0, (s, r) => s + r.totalChanges);
  int get totalAhead =>
      _repos.values.fold(0, (s, r) => s + r.ahead);
  int get totalBehind =>
      _repos.values.fold(0, (s, r) => s + r.behind);

  /// Get a specific repo's state by path.
  RepoState? getRepo(String path) => _repos[path];

  // ── Per-repo operation state ──

  final Map<String, _RepoOpState> _opStates = {};

  bool isCommitting(String repo) => _opStates[repo]?.committing ?? false;
  bool isPushing(String repo) => _opStates[repo]?.pushing ?? false;
  bool isPulling(String repo) => _opStates[repo]?.pulling ?? false;

  // ── Agent busy state (global, for progress indicator) ──

  bool agentBusy = false;
  String agentOperation = '';

  // ── Per-repo shell history ──

  final Map<String, List<Map<String, dynamic>>> _shellHistory = {};

  List<Map<String, dynamic>> shellHistoryFor(String repo) =>
      _shellHistory[repo] ?? [];

  // ── Per-repo branches/log (loaded on demand) ──

  final Map<String, List<Map<String, dynamic>>> _branches = {};
  final Map<String, List<Map<String, dynamic>>> _logEntries = {};

  List<Map<String, dynamic>> branchesFor(String repo) =>
      _branches[repo] ?? [];
  List<Map<String, dynamic>> logEntriesFor(String repo) =>
      _logEntries[repo] ?? [];

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


  // ── Lifecycle ──

  /// Bind to WebSocketService and EventBus.
  void bind(WebSocketService ws, AppEventBus eventBus) {
    if (_ws == ws && _eventBus == eventBus) return;
    _dispose();

    _ws = ws;
    _gitOps = ws.gitOps;
    _eventBus = eventBus;

    eventBus.on(AppEvents.gitStatusPush, _onStatusPush);
    eventBus.on(AppEvents.gitBranchesPush, _onBranchesPush);
    eventBus.on(AppEvents.gitLogPush, _onLogPush);
    eventBus.on(AppEvents.gitProgressPush, _onProgressPush);
    eventBus.on(AppEvents.projectSwitched, _onProjectSwitched);

    _msgSub = ws.messageStream.listen(_onMessage);
    _log.info('GitStateProvider 已绑定');
  }

  /// Request initial git data from Agent (all repos status).
  void requestInitialData() {
    final now = DateTime.now();
    if (_lastRequestTime != null &&
        now.difference(_lastRequestTime!).inMilliseconds < 2000) {
      _log.fine('requestInitialData: 跳过（2s 内已请求）');
      return;
    }
    _lastRequestTime = now;
    _log.info('请求初始 Git 数据');
    _gitOps?.requestGitStatusAll();
  }

  /// Force refresh all repos (user-triggered).
  void refresh() {
    _log.fine('手动刷新 Git 状态');
    _initialized = false;
    notifyListeners();
    _gitOps?.requestGitStatusAll();
  }

  /// Clear all state on project switch or disconnect.
  void clear() {
    _log.fine('清除 Git 状态缓存');
    _repos.clear();
    _opStates.clear();
    _shellHistory.clear();
    _branches.clear();
    _logEntries.clear();
    agentBusy = false;
    agentOperation = '';
    _initialized = false;
    _lastRequestTime = null;
    notifyListeners();
  }

  // ── Write operations (all require repo path) ──

  /// Stage specific files in a repository.
  void stage(List<String> paths, {required String repo}) =>
      _gitOps?.gitStage(paths, repo: repo);

  /// Stage all changed files in a repository.
  void stageAll({required String repo}) =>
      _gitOps?.gitStageAll(repo: repo);

  /// Unstage specific files in a repository.
  void unstageFiles(List<String> paths, {required String repo}) =>
      _gitOps?.gitUnstage(paths, repo: repo);

  /// Unstage all staged files in a repository.
  void unstageAll({required String repo}) =>
      _gitOps?.gitUnstageAll(repo: repo);

  /// Commit staged changes in a repository.
  void commit(String message, {required String repo}) {
    _getOpState(repo).committing = true;
    notifyListeners();
    _gitOps?.gitCommit(message, repo: repo);
  }

  /// Push to remote for a repository.
  void push({required String repo}) {
    _getOpState(repo).pushing = true;
    notifyListeners();
    _gitOps?.gitPush(repo: repo);
  }

  /// Pull from remote for a repository.
  void pull({required String repo}) {
    _getOpState(repo).pulling = true;
    notifyListeners();
    _gitOps?.gitPull(repo: repo);
  }

  /// Checkout a branch in a repository.
  void checkout(String branchName, {required String repo}) =>
      _gitOps?.gitCheckout(branchName, repo: repo);

  /// Discard changes for a file in a repository.
  void discard(String path, {required String repo}) =>
      _gitOps?.gitDiscard(path, repo: repo);

  /// Execute a git shell command in a repository.
  void execCommand(String cmd, {required String repo, bool confirmed = false}) =>
      _gitOps?.execGitCommand(cmd, repo: repo, confirmed: confirmed);

  /// Request diff for a specific file.
  void requestDiff(String path, {required String repo, bool isStaged = false}) =>
      _gitOps?.gitDiffFile(path, repo: repo, staged: isStaged);

  /// Request branches for a specific repo.
  void requestBranches({required String repo}) =>
      _gitOps?.gitBranches(repo: repo);

  /// Request log for a specific repo.
  void requestLog({required String repo}) =>
      _gitOps?.gitLog(repo: repo);

  /// Abort the current merge operation.
  void mergeAbort({required String repo}) =>
      _gitOps?.gitMergeAbort(repo: repo);

  // ── EventBus handlers (state.push from Agent) ──

  void _onStatusPush(Map<String, dynamic> data) {
    final payload = data['data'];
    if (payload is! Map<String, dynamic>) return;
    final repoPath = data['repo_path'] as String? ?? '';

    if (repoPath.isNotEmpty) {
      _updateRepoState(repoPath, payload);
    }
  }

  void _onBranchesPush(Map<String, dynamic> data) {
    final payload = data['data'];
    if (payload is! Map<String, dynamic>) return;
    final repoPath = data['repo_path'] as String? ?? '';
    final list = (payload['branches'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (repoPath.isNotEmpty) {
      _branches[repoPath] = list;
    }
    _log.fine('state.push → branches: ${list.length} 个 (repo=$repoPath)');
    notifyListeners();
  }

  void _onLogPush(Map<String, dynamic> data) {
    final payload = data['data'];
    if (payload is! Map<String, dynamic>) return;
    final repoPath = data['repo_path'] as String? ?? '';
    final list = (payload['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (repoPath.isNotEmpty) {
      _logEntries[repoPath] = list;
    }
    _log.fine('state.push → log: ${list.length} 条 (repo=$repoPath)');
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

  // ── WebSocket message handler ──

  void _onMessage(WsMessage msg) {
    switch (msg.type) {
      // Multi-repo status (primary data source)
      case MessageType.gitStatusAllResult:
        final repoList = (msg.payload['repos'] as List?) ?? [];
        _repos.clear();
        for (final repoData in repoList) {
          if (repoData is Map<String, dynamic>) {
            final state = RepoState.fromJson(repoData);
            if (state.path.isNotEmpty) {
              _repos[state.path] = state;
            }
          }
        }
        _initialized = true;
        _log.info('git.status.all: ${_repos.length} 个仓库');
        notifyListeners();

      // Single-repo status (backward compat / state.push result)
      case MessageType.gitStatusResult:
        final repoPath = msg.payload['repo_path'] as String? ?? '';
        if (repoPath.isNotEmpty) {
          _updateRepoState(repoPath, msg.payload);
        }

      case MessageType.gitLogResult:
        final repoPath = msg.payload['repo_path'] as String? ?? '';
        final p = GitLogResultPayload.fromJson(msg.payload);
        if (repoPath.isNotEmpty) {
          _logEntries[repoPath] = p.entries;
        }
        notifyListeners();

      case MessageType.gitBranchesResult:
        final repoPath = msg.payload['repo_path'] as String? ?? '';
        final p = GitBranchesResultPayload.fromJson(msg.payload);
        if (repoPath.isNotEmpty) {
          _branches[repoPath] = p.branches;
        }
        notifyListeners();

      // Write operation results
      case MessageType.gitCommitResult:
        final commitRepo = msg.payload['repo'] as String? ?? '';
        // Always reset committing — result means operation is done
        if (commitRepo.isNotEmpty) {
          _getOpState(commitRepo).committing = false;
        } else {
          // Fallback: reset all repos' committing flag
          for (final op in _opStates.values) {
            op.committing = false;
          }
        }
        _log.info('commit 完成: repo=$commitRepo');
        notifyListeners();

      case MessageType.gitPushResult:
        final pushRepo = msg.payload['repo'] as String? ?? '';
        if (pushRepo.isNotEmpty) {
          _getOpState(pushRepo).pushing = false;
        } else {
          for (final op in _opStates.values) {
            op.pushing = false;
          }
        }
        _log.info('push 完成: repo=$pushRepo');
        notifyListeners();

      case MessageType.gitPullResult:
        final pullRepo = msg.payload['repo'] as String? ?? '';
        if (pullRepo.isNotEmpty) {
          _getOpState(pullRepo).pulling = false;
        } else {
          for (final op in _opStates.values) {
            op.pulling = false;
          }
        }
        _log.info('pull 完成: repo=$pullRepo');
        notifyListeners();

      case MessageType.gitStageResult:
      case MessageType.gitUnstageResult:
      case MessageType.gitDiscardResult:
      case MessageType.gitCheckoutResult:
        _log.fine('操作完成: ${msg.type}');

      case MessageType.gitExecResult:
        final repo = msg.payload['repo'] as String? ?? '';
        if (repo.isNotEmpty) {
          _shellHistory.putIfAbsent(repo, () => []).add(msg.payload);
        }
        _log.fine('shell 命令完成');
        notifyListeners();

      default:
        break;
    }
  }

  // ── Internal helpers ──

  void _updateRepoState(String repoPath, Map<String, dynamic> payload) {
    final name = payload['name'] as String? ??
        repoPath.split('/').last.split('\\').last;
    _repos[repoPath] = RepoState(
      path: repoPath,
      name: name,
      branch: payload['branch'] as String? ?? '',
      ahead: payload['ahead'] as int? ?? 0,
      behind: payload['behind'] as int? ?? 0,
      staged: _parseFileList(payload['staged']),
      unstaged: _parseFileList(payload['unstaged']),
      untracked: _parseFileList(payload['untracked']),
      conflicted: _parseFileList(payload['conflicted']),
      error: payload['error'] as String? ?? '',
    );
    _initialized = true;
    notifyListeners();
  }

  _RepoOpState _getOpState(String repo) =>
      _opStates.putIfAbsent(repo, () => _RepoOpState());

  static List<Map<String, dynamic>> _parseFileList(dynamic data) {
    if (data is! List) return [];
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) item,
    ];
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

/// Per-repo mutable operation flags.
class _RepoOpState {
  bool committing = false;
  bool pushing = false;
  bool pulling = false;
}
