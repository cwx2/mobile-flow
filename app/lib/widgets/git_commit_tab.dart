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

/// Git commit tab: message input + commit/push/pull buttons.
class GitCommitTab extends StatelessWidget {
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
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasStagedFiles = stagedCount > 0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  ? S.of(context).gitCommitStagedReady(stagedCount)
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
            controller: commitController,
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
              onPressed: hasStagedFiles &&
                      commitController.text.trim().isNotEmpty &&
                      !committing
                  ? onCommit
                  : null,
              icon: committing
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
                  onPressed: pulling ? null : onPull,
                  icon: pulling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download, size: 16),
                  label: Text(pulling ? S.of(context).gitCommitPulling : 'Pull'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.primary,
                    side: BorderSide(color: colors.border),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: pushing || ahead == 0 ? null : onPush,
                  icon: pushing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload, size: 16),
                  label: Text(pushing ? S.of(context).gitCommitPushing : 'Push'),
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
    );
  }
}
