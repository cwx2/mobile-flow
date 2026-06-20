/// git_commit_tab.dart — Git commit form with message input and push/pull.
///
/// Module: widgets/
/// Responsibility:
///   Commit message input, staged files summary, commit button,
///   and push/pull action buttons.

import 'package:flutter/material.dart';

import '../animation/page_transition_builder.dart';
import '../screens/commit_detail_screen.dart';
import '../services/websocket_service.dart';
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

    return ListView(
      padding: const EdgeInsets.all(16),
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
              color:
                  hasStagedFiles ? colors.secondary : colors.onSurfaceMuted,
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

        // Recent commits section
        if (widget.recentCommits.isNotEmpty) ...[
          const SizedBox(height: 24),
          _RecentCommitsSection(
            commits: widget.recentCommits,
            ahead: widget.ahead,
            repo: widget.repo,
            branch: widget.branch,
          ),
        ],
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
    // Show at most 8 recent commits
    final display = commits.take(8).toList();
    final outgoing = display.take(ahead).toList();
    final synced = display.skip(ahead).toList();
    final localBranch = branch.isNotEmpty ? branch : 'HEAD';
    final remoteBranch = 'origin/$localBranch';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
}
