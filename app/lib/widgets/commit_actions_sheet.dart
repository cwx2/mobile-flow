/// commit_actions_sheet.dart — Shared commit action bottom sheet.
///
/// Provides a reusable long-press action menu for commits, used by both
/// GitCommitTab (recent commits) and GitLogTab (history). Extracts common
/// operations: copy hash, cherry-pick, revert, view details.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../animation/page_transition_builder.dart';
import '../components/app_bottom_sheet.dart';
import '../components/app_dialog.dart';
import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../screens/commit_detail_screen.dart';
import '../services/ws_operations/git_operations.dart';
import '../theme/theme_extensions.dart';

/// Show the commit actions bottom sheet.
///
/// [hash]: full commit hash.
/// [shortHash]: abbreviated hash for display.
/// [message]: commit message.
/// [repo]: repository path.
/// [showUndo]: whether to show "Undo Commit" option (only for outgoing commits).
/// [onUndo]: callback when undo is selected (caller handles undo logic).
void showCommitActionsSheet(
  BuildContext context, {
  required String hash,
  required String shortHash,
  required String message,
  required String repo,
  bool showUndo = false,
  VoidCallback? onUndo,
}) {
  final colors = context.colors;
  final l = S.of(context);

  AppBottomSheet.show(context, builder: (ctx) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Commit info header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(shortHash,
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace',
                      color: colors.onSurfaceMuted)),
            ],
          ),
        ),
        const Divider(height: 1),

        // Copy commit hash
        _ActionTile(
          icon: Icons.copy,
          title: l.gitCopyHash,
          color: colors.onSurfaceVariant,
          onTap: () {
            Navigator.pop(ctx);
            Clipboard.setData(ClipboardData(text: hash));
            AppToast.show(context, l.commonCopied);
          },
        ),

        // Cherry-pick
        _ActionTile(
          icon: Icons.content_copy_rounded,
          title: l.gitCherryPick,
          color: colors.success,
          onTap: () {
            Navigator.pop(ctx);
            _confirmCherryPick(context, repo: repo, hash: hash);
          },
        ),

        // Undo commit (only for outgoing/latest)
        if (showUndo && onUndo != null)
          _ActionTile(
            icon: Icons.undo,
            title: l.gitUndoCommitSoft.replaceAll(' (--soft)', ''),
            color: colors.warning,
            onTap: () {
              Navigator.pop(ctx);
              onUndo();
            },
          ),

        // Revert commit
        _ActionTile(
          icon: Icons.replay,
          title: l.gitRevertCommit,
          color: colors.primary,
          onTap: () {
            Navigator.pop(ctx);
            _showRevertOptions(context, repo: repo, hash: hash);
          },
        ),

        // Reset branch to here
        _ActionTile(
          icon: Icons.restart_alt,
          title: l.gitResetToHere,
          color: colors.warning,
          onTap: () {
            Navigator.pop(ctx);
            _showResetToHereOptions(context, repo: repo, hash: hash, shortHash: shortHash);
          },
        ),

        // View details
        _ActionTile(
          icon: Icons.info_outline,
          title: l.gitViewDetails,
          color: colors.onSurfaceVariant,
          onTap: () {
            Navigator.pop(ctx);
            Navigator.push(context, AppPageRoute(
              type: PageTransitionType.slideUp,
              page: CommitDetailScreen(
                commitHash: hash,
                shortHash: shortHash,
                message: message,
                repo: repo,
              ),
            ));
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  });
}

/// Confirm and execute cherry-pick.
void _confirmCherryPick(BuildContext context, {required String repo, required String hash}) {
  final l = S.of(context);
  final gitOps = context.read<GitOperations>();
  showAppConfirmDialog(
    context,
    title: l.gitCherryPick,
    message: l.gitCherryPickDesc,
    confirmLabel: l.gitCherryPickButton,
  ).then((confirmed) {
    if (confirmed != true || !context.mounted) return;
    gitOps.gitCherryPick(repo: repo, hash: hash);
    AppToast.show(context, l.gitCherryPickStarted, type: AppToastType.info);
  });
}

/// Revert options dialog (with no-commit checkbox).
void _showRevertOptions(BuildContext context, {required String repo, required String hash}) {
  final l = S.of(context);
  final gitOps = context.read<GitOperations>();
  showAppCheckConfirmDialog(
    context,
    title: l.gitRevertCommit,
    message: l.gitRevertCommitDesc,
    checkboxLabel: l.gitRevertNoCommitDesc,
    initialChecked: false,
  ).then((result) {
    if (result == null || !context.mounted) return;
    final noCommit = result.checked;
    gitOps.gitRevertCommit(repo: repo, hash: hash, noCommit: noCommit);
    final msg = noCommit ? l.gitRevertNoCommitDone : l.gitRevertInProgress;
    AppToast.show(context, msg, type: AppToastType.info);
  });
}

/// Reset-to-here mode selection + hard reset confirmation.
void _showResetToHereOptions(
  BuildContext context, {
  required String repo,
  required String hash,
  required String shortHash,
}) {
  final l = S.of(context);
  final gitOps = context.read<GitOperations>();

  showAppOptionsDialog<String>(
    context,
    title: l.gitResetToHere,
    message: l.gitResetToHereDesc(shortHash),
    options: [
      AppDialogOption(
        value: 'soft',
        title: '--soft',
        subtitle: l.gitUndoCommitSoftDesc,
      ),
      AppDialogOption(
        value: 'mixed',
        title: '--mixed',
        subtitle: l.gitUndoCommitMixedDesc,
      ),
      AppDialogOption(
        value: 'hard',
        title: '--hard',
        subtitle: l.gitUndoCommitHardDesc,
        isDanger: true,
      ),
    ],
    initialValue: 'mixed',
  ).then((selectedMode) {
    if (selectedMode == null || !context.mounted) return;
    if (selectedMode == 'hard') {
      showAppConfirmDialog(
        context,
        title: l.gitResetHardConfirmTitle,
        message: l.gitResetHardConfirmBody(shortHash),
        confirmLabel: l.gitResetHardConfirmButton,
        isDanger: true,
      ).then((confirmed) {
        if (confirmed != true || !context.mounted) return;
        gitOps.gitUndoCommit(repo: repo, mode: 'hard', target: hash);
        AppToast.show(context, l.gitResetDone(shortHash),
            type: AppToastType.error);
      });
    } else {
      gitOps.gitUndoCommit(repo: repo, mode: selectedMode, target: hash);
      AppToast.show(context, l.gitResetDone(shortHash),
          type: AppToastType.success);
    }
  });
}

/// Action tile for the bottom sheet.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      onTap: onTap,
    );
  }
}
