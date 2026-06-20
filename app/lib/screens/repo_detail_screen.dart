/// repo_detail_screen.dart — Single repository detail view.
///
/// Module: screens/
/// Responsibility:
///   Full-featured git interface for one repository. Shows tabs for
///   changes, commit, shell, and history. All operations scoped to
///   the specific repo path passed in.
///
/// Navigation:
///   GitScreen (aggregated) → tap repo header → RepoDetailScreen
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../models/protocol.dart';
import '../models/payloads/git_payloads.g.dart';
import '../services/git_state.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../widgets/git_changes_tab.dart';
import '../widgets/git_commit_tab.dart';
import '../widgets/git_log_tab.dart';
import '../widgets/git_shell_tab.dart';
import 'diff_viewer_screen.dart';

/// Detail screen for a single repository with tabbed interface.
class RepoDetailScreen extends StatefulWidget {
  final String repoPath;

  const RepoDetailScreen({super.key, required this.repoPath});

  @override
  State<RepoDetailScreen> createState() => _RepoDetailScreenState();
}

class _RepoDetailScreenState extends State<RepoDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _commitController = TextEditingController();
  final _shellController = TextEditingController();
  StreamSubscription? _resultSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    final ws = context.read<WebSocketService>();
    _resultSub = ws.messageStream.listen(_onResult);

    // Request branches and log for this repo
    final git = context.read<GitStateProvider>();
    git.requestBranches(repo: widget.repoPath);
    git.requestLog(repo: widget.repoPath);
  }

  void _onResult(WsMessage msg) {
    if (!mounted) return;
    switch (msg.type) {
      case MessageType.gitCommitResult:
        // Filter: only handle results for THIS repo
        final commitRepo = msg.payload['repo'] as String? ?? '';
        if (commitRepo.isNotEmpty && commitRepo != widget.repoPath) break;
        final p = GitCommitResultPayload.fromJson(msg.payload);
        if ((p.error ?? '').isNotEmpty) {
          AppToast.show(context, p.error!, type: AppToastType.error);
        } else {
          _commitController.clear();
          AppToast.show(context, 'Committed', type: AppToastType.success);
        }
      case MessageType.gitPushResult:
        final pushRepo = msg.payload['repo'] as String? ?? '';
        if (pushRepo.isNotEmpty && pushRepo != widget.repoPath) break;
        final p = GitPushResultPayload.fromJson(msg.payload);
        if ((p.error ?? '').isNotEmpty) {
          AppToast.show(context, p.error!, type: AppToastType.error);
        } else if (p.upToDate) {
          AppToast.show(context, S.of(context).gitPushUpToDate);
        } else {
          AppToast.show(context, S.of(context).gitPushSuccess);
        }
      case MessageType.gitPullResult:
        final pullRepo = msg.payload['repo'] as String? ?? '';
        if (pullRepo.isNotEmpty && pullRepo != widget.repoPath) break;
        final p = GitPullResultPayload.fromJson(msg.payload);
        if ((p.error ?? '').isNotEmpty) {
          AppToast.show(context, p.error!, type: AppToastType.error);
        } else if (p.upToDate) {
          AppToast.show(context, S.of(context).gitPullUpToDate);
        } else {
          AppToast.show(context, S.of(context).gitPullSuccess);
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final git = context.watch<GitStateProvider>();
    final repo = git.getRepo(widget.repoPath);

    if (repo == null) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(backgroundColor: colors.surface, title: const Text('...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        titleSpacing: 0,
        toolbarHeight: 44,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(repo.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text(repo.branch,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceMuted)),
          ],
        ),
        actions: [
          // Pull
          IconButton(
            icon: Icon(Icons.download, size: 20,
                color: git.isPulling(widget.repoPath) ? colors.secondary : null),
            onPressed: git.isPulling(widget.repoPath)
                ? null
                : () => git.pull(repo: widget.repoPath),
            tooltip: repo.behind > 0 ? 'Pull (${repo.behind})' : 'Pull',
          ),
          // Push
          IconButton(
            icon: Icon(Icons.upload, size: 20,
                color: git.isPushing(widget.repoPath)
                    ? colors.secondary
                    : repo.ahead > 0 ? null : colors.onSurfaceMuted.withValues(alpha: 0.3)),
            onPressed: git.isPushing(widget.repoPath) || repo.ahead == 0
                ? null
                : () => git.push(repo: widget.repoPath),
            tooltip: repo.ahead > 0 ? 'Push (${repo.ahead})' : 'Push',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: TabBar(
            controller: _tabController,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: '${S.of(context).gitTabChanges} (${repo.totalChanges})'),
              Tab(text: S.of(context).gitTabCommit),
              const Tab(text: 'Shell'),
              Tab(text: '${S.of(context).gitTabHistory} (${git.logEntriesFor(widget.repoPath).length})'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Changes tab (single repo)
          GitChangesTab(
            allRepos: [repo],
            isMultiRepo: false,
            ws: context.read<WebSocketService>(),
            onShowDiff: _showDiff,
            onConfirmDiscard: _confirmDiscard,
          ),
          // Commit tab
          GitCommitTab(
            stagedCount: repo.staged.length,
            ahead: repo.ahead,
            committing: git.isCommitting(widget.repoPath),
            pushing: git.isPushing(widget.repoPath),
            pulling: git.isPulling(widget.repoPath),
            commitController: _commitController,
            ws: context.read<WebSocketService>(),
            onCommit: () => git.commit(_commitController.text.trim(), repo: widget.repoPath),
            onPush: () => git.push(repo: widget.repoPath),
            onPull: () => git.pull(repo: widget.repoPath),
          ),
          // Shell tab
          GitShellTab(
            history: git.shellHistoryFor(widget.repoPath),
            controller: _shellController,
            ws: context.read<WebSocketService>(),
          ),
          // Log tab
          GitLogTab(
            entries: git.logEntriesFor(widget.repoPath),
            branches: git.branchesFor(widget.repoPath),
            onCountChanged: (_) {},
          ),
        ],
      ),
    );
  }

  void _showDiff(String path, {required String repo, required bool staged}) {
    final ws = context.read<WebSocketService>();

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
    final git = context.read<GitStateProvider>();
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
              git.discard(path, repo: widget.repoPath);
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
    _tabController.dispose();
    _commitController.dispose();
    _shellController.dispose();
    super.dispose();
  }
}
