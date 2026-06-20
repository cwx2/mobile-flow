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

import '../components/app_dialog.dart';
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
        if (commitRepo.isNotEmpty &&
            commitRepo.replaceAll('\\', '/') != widget.repoPath.replaceAll('\\', '/')) break;
        final p = GitCommitResultPayload.fromJson(msg.payload);
        if ((p.error ?? '').isNotEmpty) {
          final hookFailed = msg.payload['hook_failed'] as bool? ?? false;
          if (hookFailed) {
            _showForceCommitDialog(p.error!);
          } else {
            AppToast.show(context, p.error!, type: AppToastType.error);
          }
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
      case MessageType.gitCheckoutResult:
        final checkoutRepo = msg.payload['repo'] as String? ?? '';
        if (checkoutRepo.isNotEmpty && checkoutRepo != widget.repoPath) break;
        final p = GitCheckoutResultPayload.fromJson(msg.payload);
        if ((p.error ?? '').isNotEmpty) {
          AppToast.show(context, p.error!, type: AppToastType.error);
        } else {
          AppToast.show(context, S.of(context).gitCheckoutSuccess,
              type: AppToastType.success);
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
            GestureDetector(
              onTap: () => _showBranchPicker(context, git, repo.branch),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.alt_route, size: 14, color: colors.secondary),
                    const SizedBox(width: 4),
                    Text(repo.branch,
                        style: TextStyle(fontSize: 12, color: colors.secondary)),
                  ],
                ),
              ),
            ),
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

  void _showForceCommitDialog(String error) async {
    final confirmed = await showAppErrorActionDialog(
      context,
      title: S.of(context).gitHookFailedTitle,
      error: error,
      description: S.of(context).gitHookFailedMessage,
      actionLabel: S.of(context).gitForceCommit,
      cancelLabel: S.of(context).commonCancel,
    );
    if (confirmed == true && mounted) {
      final ws = context.read<WebSocketService>();
      ws.gitOps.gitCommit(
        _commitController.text.trim(),
        repo: widget.repoPath,
        noVerify: true,
      );
    }
  }

  void _showBranchPicker(BuildContext context, GitStateProvider git, String currentBranch) {
    final colors = context.colors;
    final branches = git.branchesFor(widget.repoPath);

    // If branches not loaded yet, request them
    if (branches.isEmpty) {
      git.requestBranches(repo: widget.repoPath);
      AppToast.show(context, S.of(context).gitBranchesLoading);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      builder: (ctx) => _BranchPickerSheet(
        branches: branches,
        currentBranch: currentBranch,
        onSelect: (branchName) {
          Navigator.pop(ctx);
          if (branchName != currentBranch) {
            git.checkout(branchName, repo: widget.repoPath);
          }
        },
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

/// Bottom sheet for branch selection (VS Code style).
///
/// Shows search, local branches (with ahead/behind, commit info),
/// and remote branches grouped separately.
class _BranchPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> branches;
  final String currentBranch;
  final ValueChanged<String> onSelect;

  const _BranchPickerSheet({
    required this.branches,
    required this.currentBranch,
    required this.onSelect,
  });

  @override
  State<_BranchPickerSheet> createState() => _BranchPickerSheetState();
}

class _BranchPickerSheetState extends State<_BranchPickerSheet> {
  String _filter = '';

  List<Map<String, dynamic>> get _localBranches => widget.branches
      .where((b) => (b['type'] as String? ?? 'branch') == 'branch')
      .where(_matchesFilter)
      .toList();

  List<Map<String, dynamic>> get _remoteBranches => widget.branches
      .where((b) => (b['type'] as String? ?? '') == 'remote')
      .where(_matchesFilter)
      .toList();

  List<Map<String, dynamic>> get _tags => widget.branches
      .where((b) => (b['type'] as String? ?? '') == 'tag')
      .where(_matchesFilter)
      .toList();

  bool _matchesFilter(Map<String, dynamic> b) {
    if (_filter.isEmpty) return true;
    final name = (b['name'] as String? ?? '').toLowerCase();
    final msg = (b['message'] as String? ?? '').toLowerCase();
    final q = _filter.toLowerCase();
    return name.contains(q) || msg.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final local = _localBranches;
    final remote = _remoteBranches;
    final tags = _tags;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle bar
        const SizedBox(height: 8),
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: colors.onSurfaceMuted.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Search field
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            autofocus: widget.branches.length > 5,
            decoration: InputDecoration(
              hintText: S.of(context).gitBranchSearchHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: colors.background,
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        // Branch list
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              // Local branches section
              if (local.isNotEmpty) ...[
                _sectionHeader(context, S.of(context).gitBranchLocal),
                ...local.map((b) => _branchTile(context, b, isRemote: false)),
              ],
              // Remote branches section
              if (remote.isNotEmpty) ...[
                _sectionHeader(context, S.of(context).gitBranchRemote),
                ...remote.map((b) => _branchTile(context, b, isRemote: true)),
              ],
              // Tags section
              if (tags.isNotEmpty) ...[
                _sectionHeader(context, S.of(context).gitBranchTag),
                ...tags.map((b) => _branchTile(context, b, isRemote: false, isTag: true)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceMuted,
              letterSpacing: 0.5)),
    );
  }

  Widget _branchTile(BuildContext context, Map<String, dynamic> branch,
      {required bool isRemote, bool isTag = false}) {
    final colors = context.colors;
    final name = branch['name'] as String? ?? '';
    final isCurrent = branch['current'] as bool? ?? false;
    final hash = branch['hash'] as String? ?? '';
    final message = branch['message'] as String? ?? '';
    final author = branch['author'] as String? ?? '';
    final date = branch['date'] as String? ?? '';
    final ahead = branch['ahead'] as int? ?? 0;
    final behind = branch['behind'] as int? ?? 0;

    return InkWell(
      onTap: () => widget.onSelect(name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: isCurrent ? colors.secondary.withValues(alpha: 0.08) : null,
        child: Row(
          children: [
            // Ref icon
            Icon(
              isTag ? Icons.sell_outlined
                  : isRemote ? Icons.cloud_outlined : Icons.alt_route,
              size: 16,
              color: isCurrent ? colors.secondary : colors.onSurfaceMuted,
            ),
            const SizedBox(width: 10),
            // Branch info (name + commit details)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // First line: name + ahead/behind + date
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                            color: isCurrent ? colors.secondary : colors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (ahead > 0 || behind > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${behind > 0 ? "$behind↓" : ""}${ahead > 0 ? "$ahead↑" : ""}',
                          style: TextStyle(fontSize: 11, color: colors.onSurfaceMuted),
                        ),
                      ],
                      if (date.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(date,
                            style: TextStyle(fontSize: 11, color: colors.onSurfaceMuted)),
                      ],
                    ],
                  ),
                  // Second line: author • hash • message
                  if (hash.isNotEmpty || message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          if (author.isNotEmpty) author,
                          if (hash.isNotEmpty) hash,
                          if (message.isNotEmpty) message,
                        ].join(' • '),
                        style: TextStyle(fontSize: 11, color: colors.onSurfaceMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            // Right label
            if (isCurrent)
              Text(isTag ? S.of(context).gitBranchTag
                  : isRemote ? S.of(context).gitBranchRemote
                  : S.of(context).gitBranchLocal,
                  style: TextStyle(fontSize: 11, color: colors.secondary)),
          ],
        ),
      ),
    );
  }
}
