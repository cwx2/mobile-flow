/// pending_review_banner.dart — Floating banner for pending file edit reviews.
///
/// Shows a compact banner at the top of the chat screen when there are
/// unreviewed AI file edits. Expands to show a file list with Diff buttons
/// and batch Accept All / Reject All actions.
///
/// Data source: reads pending edits from [ChatStateMixin.messages] —
/// same data that [FileEditCard] uses, so state is always in sync.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../animation/page_transition_builder.dart';
import '../models/chat_message.dart';
import '../screens/diff_viewer_screen.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../theme/tokens/color_tokens.dart';
import '../utils/language_detect.dart';
import '../utils/logger.dart';

final _log = getLogger('PendingReview');

/// A pending file edit awaiting user review.
class PendingEdit {
  final String filePath;
  final FileEditEntry entry;
  final ContentBlock block;

  PendingEdit({
    required this.filePath,
    required this.entry,
    required this.block,
  });

  String get fileName => filePath.split('/').last;
}

/// Floating banner showing pending file edit count with expand/collapse.
class PendingReviewBanner extends StatefulWidget {
  const PendingReviewBanner({super.key});

  @override
  State<PendingReviewBanner> createState() => _PendingReviewBannerState();
}

class _PendingReviewBannerState extends State<PendingReviewBanner> {
  bool _expanded = false;

  /// Extract all pending edits from chat messages.
  List<PendingEdit> _getPendingEdits(WebSocketService ws) {
    final pending = <PendingEdit>[];
    for (final msg in ws.messages) {
      for (final block in msg.blocks) {
        if (block.type == BlockType.fileEdit && block.filePath != null) {
          for (final entry in block.editEntries) {
            if (entry.isPending) {
              pending.add(PendingEdit(
                filePath: block.filePath!,
                entry: entry,
                block: block,
              ));
            }
          }
        }
      }
    }
    return pending;
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final pending = _getPendingEdits(ws);

    if (pending.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.primary.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(pending, colors),
            if (_expanded) _buildFileList(pending, ws, colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(List<PendingEdit> pending, AppColorTokens colors) {
    // Group by file for display count
    final fileCount = pending.map((e) => e.filePath).toSet().length;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.rate_review_outlined, size: 16, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$fileCount file${fileCount > 1 ? 's' : ''} pending review',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurface,
                ),
              ),
            ),
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: colors.onSurfaceMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList(
      List<PendingEdit> pending, WebSocketService ws, AppColorTokens colors) {
    // Group edits by file path
    final grouped = <String, List<PendingEdit>>{};
    for (final edit in pending) {
      grouped.putIfAbsent(edit.filePath, () => []).add(edit);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        ...grouped.entries.map((entry) => _buildFileRow(
              entry.key, entry.value, ws, colors)),
        _buildActions(pending, ws, colors),
      ],
    );
  }

  Widget _buildFileRow(String filePath, List<PendingEdit> edits,
      WebSocketService ws, AppColorTokens colors) {
    final fileName = filePath.split('/').last;
    final totalAdded = edits.fold<int>(0, (sum, e) => sum + e.entry.linesAdded);
    final totalDeleted =
        edits.fold<int>(0, (sum, e) => sum + e.entry.linesDeleted);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 14, color: colors.onSurfaceMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              style: TextStyle(fontSize: 12, color: colors.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Change stats
          if (totalAdded > 0)
            Text('+$totalAdded ',
                style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50))),
          if (totalDeleted > 0)
            Text('-$totalDeleted ',
                style: const TextStyle(fontSize: 11, color: Color(0xFFE57373))),
          const SizedBox(width: 4),
          // Diff button
          GestureDetector(
            onTap: () => _openDiff(edits.last, ws),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('Diff',
                  style: TextStyle(fontSize: 11, color: colors.primary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
      List<PendingEdit> pending, WebSocketService ws, AppColorTokens colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _acceptAll(pending, ws),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Text('Accept All',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF4CAF50))),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => _rejectAll(pending, ws),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE57373).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Text('Reject All',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFE57373))),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openDiff(PendingEdit edit, WebSocketService ws) {
    final lang = detectLanguage(edit.filePath);
    Navigator.of(context).push(AppPageRoute(
      type: PageTransitionType.slideUp,
      page: DiffViewerScreen(
        filePath: edit.filePath,
        oldCode: edit.entry.oldContent,
        newCode: edit.entry.newContent,
        language: lang,
        showAcceptReject: true,
      ),
    ));
  }

  void _acceptAll(List<PendingEdit> pending, WebSocketService ws) {
    _log.info('Accept All: ${pending.length} edits');
    for (final edit in pending) {
      edit.entry.accepted = true;
      ws.fileOps.applyDiff(edit.filePath, edit.entry.newContent);
    }
    // Trigger UI rebuild via setState (Provider will pick up changes)
    setState(() => _expanded = false);
  }

  void _rejectAll(List<PendingEdit> pending, WebSocketService ws) {
    _log.info('Reject All: ${pending.length} edits');
    for (final edit in pending) {
      edit.entry.accepted = false;
      ws.fileOps.rejectDiff(edit.filePath);
    }
    setState(() => _expanded = false);
  }
}
