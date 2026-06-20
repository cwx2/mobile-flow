/// git_commit_tab.dart — Git commit form with message input and push/pull.
///
/// Module: widgets/
/// Responsibility:
///   Commit message input, staged files summary, commit button,
///   and push/pull action buttons.

import 'package:flutter/material.dart';

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
          ),
        ],
      ],
    );
  }
}

/// Displays recent commits with outgoing (unpushed) commits highlighted.
class _RecentCommitsSection extends StatelessWidget {
  final List<Map<String, dynamic>> commits;
  final int ahead;

  const _RecentCommitsSection({
    required this.commits,
    required this.ahead,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Show at most 8 recent commits
    final display = commits.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        if (ahead > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.arrow_upward, size: 14, color: colors.secondary),
                const SizedBox(width: 4),
                Text(
                  S.of(context).gitOutgoingCommits(ahead),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.secondary,
                  ),
                ),
              ],
            ),
          ),
        // Commit list
        ...List.generate(display.length, (i) {
          final commit = display[i];
          final isOutgoing = i < ahead;
          return _CommitRow(commit: commit, isOutgoing: isOutgoing);
        }),
      ],
    );
  }
}

/// A single commit row in the recent commits list.
class _CommitRow extends StatelessWidget {
  final Map<String, dynamic> commit;
  final bool isOutgoing;

  const _CommitRow({required this.commit, required this.isOutgoing});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = commit['message'] as String? ?? '';
    final author = commit['author'] as String? ?? '';
    final date = commit['date'] as String? ?? '';
    final shortHash = commit['short_hash'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot + line
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Icon(
              Icons.circle,
              size: 8,
              color: isOutgoing ? colors.secondary : colors.onSurfaceMuted,
            ),
          ),
          // Commit info
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Message
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      color: isOutgoing ? colors.onSurface : colors.onSurfaceMuted,
                      fontWeight: isOutgoing ? FontWeight.w500 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Author + hash + date
                  Text(
                    [author, shortHash, date].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
