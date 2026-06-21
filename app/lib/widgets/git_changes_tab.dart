/// git_changes_tab.dart — Multi-repo git changes view.
///
/// Module: widgets/
/// Responsibility:
///   Displays all repositories with their file changes in a scrollable list.
///   Each repository is a collapsible section showing staged/unstaged/untracked.
///   All repos visible simultaneously, no switching.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/repo_state.dart';
import '../screens/conflict_resolver_screen.dart';
import '../screens/repo_detail_screen.dart';
import '../services/git_state.dart';
import '../services/websocket_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';

/// Git changes tab: multi-repo aggregated view.
///
/// When [isMultiRepo] is true, renders all repos as collapsible sections.
/// When false (single repo), renders a flat list without repo header.
class GitChangesTab extends StatelessWidget {
  final List<RepoState> allRepos;
  final bool isMultiRepo;
  final WebSocketService ws;
  final void Function(String path, {required String repo, required bool staged}) onShowDiff;
  final void Function(String path) onConfirmDiscard;

  const GitChangesTab({
    super.key,
    required this.allRepos,
    required this.isMultiRepo,
    required this.ws,
    required this.onShowDiff,
    required this.onConfirmDiscard,
  });

  @override
  Widget build(BuildContext context) {
    if (allRepos.isEmpty) {
      return _buildCleanState(context);
    }

    return ListView.builder(
      itemCount: allRepos.length,
      itemBuilder: (context, index) {
        final repo = allRepos[index];
        return _RepoSection(
          repo: repo,
          initiallyExpanded: repo.hasChanges,
          showHeader: isMultiRepo,
          ws: ws,
          onShowDiff: onShowDiff,
          onConfirmDiscard: onConfirmDiscard,
        );
      },
    );
  }

  Widget _buildCleanState(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline,
              size: 40, color: colors.secondary.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(S.of(context).gitChangesClean,
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(S.of(context).gitChangesCleanDesc,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceMuted)),
        ],
      ),
    );
  }
}

/// Collapsible repository section.
class _RepoSection extends StatefulWidget {
  final RepoState repo;
  final bool initiallyExpanded;
  final bool showHeader;
  final WebSocketService ws;
  final void Function(String path, {required String repo, required bool staged}) onShowDiff;
  final void Function(String path) onConfirmDiscard;

  const _RepoSection({
    required this.repo,
    required this.initiallyExpanded,
    required this.showHeader,
    required this.ws,
    required this.onShowDiff,
    required this.onConfirmDiscard,
  });

  @override
  State<_RepoSection> createState() => _RepoSectionState();
}

class _RepoSectionState extends State<_RepoSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final repo = widget.repo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Repository header (hidden in single-repo mode)
        if (widget.showHeader)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceVariant.withValues(alpha: 0.3),
                border: Border(
                  bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  // Repo name
                  Expanded(
                    child: Text(
                      repo.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Branch
                  Icon(Icons.account_tree_outlined, size: 12, color: colors.onSurfaceMuted),
                  const SizedBox(width: 3),
                  Text(
                    repo.branch.isNotEmpty ? repo.branch : '-',
                    style: TextStyle(fontSize: 11, color: colors.onSurfaceMuted),
                  ),
                  const SizedBox(width: 8),
                  // Sync status
                  Icon(Icons.sync, size: 12, color: colors.onSurfaceMuted),
                  const SizedBox(width: 2),
                  Text(
                    '${repo.behind}↓ ${repo.ahead}↑',
                    style: TextStyle(fontSize: 10, color: colors.onSurfaceMuted),
                  ),
                  // Change count badge
                  if (repo.hasChanges) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: colors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${repo.totalChanges}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: colors.warning),
                      ),
                    ),
                  ],
                  // Enter detail page arrow
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RepoDetailScreen(repoPath: repo.path),
                      ));
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Icon(Icons.arrow_forward_ios, size: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Expanded file list
        if (_expanded || !widget.showHeader) ...[
          if (!repo.hasChanges && widget.showHeader)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 14, color: colors.secondary),
                  const SizedBox(width: 8),
                  Text(
                    S.of(context).gitChangesClean,
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceMuted),
                  ),
                ],
              ),
            )
          else ...[
            // Conflicts section (highest priority, shown first)
            if (repo.conflicted.isNotEmpty) ...[
              _SectionHeader(
                title: S.of(context).gitConflictsCount(repo.conflicted.length),
                color: colors.error,
                actionLabel: repo.operationState == 'cherry-pick'
                    ? S.of(context).gitConflictsAbortCherryPick
                    : repo.operationState == 'revert'
                        ? S.of(context).gitConflictsAbortRevert
                        : S.of(context).gitConflictsAbortMerge,
                onAction: () {
                  final git = context.read<GitStateProvider>();
                  if (repo.operationState == 'cherry-pick' ||
                      repo.operationState == 'revert') {
                    widget.ws.gitOps.gitSequencerAbort(repo: repo.path);
                  } else {
                    git.mergeAbort(repo: repo.path);
                  }
                },
              ),
              ...repo.conflicted.map((f) => _ConflictFileItem(
                    file: f,
                    repoPath: repo.path,
                    ws: widget.ws,
                  )),
            ],
            if (repo.staged.isNotEmpty) ...[
              _SectionHeader(
                title: S.of(context).gitChangesStagedCount(repo.staged.length),
                color: colors.secondary,
                actionLabel: S.of(context).gitChangesUnstageAll,
                onAction: () {
                  final git = context.read<GitStateProvider>();
                  git.unstageAll(repo: repo.path);
                },
              ),
              ...repo.staged.map((f) => _FileItem(
                    file: f,
                    staged: true,
                    repoPath: repo.path,
                    onTap: () => widget.onShowDiff(f['path'] as String? ?? '', repo: repo.path, staged: true),
                    onDiscard: null,
                  )),
            ],
            if (repo.unstaged.isNotEmpty) ...[
              _SectionHeader(
                title: S.of(context).gitChangesUnstagedCount(repo.unstaged.length),
                color: colors.warning,
                actionLabel: S.of(context).gitChangesStageAll,
                onAction: () {
                  final git = context.read<GitStateProvider>();
                  git.stageAll(repo: repo.path);
                },
              ),
              ...repo.unstaged.map((f) => _FileItem(
                    file: f,
                    staged: false,
                    repoPath: repo.path,
                    onTap: () => widget.onShowDiff(f['path'] as String? ?? '', repo: repo.path, staged: false),
                    onDiscard: () => widget.onConfirmDiscard(f['path'] as String? ?? ''),
                  )),
            ],
            if (repo.untracked.isNotEmpty) ...[
              _SectionHeader(
                title: S.of(context).gitChangesUntrackedCount(repo.untracked.length),
                color: colors.onSurfaceVariant,
                actionLabel: S.of(context).gitChangesAddAll,
                onAction: () {
                  final git = context.read<GitStateProvider>();
                  final paths = repo.untracked.map((f) => f['path'] as String).toList();
                  git.stage(paths, repo: repo.path);
                },
              ),
              ...repo.untracked.map((f) => _FileItem(
                    file: f,
                    staged: false,
                    untracked: true,
                    repoPath: repo.path,
                    onTap: () => widget.onShowDiff(f['path'] as String? ?? '', repo: repo.path, staged: false),
                    onDiscard: null,
                  )),
            ],
          ],
        ],
      ],
    );
  }
}

/// Single conflict file item — taps navigate to ConflictResolverScreen.
class _ConflictFileItem extends StatelessWidget {
  final Map<String, dynamic> file;
  final String repoPath;
  final WebSocketService ws;

  const _ConflictFileItem({
    required this.file,
    required this.repoPath,
    required this.ws,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final path = file['path'] as String? ?? '';
    final fileName = path.split('/').last;
    final dirPath = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ConflictResolverScreen(
            repoPath: repoPath,
            filePath: path,
          ),
        ));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.05),
        ),
        child: Row(
          children: [
            // Conflict warning icon
            Icon(Icons.warning_amber_rounded, size: 18, color: colors.error),
            const SizedBox(width: 8),
            // Filename + directory path
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fileName,
                      style: TextStyle(fontSize: 13, color: colors.onSurface)),
                  if (dirPath.isNotEmpty)
                    Text(dirPath,
                        style: TextStyle(fontSize: 10, color: colors.onSurfaceMuted)),
                ],
              ),
            ),
            // Navigate arrow
            Icon(Icons.chevron_right, size: 18, color: colors.onSurfaceMuted),
          ],
        ),
      ),
    );
  }
}

/// Section header with title and optional action button.
class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  final String actionLabel;
  final VoidCallback onAction;

  const _SectionHeader({
    required this.title,
    required this.color,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          const Spacer(),
          InkWell(
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(actionLabel,
                  style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single file item with status icon and action buttons.
class _FileItem extends StatelessWidget {
  final Map<String, dynamic> file;
  final bool staged;
  final bool untracked;
  final String repoPath;
  final VoidCallback onTap;
  final VoidCallback? onDiscard;

  const _FileItem({
    required this.file,
    required this.staged,
    this.untracked = false,
    required this.repoPath,
    required this.onTap,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final path = file['path'] as String? ?? '';
    final status = file['status'] as String? ?? '';
    final statusColor = _getStatusColor(status, colors);
    final fileName = path.split('/').last;
    final dirPath = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Status letter badge
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              child: Text(status.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)),
            ),
            const SizedBox(width: 8),
            // Filename + directory path
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fileName, style: const TextStyle(fontSize: 13)),
                  if (dirPath.isNotEmpty)
                    Text(dirPath,
                        style: TextStyle(fontSize: 10, color: colors.onSurfaceMuted)),
                ],
              ),
            ),
            // Action buttons
            if (!untracked) ...[
              if (staged)
                _actionIcon(context, Icons.remove_circle_outline, colors.warning,
                    () {
                  final git = context.read<GitStateProvider>();
                  git.unstageFiles([path], repo: repoPath);
                })
              else ...[
                _actionIcon(context, Icons.add_circle_outline, colors.secondary,
                    () {
                  final git = context.read<GitStateProvider>();
                  git.stage([path], repo: repoPath);
                }),
                if (onDiscard != null)
                  _actionIcon(context, Icons.undo, colors.error, onDiscard!),
              ],
            ] else
              _actionIcon(context, Icons.add_circle_outline, colors.secondary,
                  () {
                final git = context.read<GitStateProvider>();
                git.stage([path], repo: repoPath);
              }),
          ],
        ),
      ),
    );
  }

  Widget _actionIcon(BuildContext context, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }

  static Color _getStatusColor(String status, dynamic colors) {
    switch (status.toUpperCase()) {
      case 'M':
        return colors.warning;
      case 'A':
        return colors.secondary;
      case 'D':
        return colors.error;
      case 'R':
        return colors.primary;
      default:
        return colors.onSurfaceVariant;
    }
  }
}
