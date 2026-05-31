/// git_changes_tab.dart — Git changed files list (staged/unstaged/untracked).
///
/// Module: widgets/
/// Responsibility:
///   Displays categorized file change lists with stage/unstage/discard actions.
///   Each file item shows status icon, path, and action buttons.

import 'package:flutter/material.dart';

import '../services/websocket_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';

/// Git changes tab: staged + unstaged + untracked file lists.
///
/// Callbacks are used for actions that require parent coordination
/// (diff viewing, discard confirmation).
class GitChangesTab extends StatelessWidget {
  final List<Map<String, dynamic>> staged;
  final List<Map<String, dynamic>> unstaged;
  final List<Map<String, dynamic>> untracked;
  final WebSocketService ws;
  final void Function(String path, {required bool staged}) onShowDiff;
  final void Function(String path) onConfirmDiscard;

  const GitChangesTab({
    super.key,
    required this.staged,
    required this.unstaged,
    required this.untracked,
    required this.ws,
    required this.onShowDiff,
    required this.onConfirmDiscard,
  });

  @override
  Widget build(BuildContext context) {
    if (staged.isEmpty && unstaged.isEmpty && untracked.isEmpty) {
      final colors = context.colors;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 40, color: colors.secondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(S.of(context).gitChangesClean,
                style: TextStyle(
                    fontSize: 14, color: colors.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(S.of(context).gitChangesCleanDesc,
                style: TextStyle(
                    fontSize: 12, color: colors.onSurfaceMuted)),
          ],
        ),
      );
    }

    final colors = context.colors;
    return ListView(
      children: [
        if (staged.isNotEmpty) ...[
          _SectionHeader(
            title: S.of(context).gitChangesStagedCount(staged.length),
            color: colors.secondary,
            actionLabel: S.of(context).gitChangesUnstageAll,
            onAction: () => ws.gitOps.gitUnstageAll(),
          ),
          ...staged.map((f) => _FileItem(
                file: f,
                staged: true,
                ws: ws,
                onTap: () => onShowDiff(f['path'] as String? ?? '', staged: true),
                onDiscard: null,
              )),
        ],
        if (unstaged.isNotEmpty) ...[
          _SectionHeader(
            title: S.of(context).gitChangesUnstagedCount(unstaged.length),
            color: colors.warning,
            actionLabel: S.of(context).gitChangesStageAll,
            onAction: () => ws.gitOps.gitStageAll(),
          ),
          ...unstaged.map((f) => _FileItem(
                file: f,
                staged: false,
                ws: ws,
                onTap: () =>
                    onShowDiff(f['path'] as String? ?? '', staged: false),
                onDiscard: () =>
                    onConfirmDiscard(f['path'] as String? ?? ''),
              )),
        ],
        if (untracked.isNotEmpty) ...[
          _SectionHeader(
            title: S.of(context).gitChangesUntrackedCount(untracked.length),
            color: colors.onSurfaceVariant,
            actionLabel: S.of(context).gitChangesAddAll,
            onAction: () {
              final paths =
                  untracked.map((f) => f['path'] as String).toList();
              ws.gitOps.gitStage(paths);
            },
          ),
          ...untracked.map((f) => _FileItem(
                file: f,
                staged: false,
                untracked: true,
                ws: ws,
                onTap: () =>
                    onShowDiff(f['path'] as String? ?? '', staged: false),
                onDiscard: null,
              )),
        ],
      ],
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
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          const Spacer(),
          InkWell(
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(actionLabel,
                  style: TextStyle(
                      fontSize: 11, color: colors.onSurfaceVariant)),
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
  final WebSocketService ws;
  final VoidCallback onTap;
  final VoidCallback? onDiscard;

  const _FileItem({
    required this.file,
    required this.staged,
    this.untracked = false,
    required this.ws,
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
    final dirPath =
        path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

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
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor)),
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
                        style: TextStyle(
                            fontSize: 10, color: colors.onSurfaceMuted)),
                ],
              ),
            ),
            // Action buttons
            if (!untracked) ...[
              if (staged)
                _actionIcon(Icons.remove_circle_outline, colors.warning,
                    () => ws.gitOps.gitUnstage([path]))
              else ...[
                _actionIcon(Icons.add_circle_outline, colors.secondary,
                    () => ws.gitOps.gitStage([path])),
                if (onDiscard != null)
                  _actionIcon(Icons.undo, colors.error, onDiscard!),
              ],
            ] else
              _actionIcon(Icons.add_circle_outline, colors.secondary,
                  () => ws.gitOps.gitStage([path])),
          ],
        ),
      ),
    );
  }

  Widget _actionIcon(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: color),
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
