/// git_screen.dart — Git operations panel.
//
// Module: screens/
// Responsibility:
//   Pure UI layer for Git operations. Reads all git data from
//   GitStateProvider (single source of truth) instead of managing
//   its own state or sending WebSocket requests directly.
//
//   Includes:
//   - Changed file list (staged / unstaged / untracked groups)
//   - File diff viewing (tap a file to open diff viewer)
//   - Stage / Unstage operations
//   - Commit (message input + commit button)
//   - Push / Pull buttons
//   - Branch switching
//   - Git log (commit history)
//   - Git Shell (safe command execution)
//
// Called by:
//   - HomeScreen bottom navigation Git tab

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_button.dart';
import '../components/app_toast.dart';
import '../components/workbench_state_card.dart';
import '../l10n/app_localizations.dart';
import '../core/loading_state.dart';
import '../animation/page_transition_builder.dart';
import '../models/protocol.dart';
import '../models/payloads/git_payloads.g.dart';
import '../services/git_state.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/git_operations.dart';
import '../theme/theme_extensions.dart';
import '../widgets/git_changes_tab.dart';
import '../widgets/git_commit_tab.dart';
import '../widgets/git_log_tab.dart';
import '../widgets/git_shell_tab.dart';
import 'diff_viewer_screen.dart';
import '../utils/logger.dart';

final _log = getLogger('GitScreen');

/// Git operations screen — pure UI, reads from GitStateProvider.
class GitScreen extends StatefulWidget {
  const GitScreen({super.key});

  @override
  State<GitScreen> createState() => _GitScreenState();
}

class _GitScreenState extends State<GitScreen>
    with SingleTickerProviderStateMixin, LoadingStateMixin {
  late TabController _tabController;
  final _commitController = TextEditingController();
  final _shellController = TextEditingController();

  StreamSubscription? _resultSub;
  // Saved reference to avoid context.read in async callbacks
  // (context is unsafe after deactivate, even if mounted is true)
  late final GitStateProvider _git;

  // Tracks the actual log entry count (updated by GitLogTab via callback,
  // so the tab title reflects paginated totals, not just the initial page).
  int _logCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _git = context.read<GitStateProvider>();
    _logCount = _git.logEntries.length;

    // Listen for operation results that need toast feedback
    final ws = context.read<WebSocketService>();
    _resultSub = ws.messageStream.listen(_onOperationResult);

    // Request initial data via provider
    final git = context.read<GitStateProvider>();
    if (!git.isInitialized) {
      startLoadingTimeout();
      git.requestInitialData();
    }
  }

  /// Handle operation result messages for toast feedback.
  ///
  /// GitStateProvider handles state updates; this only shows toasts
  /// because toasts need BuildContext which providers don't have.
  void _onOperationResult(WsMessage msg) {
    if (!mounted) return;

    switch (msg.type) {
      case MessageType.gitCommitResult:
        final p = GitCommitResultPayload.fromJson(msg.payload);
        final err = p.error ?? '';
        if (err.isNotEmpty && _git.branch.isNotEmpty) {
          AppToast.show(context, err, type: AppToastType.error);
        } else if (err.isEmpty) {
          _commitController.clear();
        }

      case MessageType.gitPushResult:
        final p = GitPushResultPayload.fromJson(msg.payload);
        final err = p.error ?? '';
        if (err.isNotEmpty && _git.branch.isNotEmpty) {
          AppToast.show(context, err, type: AppToastType.error);
        } else if (p.upToDate) {
          AppToast.show(context, S.of(context).gitPushUpToDate);
        } else if (err.isEmpty) {
          AppToast.show(context, S.of(context).gitPushSuccess);
        }

      case MessageType.gitPullResult:
        final p = GitPullResultPayload.fromJson(msg.payload);
        final err = p.error ?? '';
        if (err.isNotEmpty && _git.branch.isNotEmpty) {
          AppToast.show(context, err, type: AppToastType.error);
        } else if (p.upToDate) {
          AppToast.show(context, S.of(context).gitPullUpToDate);
        } else if (err.isEmpty) {
          AppToast.show(context, S.of(context).gitPullSuccess);
        }

      case MessageType.gitStageResult:
        final p = GitStageResultPayload.fromJson(msg.payload);
        if ((p.error ?? '').isNotEmpty && _git.branch.isNotEmpty) {
          AppToast.show(context, p.error!, type: AppToastType.error);
        }
      case MessageType.gitUnstageResult:
        final p = GitUnstageResultPayload.fromJson(msg.payload);
        if ((p.error ?? '').isNotEmpty && _git.branch.isNotEmpty) {
          AppToast.show(context, p.error!, type: AppToastType.error);
        }
      case MessageType.gitDiscardResult:
        final p = GitDiscardResultPayload.fromJson(msg.payload);
        if ((p.error ?? '').isNotEmpty && _git.branch.isNotEmpty) {
          AppToast.show(context, p.error!, type: AppToastType.error);
        }
      case MessageType.gitCheckoutResult:
        final p = GitCheckoutResultPayload.fromJson(msg.payload);
        if ((p.error ?? '').isNotEmpty && _git.branch.isNotEmpty) {
          AppToast.show(context, p.error!, type: AppToastType.error);
        }

      case MessageType.gitExecResult:
        final p = GitExecResultPayload.fromJson(msg.payload);
        if (p.success) {
          AppToast.show(context, S.of(context).gitExecSuccess, type: AppToastType.success);
        }

      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ws = context.watch<WebSocketService>();
    final git = context.watch<GitStateProvider>();

    // Stop loading spinner when data arrives
    if (git.isInitialized && isLoading) {
      markDataReceived();
    }

    // No project selected — show empty state with guidance
    if (ws.currentProjectPath.isEmpty) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.surface,
          toolbarHeight: 44,
          title: const Row(
            children: [
              Icon(Icons.commit, size: 20),
              SizedBox(width: 8),
              Text('Git', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
        body: WorkbenchStateCard(
          icon: Icons.folder_off_outlined,
          title: S.of(context).gitNoWorkDir,
          description: S.of(context).gitNoWorkDirDescription,
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        titleSpacing: 12,
        toolbarHeight: 44,
        title: GestureDetector(
          onTap: git.repos.length > 1 ? _showRepoSwitcher : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.commit, size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (git.repos.length > 1) ...[
                        Flexible(
                          flex: 0,
                          child: Text(
                            git.activeRepoName,
                            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text('/', style: TextStyle(fontSize: 13, color: colors.onSurfaceMuted)),
                        ),
                      ],
                      Flexible(
                        child: Text(
                          git.branch.isNotEmpty ? git.branch : 'Git',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (git.repos.length > 1)
                        Icon(Icons.unfold_more, size: 14, color: colors.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              if (git.branch.isNotEmpty) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _showBranchPicker,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.swap_horiz, size: 16, color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 20),
            onPressed: isLoading ? null : () {
              _log.fine('手动刷新');
              setState(() { resetLoading(); });
              startLoadingTimeout();
              git.refresh();
            },
            tooltip: S.of(context).filesRefresh,
          ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.download, size: 20, color: git.pulling ? colors.secondary : null),
                if (git.behind > 0)
                  Positioned(right: -8, top: -4,
                    child: Text('${git.behind}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: colors.primary))),
              ],
            ),
            onPressed: git.pulling ? null : () => git.pull(),
            tooltip: git.behind > 0 ? 'Pull (${git.behind})' : 'Pull',
          ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.upload, size: 20,
                    color: git.pushing ? colors.secondary : git.ahead > 0 ? null : colors.onSurfaceMuted.withValues(alpha: 0.3)),
                if (git.ahead > 0)
                  Positioned(right: -8, top: -4,
                    child: Text('${git.ahead}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: colors.success))),
              ],
            ),
            onPressed: git.pushing || git.ahead == 0 ? null : () => git.push(),
            tooltip: git.ahead > 0 ? 'Push (${git.ahead})' : S.of(context).gitPushNoCommits,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(text: '${S.of(context).gitTabChanges} (${git.totalChanges})'),
                  Tab(text: S.of(context).gitTabCommit),
                  const Tab(text: 'Shell'),
                  Tab(text: '${S.of(context).gitTabHistory} ($_logCount)'),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: git.agentBusy
                    ? Tooltip(
                        message: git.agentOperation.isNotEmpty ? git.agentOperation : S.of(context).gitProcessing,
                        child: const LinearProgressIndicator(minHeight: 2),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
        child: loadingError.isNotEmpty
            ? KeyedSubtree(key: const ValueKey('timeout'), child: _buildTimeoutState(git))
            : isLoading
                ? const KeyedSubtree(key: ValueKey('loading'), child: Center(child: CircularProgressIndicator()))
                : git.error.isNotEmpty
                    ? KeyedSubtree(key: const ValueKey('error'), child: _buildGitErrorState(git))
                    : (git.repos.isNotEmpty && git.branch.isEmpty)
                        ? KeyedSubtree(key: const ValueKey('repo-selector'), child: _buildRepoSelector(git))
                        : TabBarView(
                            key: const ValueKey('tabs'),
                            controller: _tabController,
                            children: [
                              GitChangesTab(
                                staged: git.staged,
                                unstaged: git.unstaged,
                                untracked: git.untracked,
                                ws: context.read<WebSocketService>(),
                                onShowDiff: _showFileDiff,
                                onConfirmDiscard: _confirmDiscard,
                              ),
                              GitCommitTab(
                                stagedCount: git.staged.length,
                                ahead: git.ahead,
                                committing: git.committing,
                                pushing: git.pushing,
                                pulling: git.pulling,
                                commitController: _commitController,
                                ws: context.read<WebSocketService>(),
                                onCommit: () => git.commit(_commitController.text.trim()),
                                onPush: () => git.push(),
                                onPull: () => git.pull(),
                              ),
                              GitShellTab(
                                history: git.shellHistory,
                                controller: _shellController,
                                ws: context.read<WebSocketService>(),
                              ),
                              GitLogTab(
                                entries: git.logEntries,
                                branches: git.branches,
                                onCountChanged: (count) {
                                  if (mounted && count != _logCount) {
                                    setState(() => _logCount = count);
                                  }
                                },
                              ),
                            ],
                          ),
      ),
    );
  }

  Widget _buildTimeoutState(GitStateProvider git) {
    return WorkbenchStateCard(
      icon: Icons.wifi_off_outlined,
      tint: context.colors.error,
      title: S.of(context).gitLoadTimeout,
      description: loadingError,
      action: AppButton(
        label: S.of(context).gitRecheck,
        icon: Icons.refresh_rounded,
        onTap: () {
          setState(() { resetLoading(); });
          startLoadingTimeout();
          git.refresh();
        },
      ),
    );
  }

  Widget _buildGitErrorState(GitStateProvider git) {
    final colors = context.colors;
    if (git.repos.isNotEmpty) return _buildRepoSelector(git);
    return WorkbenchStateCard(
      icon: Icons.source_outlined,
      tint: colors.error,
      title: S.of(context).gitNoRepoDetected,
      description: '${git.error}\n${S.of(context).gitNoRepoHint}',
      action: AppButton(
        label: isLoading ? S.of(context).gitChecking : S.of(context).gitRecheck,
        icon: isLoading ? Icons.hourglass_top : Icons.refresh_rounded,
        onTap: isLoading ? null : () {
          setState(() { resetLoading(); });
          startLoadingTimeout();
          git.refresh();
        },
      ),
    );
  }

  Widget _buildRepoSelector(GitStateProvider git) {
    final colors = context.colors;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.folder_copy, size: 20, color: colors.secondary),
              const SizedBox(width: 8),
              Text(S.of(context).gitFoundRepos(git.repos.length),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Divider(height: 1, color: colors.border),
        Expanded(
          child: ListView.builder(
            itemCount: git.repos.length,
            itemBuilder: (context, index) {
              final repo = git.repos[index];
              final name = repo['name'] as String? ?? '';
              final relPath = repo['relative_path'] as String? ?? '';
              final branch = repo['branch'] as String? ?? '';
              final isCurrent = repo['is_current'] == true;
              return ListTile(
                leading: Icon(
                  isCurrent ? Icons.folder_open : Icons.folder_outlined,
                  color: isCurrent ? colors.secondary : colors.onSurfaceMuted,
                ),
                title: Text(name, style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  color: isCurrent ? colors.onSurface : colors.onSurfaceVariant,
                )),
                subtitle: Text(
                  branch.isNotEmpty ? '$relPath · $branch' : relPath,
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceMuted),
                ),
                trailing: isCurrent
                    ? Icon(Icons.check, size: 18, color: colors.secondary)
                    : Icon(Icons.chevron_right, size: 18, color: colors.onSurfaceMuted),
                onTap: () {
                  final path = repo['path'] as String? ?? '';
                  if (path.isNotEmpty) git.switchRepo(path);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showFileDiff(String path, {required bool staged}) {
    final ws = context.read<WebSocketService>();
    context.read<GitOperations>().gitDiffFile(path, staged: staged);

    late StreamSubscription sub;
    sub = ws.messageStream.listen((msg) {
      if (msg.type == MessageType.gitDiffResult) {
        sub.cancel();
        if (!mounted) return;
        final p = GitDiffResultPayload.fromJson(msg.payload);
        final oldContent = p.oldContent ?? '';
        final newContent = p.newContent ?? '';
        final error = p.error ?? '';
        if (error.isNotEmpty) {
          AppToast.show(context, error, type: AppToastType.error);
          return;
        }
        if (oldContent.isEmpty && newContent.isEmpty) return;
        Navigator.push(context, AppPageRoute(
          type: PageTransitionType.slideUp,
          page: DiffViewerScreen(filePath: path, oldCode: oldContent, newCode: newContent, showAcceptReject: false),
        ));
      }
    });
  }

  void _confirmDiscard(String path) {
    final colors = context.colors;
    final git = context.read<GitStateProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(S.of(context).gitDiscardTitle, style: TextStyle(fontSize: 16)),
        content: Text(S.of(context).gitDiscardMessage(path),
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).commonCancel, style: TextStyle(color: colors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              git.discard(path);
            },
            child: Text(S.of(context).gitDiscard, style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }

  void _showRepoSwitcher() {
    final colors = context.colors;
    final git = context.read<GitStateProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(S.of(context).gitSwitchRepo(git.repos.length),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: git.repos.length,
                itemBuilder: (ctx, i) {
                  final repo = git.repos[i];
                  final name = repo['name'] as String? ?? '';
                  final branch = repo['branch'] as String? ?? '';
                  final relPath = repo['relative_path'] as String? ?? '';
                  final isCurrent = repo['is_current'] == true;
                  return ListTile(
                    leading: Icon(
                      isCurrent ? Icons.folder_open : Icons.folder_outlined,
                      color: isCurrent ? colors.secondary : colors.onSurfaceMuted,
                    ),
                    title: Text(name, style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                    )),
                    subtitle: Text(
                      branch.isNotEmpty ? '$relPath · $branch' : relPath,
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceMuted),
                    ),
                    trailing: isCurrent ? Icon(Icons.check, size: 18, color: colors.secondary) : null,
                    onTap: isCurrent ? null : () {
                      Navigator.pop(ctx);
                      git.switchRepo(repo['path'] as String? ?? '');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBranchPicker() {
    final colors = context.colors;
    final git = context.read<GitStateProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(S.of(context).gitSwitchBranch, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: git.branches.length,
                itemBuilder: (ctx, i) {
                  final b = git.branches[i];
                  final name = b['name'] as String? ?? '';
                  final current = b['current'] == true;
                  final remote = b['remote'] == true;
                  return ListTile(
                    leading: Icon(
                      current ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: current ? colors.primary : colors.onSurfaceVariant,
                      size: 20,
                    ),
                    title: Text(name, style: TextStyle(
                      fontSize: 13,
                      color: remote ? colors.onSurfaceVariant : null,
                    )),
                    trailing: remote
                        ? Text('remote', style: TextStyle(fontSize: 10, color: colors.onSurfaceMuted))
                        : null,
                    onTap: current ? null : () {
                      Navigator.pop(ctx);
                      git.checkout(name);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    disposeLoading();
    _resultSub?.cancel();
    _tabController.dispose();
    _commitController.dispose();
    _shellController.dispose();
    super.dispose();
  }
}
