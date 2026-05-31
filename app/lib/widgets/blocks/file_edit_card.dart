/// file_edit_card.dart — File edit card (collapsible group).
///
/// Collapsible card for reviewing file edits within a chat turn:
/// - Collapsed header: filename + edit count + Diff button + expand/collapse
/// - Expanded: each entry as a row with index, change stats, status, Diff, Undo
/// - Accept All / Reject All buttons
///
/// One FileEditCard corresponds to all edits for a single file within one prompt turn.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../../animation/page_transition_builder.dart';
import '../../models/chat_message.dart';
import '../../models/context_reference.dart';
import '../../screens/diff_viewer_screen.dart';
import '../../screens/file_viewer_screen.dart';
import '../../services/websocket_service.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/logger.dart';

final _log = getLogger('FileEditCard');

class FileEditCard extends StatefulWidget {
  final ContentBlock block;
  const FileEditCard({super.key, required this.block});

  @override
  State<FileEditCard> createState() => _FileEditCardState();
}

class _FileEditCardState extends State<FileEditCard> {
  bool _expanded = true; // expanded by default

  ContentBlock get block => widget.block;
  List<FileEditEntry> get entries => block.editEntries;
  String get fileName => (block.filePath ?? '').split('/').last;
  bool get allResolved =>
      entries.isNotEmpty && entries.every((e) => !e.isPending);
  int get pendingCount => entries.where((e) => e.isPending).length;

  @override
  Widget build(BuildContext context) {
    final ws = context.read<WebSocketService>();
    final colors = context.colors;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: allResolved ? colors.surfaceDim : colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: allResolved ? colors.borderSubtle : colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(ws),
          if (_expanded) ...[
            if (block.filePath != null) _filePath(),
            ...entries
                .asMap()
                .entries
                .map((e) => _entryRow(e.key, e.value, ws)),
            if (pendingCount > 0) _actions(ws),
          ],
        ],
      ),
    );
  }

  /// Collapsed header: filename + edit count + expand/collapse.
  Widget _header(WebSocketService ws) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: allResolved ? colors.surfaceVariant : colors.surfaceVariant,
          borderRadius: _expanded
              ? const BorderRadius.vertical(top: Radius.circular(8))
              : BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(_expanded ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: allResolved ? colors.onSurfaceMuted : colors.primary),
            const SizedBox(width: 4),
            // Edit count
            Text(
              '${entries.length} edit${entries.length > 1 ? 's' : ''} to file',
              style: TextStyle(
                  fontSize: 11,
                  color: allResolved
                      ? colors.onSurfaceMuted
                      : colors.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            // Filename
            Expanded(
              child: Text(
                '📄 $fileName',
                style: TextStyle(
                  fontSize: 13,
                  color: allResolved ? colors.onSurfaceMuted : colors.primary,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Diff button (shows latest full diff)
            if (!allResolved)
              GestureDetector(
                onTap: () => _openDiff(context, entries.last, ws),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Diff',
                      style: TextStyle(fontSize: 10, color: colors.primary)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// File path row: tap path to navigate, tap + icon to add to context.
  Widget _filePath() {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(children: [
        // Tap path text to open file viewer
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(AppPageRoute(
              type: PageTransitionType.slideUp,
              page: FileViewerScreen(filePath: block.filePath!),
            )),
            child: Row(children: [
              Icon(Icons.open_in_new, size: 10, color: colors.secondary),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(block.filePath!,
                      style: TextStyle(
                          fontSize: 10,
                          color: colors.secondary,
                          fontFamily: 'monospace',
                          decoration: TextDecoration.underline,
                          decorationColor: colors.secondary))),
            ]),
          ),
        ),
        // Tap + icon to add file to pending context references
        GestureDetector(
          onTap: () => _addFileToContext(block.filePath!),
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.add_link, size: 14, color: colors.secondary),
          ),
        ),
      ]),
    );
  }

  /// Add a file path to pending context references with toast feedback.
  void _addFileToContext(String path) {
    final ref = ContextReference(type: ContextRefType.files, path: path);
    context.read<WebSocketService>().addContextReference(ref);
    AppToast.show(context, S.of(context).toolCallAddedToContext);
    _log.fine('添加文件到上下文: $path');
  }

  /// Single edit entry row.
  Widget _entryRow(int index, FileEditEntry entry, WebSocketService ws) {
    final colors = context.colors;
    final statusColor = entry.isAccepted
        ? colors.secondary
        : entry.isRejected
            ? colors.error
            : colors.onSurfaceVariant;
    final statusIcon = entry.isAccepted
        ? Icons.check_circle_outline
        : entry.isRejected
            ? Icons.cancel_outlined
            : Icons.circle_outlined;
    final statusText = entry.isAccepted
        ? 'Accepted'
        : entry.isRejected
            ? 'Rejected'
            : 'Pending';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: colors.borderSubtle.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          // Index
          SizedBox(
            width: 20,
            child: Text('#${index + 1}',
                style: TextStyle(
                    fontSize: 10, color: statusColor, fontFamily: 'monospace')),
          ),
          // Change stats
          Text('+${entry.linesAdded}',
              style: TextStyle(fontSize: 10, color: colors.secondary)),
          const SizedBox(width: 2),
          Text('-${entry.linesDeleted}',
              style: TextStyle(fontSize: 10, color: colors.error)),
          const SizedBox(width: 8),
          // Status
          Icon(statusIcon, size: 12, color: statusColor),
          const SizedBox(width: 3),
          Expanded(
              child: Text(statusText,
                  style: TextStyle(fontSize: 10, color: statusColor))),
          // Diff button
          if (entry.isPending)
            GestureDetector(
              onTap: () => _openDiff(context, entry, ws),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child:
                    Icon(Icons.compare_arrows, size: 14, color: colors.primary),
              ),
            ),
          // Undo button (for already-resolved entries)
          if (!entry.isPending)
            GestureDetector(
              onTap: () {
                setState(() => entry.accepted = null);
                // TODO: send undo to agent
                ws.scheduleStreamNotify();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.undo, size: 14, color: colors.onSurfaceMuted),
              ),
            ),
        ],
      ),
    );
  }

  /// Accept All / Reject All action buttons
  Widget _actions(WebSocketService ws) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _chip('Accept All', colors.secondary, Icons.check, () {
            _log.info('接受所有编辑: ${block.filePath}');
            for (final e in entries) {
              if (e.isPending) e.accepted = true;
            }
            ws.fileOps.applyDiff(block.filePath ?? '', block.newContent ?? '');
            setState(() {});
            ws.scheduleStreamNotify();
          }),
          const SizedBox(width: 6),
          _chip('Reject All', colors.error, Icons.close, () {
            _log.info('拒绝所有编辑: ${block.filePath}');
            for (final e in entries) {
              if (e.isPending) e.accepted = false;
            }
            ws.fileOps.rejectDiff(block.filePath ?? '');
            setState(() {});
            ws.scheduleStreamNotify();
          }),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ]),
      ),
    );
  }

  /// Open the Diff viewer screen.
  void _openDiff(
      BuildContext context, FileEditEntry entry, WebSocketService ws) async {
    final result = await Navigator.of(context).push<String>(AppPageRoute(
      type: PageTransitionType.slideUp,
      page: DiffViewerScreen(
        filePath: block.filePath ?? '',
        oldCode: entry.oldContent,
        newCode: entry.newContent,
      ),
    ));
    if (result == 'accept') {
      _log.fine('接受 Diff: ${block.filePath}');
      setState(() => entry.accepted = true);
      ws.fileOps.applyDiff(block.filePath ?? '', entry.newContent);
      ws.scheduleStreamNotify();
    } else if (result == 'reject') {
      _log.fine('拒绝 Diff: ${block.filePath}');
      setState(() => entry.accepted = false);
      ws.fileOps.rejectDiff(block.filePath ?? '');
      ws.scheduleStreamNotify();
    }
  }
}
