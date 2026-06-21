/// git_screen.dart — Git operations panel (multi-repo architecture).
///
/// Module: screens/
/// Responsibility:
///   Pure UI layer for Git operations. In multi-repo mode, displays all
///   repositories in a single scrollable list. Each repo section shows
///   its own status, changes, and action buttons.
///
/// Called by:
///   - HomeScreen bottom navigation Git tab
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_notification.dart';
import '../components/app_toast.dart';
import '../components/workbench_state_card.dart';
import '../l10n/app_localizations.dart';
import '../core/loading_state.dart';
import '../models/protocol.dart';
import '../models/payloads/git_payloads.g.dart';
import '../services/git_state.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../widgets/git_changes_tab.dart';
import 'diff_viewer_screen.dart';
import '../utils/logger.dart';

final _log = getLogger('GitScreen');

/// Git operations screen — multi-repo aggregated view.
class GitScreen extends StatefulWidget {
  const GitScreen({super.key});

  @override
  State<GitScreen> createState() => _GitScreenState();
}

class _GitScreenState extends State<GitScreen> with LoadingStateMixin {
  StreamSubscription? _resultSub;
  late final GitStateProvider _git;

  @override
  void initState() {
    super.initState();
    _git = context.read<GitStateProvider>();

    // Listen for operation results that need toast feedback
    final ws = context.read<WebSocketService>();
    _resultSub = ws.messageStream.listen(_onOperationResult);

    // Request initial data via provider
    if (!_git.isInitialized) {
      startLoadingTimeout();
      _git.requestInitialData();
    }
  }

  void _onOperationResult(WsMessage msg) {
    if (!mounted) return;

    switch (msg.type) {
      case MessageType.gitCommitResult:
        final p = GitCommitResultPayload.fromJson(msg.payload);
        final err = p.error ?? '';
        final hookFailed = msg.payload['hook_failed'] as bool? ?? false;
        if (err.isNotEmpty && !hookFailed) {
          _showError(err, title: 'Commit failed');
        }

      case MessageType.gitPushResult:
        final p = GitPushResultPayload.fromJson(msg.payload);
        final err = p.error ?? '';
        if (err.isNotEmpty) {
          _showError(err, title: 'Push failed');
        } else if (p.upToDate) {
          AppToast.show(context, S.of(context).gitPushUpToDate);
        } else if (err.isEmpty) {
          AppToast.show(context, S.of(context).gitPushSuccess);
        }

      case MessageType.gitPullResult:
        final p = GitPullResultPayload.fromJson(msg.payload);
        final err = p.error ?? '';
        if (err.isNotEmpty) {
          _showError(err, title: 'Pull failed');
        } else if (p.upToDate) {
          AppToast.show(context, S.of(context).gitPullUpToDate);
        } else if (err.isEmpty) {
          AppToast.show(context, S.of(context).gitPullSuccess);
        }

      case MessageType.gitExecResult:
        final p = GitExecResultPayload.fromJson(msg.payload);
        if (p.success) {
          AppToast.show(context, S.of(context).gitExecSuccess, type: AppToastType.success);
        }

      case MessageType.gitCherryPickResult:
        final success = msg.payload['success'] as bool? ?? false;
        final hasConflicts = msg.payload['has_conflicts'] as bool? ?? false;
        final isEmpty = msg.payload['is_empty'] as bool? ?? false;
        final error = msg.payload['error'] as String? ?? '';
        if (success) {
          AppToast.show(context, S.of(context).gitCherryPickSuccess, type: AppToastType.success);
        } else if (hasConflicts) {
          AppNotification.show(context,
            title: S.of(context).gitCherryPickConflict,
            detail: error.isNotEmpty ? error : null,
            type: AppNotificationType.error,
          );
        } else if (isEmpty) {
          AppToast.show(context, S.of(context).gitCherryPickEmpty, type: AppToastType.info);
        } else if (error.isNotEmpty) {
          AppNotification.show(context,
            title: 'Cherry-pick failed',
            detail: error,
            type: AppNotificationType.error,
          );
        }

      case MessageType.gitRevertCommitResult:
        final success = msg.payload['success'] as bool? ?? false;
        final hasConflicts = msg.payload['has_conflicts'] as bool? ?? false;
        final error = msg.payload['error'] as String? ?? '';
        if (success) {
          AppToast.show(context, S.of(context).gitRevertSuccess, type: AppToastType.success);
        } else if (hasConflicts) {
          AppNotification.show(context,
            title: S.of(context).gitRevertConflict,
            detail: error.isNotEmpty ? error : null,
            type: AppNotificationType.error,
          );
        } else if (error.isNotEmpty) {
          AppNotification.show(context,
            title: 'Revert failed',
            detail: error,
            type: AppNotificationType.error,
          );
        }

      default:
        break;
    }
  }

  /// Show error: short messages use toast, long/multi-line use persistent notification.
  void _showError(String error, {String? title}) {
    if (error.length > 80 || error.contains('\n')) {
      AppNotification.show(context,
        title: title ?? error.split('\n').first,
        detail: error,
        type: AppNotificationType.error,
      );
    } else {
      AppToast.show(context, error, type: AppToastType.error);
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

    // No project selected
    if (ws.currentProjectPath.isEmpty) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: _buildAppBar(colors, git),
        body: WorkbenchStateCard(
          icon: Icons.folder_off_outlined,
          title: S.of(context).gitNoWorkDir,
          description: S.of(context).gitNoWorkDirDescription,
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: _buildAppBar(colors, git),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: loadingError.isNotEmpty
            ? KeyedSubtree(
                key: const ValueKey('timeout'),
                child: _buildTimeoutState(git))
            : isLoading
                ? const KeyedSubtree(
                    key: ValueKey('loading'),
                    child: Center(child: CircularProgressIndicator()))
                : KeyedSubtree(
                    key: const ValueKey('content'),
                    child: GitChangesTab(
                      allRepos: git.allRepos,
                      isMultiRepo: true,
                      ws: context.read<WebSocketService>(),
                      onShowDiff: _showFileDiff,
                      onConfirmDiscard: _confirmDiscard,
                    ),
                  ),
      ),
    );
  }

  AppBar _buildAppBar(dynamic colors, GitStateProvider git) {
    return AppBar(
      backgroundColor: colors.surface,
      titleSpacing: 12,
      toolbarHeight: 44,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.commit, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            git.repoCount > 0
                ? 'Git · ${git.repoCount}'
                : 'Git',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (git.totalChanges > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${git.totalChanges}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.warning),
              ),
            ),
          ],
        ],
      ),
      actions: [
        IconButton(
          icon: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh, size: 20),
          onPressed: isLoading
              ? null
              : () {
                  _log.fine('手动刷新');
                  setState(() {
                    resetLoading();
                  });
                  startLoadingTimeout();
                  git.refresh();
                },
          tooltip: S.of(context).filesRefresh,
        ),
      ],
    );
  }

  Widget _buildTimeoutState(GitStateProvider git) {
    final colors = context.colors;
    return WorkbenchStateCard(
      icon: Icons.wifi_off_outlined,
      title: S.of(context).gitLoadTimeout,
      description: S.of(context).gitRecheck,
      action: TextButton(
        onPressed: () {
          setState(() {
            resetLoading();
          });
          startLoadingTimeout();
          git.refresh();
        },
        child: Text(S.of(context).commonRetry,
            style: TextStyle(color: colors.primary)),
      ),
    );
  }

  void _showFileDiff(String path, {required String repo, required bool staged}) {
    final ws = context.read<WebSocketService>();

    // Register listener BEFORE sending request to avoid race condition
    // (Agent may respond before listen() completes on fast connections)
    late StreamSubscription<WsMessage> sub;
    sub = ws.messageStream.listen((msg) {
      if (msg.type == MessageType.gitDiffResult) {
        sub.cancel();
        if (!mounted) return;
        final p = GitDiffResultPayload.fromJson(msg.payload);
        final oldContent = p.oldContent ?? '';
        final newContent = p.newContent ?? '';
        final error = p.error ?? '';
        if (error.isNotEmpty) {
          final message = error == 'binary'
              ? S.of(context).gitBinaryFileToast
              : error;
          AppToast.show(context, message, type: AppToastType.error);
          return;
        }
        if (oldContent.isEmpty && newContent.isEmpty) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DiffViewerScreen(
            filePath: path,
            oldCode: oldContent,
            newCode: newContent,
            showAcceptReject: false,
          ),
        ));
      }
    });

    ws.gitOps.gitDiffFile(path, repo: repo, staged: staged);
  }

  void _confirmDiscard(String path) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(S.of(context).gitDiscardTitle),
        content: Text(S.of(context).gitDiscardMessage(path)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Find which repo owns this file
              for (final repo in _git.allRepos) {
                final files = [...repo.unstaged, ...repo.untracked];
                if (files.any((f) => f['path'] == path)) {
                  _git.discard(path, repo: repo.path);
                  break;
                }
              }
            },
            child: Text(S.of(context).gitDiscard,
                style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _resultSub?.cancel();
    super.dispose();
  }
}
