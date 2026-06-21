/// git_commit_tab.dart — Git commit form with message input and push/pull.
///
/// Module: widgets/
/// Responsibility:
///   Commit message input, staged files summary, commit button,
///   and push/pull action buttons.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../animation/page_transition_builder.dart';
import '../components/app_bottom_sheet.dart';
import '../components/app_dialog.dart';
import '../components/app_toast.dart';
import '../screens/commit_detail_screen.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/git_operations.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';

/// Git commit tab: message input + commit/push/pull buttons + recent commits.
class GitCommitTab extends StatefulWidget {
  final int stagedCount;
  final int ahead;
  final bool committing;
  final bool pushing;
  final bool pulling;
  final TextEditingController commitController;
  final WebSocketService ws;
  final VoidCallback onCommit;
  final VoidCallback onPush;
  final VoidCallback onPull;
  final List<Map<String, dynamic>> recentCommits;
  final String repo;
  final String branch;

  const GitCommitTab({
    super.key,
    required this.stagedCount,
    this.ahead = 0,
    required this.committing,
    required this.pushing,
    required this.pulling,
    required this.commitController,
    required this.ws,
    required this.onCommit,
    required this.onPush,
    required this.onPull,
    this.recentCommits = const [],
    this.repo = '',
    this.branch = '',
  });

  @override
  State<GitCommitTab> createState() => _GitCommitTabState();
}

class _GitCommitTabState extends State<GitCommitTab> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.commitController.text.trim().isNotEmpty;
    widget.commitController.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(GitCommitTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commitController != widget.commitController) {
      oldWidget.commitController.removeListener(_onTextChanged);
      widget.commitController.addListener(_onTextChanged);
      _hasText = widget.commitController.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    widget.commitController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final newHasText = widget.commitController.text.trim().isNotEmpty;
    if (newHasText != _hasText) {
      setState(() => _hasText = newHasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasStagedFiles = widget.stagedCount > 0;

    return Column(
      children: [
        // Fixed top section: staged summary + input + buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Staged files summary
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hasStagedFiles
                      ? colors.secondary.withValues(alpha: 0.08)
                      : colors.border.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasStagedFiles
                      ? S.of(context).gitCommitStagedReady(widget.stagedCount)
                      : S.of(context).gitCommitNoStaged,
                  style: TextStyle(
                    fontSize: 13,
                    color: hasStagedFiles ? colors.secondary : colors.onSurfaceMuted,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Commit message input
              TextField(
                controller: widget.commitController,
                maxLines: 4,
                minLines: 2,
                decoration: InputDecoration(
                  hintText: S.of(context).gitCommitMessageHint,
                  hintStyle: TextStyle(color: colors.onSurfaceMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 16),

              // Commit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: hasStagedFiles && _hasText && !widget.committing
                      ? widget.onCommit
                      : null,
                  icon: widget.committing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check, size: 18),
                  label: Text(S.of(context).gitCommitButton),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.secondary,
                    foregroundColor: colors.background,
                    disabledBackgroundColor: colors.border,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Push + Pull button row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.pulling ? null : widget.onPull,
                      icon: widget.pulling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download, size: 16),
                      label: Text(widget.pulling ? S.of(context).gitCommitPulling : 'Pull'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(color: colors.border),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.pushing || widget.ahead == 0 ? null : widget.onPush,
                      icon: widget.pushing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload, size: 16),
                      label: Text(widget.pushing ? S.of(context).gitCommitPushing : 'Push'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(color: colors.border),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Scrollable recent commits section (fills remaining space)
        if (widget.recentCommits.isNotEmpty)
          Expanded(
            child: _RecentCommitsSection(
              commits: widget.recentCommits,
              ahead: widget.ahead,
              repo: widget.repo,
              branch: widget.branch,
            ),
          )
        else
          const Spacer(),
      ],
    );
  }
}

/// Displays recent commits with outgoing (unpushed) commits highlighted.
///
/// VS Code style: local unpushed commits show "main" badge,
/// remote-synced commits show "origin/main" badge, with visual separator.
class _RecentCommitsSection extends StatelessWidget {
  final List<Map<String, dynamic>> commits;
  final int ahead;
  final String repo;
  final String branch;

  const _RecentCommitsSection({
    required this.commits,
    required this.ahead,
    required this.repo,
    required this.branch,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Show recent commits (enough to fill the screen)
    final display = commits.take(20).toList();
    final outgoing = display.take(ahead).toList();
    final synced = display.skip(ahead).toList();
    final localBranch = branch.isNotEmpty ? branch : 'HEAD';
    final remoteBranch = 'origin/$localBranch';

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Outgoing section (local, not yet pushed)
        if (outgoing.isNotEmpty) ...[
          _SectionLabel(
            icon: Icons.arrow_upward,
            label: S.of(context).gitOutgoingCommits(outgoing.length),
            color: colors.secondary,
          ),
          ...outgoing.indexed.map((e) => _CommitRow(
            commit: e.$2,
            isOutgoing: true,
            isFirst: e.$1 == 0,
            isLast: e.$1 == outgoing.length - 1 && synced.isEmpty,
            badge: e.$1 == 0 ? localBranch : null,
            repo: repo,
          )),
        ],
        // Separator between local and remote
        if (outgoing.isNotEmpty && synced.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                Container(width: 8, height: 1, color: colors.border),
                const SizedBox(width: 8),
                Icon(Icons.cloud_outlined, size: 12, color: colors.onSurfaceMuted),
                const SizedBox(width: 4),
                Text(remoteBranch,
                    style: TextStyle(fontSize: 10, color: colors.onSurfaceMuted)),
                const SizedBox(width: 8),
                Expanded(child: Container(height: 1, color: colors.border)),
              ],
            ),
          ),
        // Synced section (already on remote)
        if (synced.isNotEmpty) ...[
          if (outgoing.isEmpty)
            _SectionLabel(
              icon: Icons.check_circle_outline,
              label: S.of(context).gitSyncedCommits,
              color: colors.onSurfaceMuted,
            ),
          ...synced.indexed.map((e) => _CommitRow(
            commit: e.$2,
            isOutgoing: false,
            isFirst: e.$1 == 0 && outgoing.isEmpty,
            isLast: e.$1 == synced.length - 1,
            badge: e.$1 == 0 && outgoing.isNotEmpty ? remoteBranch : null,
            repo: repo,
          )),
        ],
      ],
    );
  }
}

/// Section label with icon and text.
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionLabel({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// A single commit row in the recent commits list.
/// Long-press shows undo/revert action sheet.
class _CommitRow extends StatelessWidget {
  final Map<String, dynamic> commit;
  final bool isOutgoing;
  final bool isFirst;
  final bool isLast;
  final String? badge;
  final String repo;

  const _CommitRow({
    required this.commit,
    required this.isOutgoing,
    this.isFirst = false,
    this.isLast = false,
    this.badge,
    required this.repo,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = commit['message'] as String? ?? '';
    final author = commit['author'] as String? ?? '';
    final date = commit['date'] as String? ?? '';
    final shortHash = commit['short_hash'] as String? ?? '';
    final hash = commit['hash'] as String? ?? '';

    return InkWell(
      onTap: hash.isEmpty ? null : () {
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
      onLongPress: hash.isEmpty ? null : () {
        _showCommitActions(context, hash, message);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline dot
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 10),
              child: Icon(
                isFirst ? Icons.radio_button_checked : Icons.circle,
                size: isFirst ? 10 : 8,
                color: isOutgoing ? colors.secondary : colors.onSurfaceMuted,
              ),
            ),
            // Commit info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Message line + badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(
                            fontSize: 13,
                            color: isOutgoing ? colors.onSurface : colors.onSurfaceMuted,
                            fontWeight: isOutgoing ? FontWeight.w500 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isOutgoing
                                ? colors.secondary.withValues(alpha: 0.15)
                                : colors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isOutgoing ? colors.secondary : colors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Author + hash + date
                  Text(
                    [author, shortHash, date].where((s) => s.isNotEmpty).join(' - '),
                    style: TextStyle(fontSize: 11, color: colors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
            // Chevron
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(Icons.chevron_right, size: 14, color: colors.onSurfaceMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _showCommitActions(BuildContext context, String hash, String message) {
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
                Text(hash.substring(0, 12),
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
            subtitle: null,
            color: colors.onSurfaceVariant,
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: hash));
              AppToast.show(context, l.commonCopied);
            },
          ),

          // Cherry-pick (apply this commit to current branch)
          _ActionTile(
            icon: Icons.content_copy_rounded,
            title: l.gitCherryPick,
            subtitle: null,
            color: colors.success,
            onTap: () {
              Navigator.pop(ctx);
              _confirmCherryPick(context, hash, l);
            },
          ),

          // Undo commit (only for outgoing/first commit)
          if (isOutgoing && isFirst)
            _ActionTile(
              icon: Icons.undo,
              title: l.gitUndoCommitSoft.replaceAll(' (--soft)', ''),
              subtitle: null,
              color: colors.warning,
              onTap: () {
                Navigator.pop(ctx);
                _showUndoOptions(context, l);
              },
            ),

          // Revert commit (available for any commit)
          _ActionTile(
            icon: Icons.replay,
            title: l.gitRevertCommit,
            subtitle: null,
            color: colors.primary,
            onTap: () {
              Navigator.pop(ctx);
              _showRevertOptions(context, hash, l);
            },
          ),

          // View details
          _ActionTile(
            icon: Icons.info_outline,
            title: l.gitViewDetails,
            subtitle: null,
            color: colors.onSurfaceVariant,
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, AppPageRoute(
                type: PageTransitionType.slideUp,
                page: CommitDetailScreen(
                  commitHash: hash,
                  shortHash: hash.substring(0, 7),
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

  /// Confirm and execute cherry-pick operation.
  void _confirmCherryPick(BuildContext context, String hash, S l) {
    final gitOps = context.read<GitOperations>();
    showAppConfirmDialog(
      context,
      title: l.gitCherryPick,
      message: l.gitCherryPickDesc,
      confirmLabel: l.gitCherryPickButton,
    ).then((confirmed) {
      if (confirmed == true) {
        gitOps.gitCherryPick(repo: repo, hash: hash);
        AppToast.show(context, l.gitCherryPickStarted, type: AppToastType.info);
      }
    });
  }

  /// Second-level dialog: choose undo mode (soft/mixed/hard) then confirm.
  void _showUndoOptions(BuildContext context, S l) {
    final gitOps = context.read<GitOperations>();

    showAppOptionsDialog<String>(
      context,
      title: l.gitUndoCommitSoft.replaceAll(' (--soft)', ''),
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
      initialValue: 'soft',
    ).then((selectedMode) {
      if (selectedMode == null) return;
      if (selectedMode == 'hard') {
        _confirmHardReset(context, gitOps, l);
      } else {
        gitOps.gitUndoCommit(repo: repo, mode: selectedMode);
        final msg = selectedMode == 'soft'
            ? l.gitUndoCommitDoneSoft
            : l.gitUndoCommitDoneMixed;
        AppToast.show(context, msg, type: AppToastType.success);
      }
    });
  }

  /// Second-level dialog: choose revert options then confirm.
  void _showRevertOptions(BuildContext context, String hash, S l) {
    final gitOps = context.read<GitOperations>();

    showAppCheckConfirmDialog(
      context,
      title: l.gitRevertCommit,
      message: l.gitRevertCommitDesc,
      checkboxLabel: l.gitRevertNoCommitDesc,
      initialChecked: false,
    ).then((result) {
      if (result == null) return;
      final noCommit = result.checked;
      gitOps.gitRevertCommit(repo: repo, hash: hash, noCommit: noCommit);
      final msg = noCommit ? l.gitRevertNoCommitDone : l.gitRevertInProgress;
      AppToast.show(context, msg, type: AppToastType.info);
    });
  }

  void _confirmHardReset(BuildContext context, GitOperations gitOps, S l) {
    showAppConfirmDialog(
      context,
      title: l.gitUndoCommitHardConfirmTitle,
      message: l.gitUndoCommitHardConfirmBody,
      confirmLabel: l.gitUndoCommitHardConfirmButton,
      isDanger: true,
    ).then((confirmed) {
      if (confirmed == true) {
        gitOps.gitUndoCommit(repo: repo, mode: 'hard');
        AppToast.show(context, l.gitUndoCommitDoneHard,
            type: AppToastType.error);
      }
    });
  }
}

/// Action tile for the commit action bottom sheet.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color),
      title: Text(title, style: TextStyle(fontSize: 13, color: color)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 11))
          : null,
      onTap: onTap,
    );
  }
}
