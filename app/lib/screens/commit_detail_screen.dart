/// commit_detail_screen.dart — Commit detail view.
///
/// Module: screens/
/// Responsibility:
///   Shows commit metadata (author, date, full message) and a list of
///   changed files with additions/deletions stats. Tapping a file opens
///   the DiffViewerScreen with old/new content from that commit.
///
/// Called by:
///   - GitLogTab (tap on a commit entry)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../animation/page_transition_builder.dart';
import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../models/payloads/git_payloads.g.dart';
import '../models/protocol.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/git_operations.dart';
import '../theme/theme_extensions.dart';
import '../utils/logger.dart';
import 'diff_viewer_screen.dart';

final _log = getLogger('CommitDetail');

/// Commit detail screen showing metadata and changed files.
class CommitDetailScreen extends StatefulWidget {
  final String commitHash;
  final String shortHash;
  final String message;

  const CommitDetailScreen({
    super.key,
    required this.commitHash,
    required this.shortHash,
    required this.message,
  });

  @override
  State<CommitDetailScreen> createState() => _CommitDetailScreenState();
}

class _CommitDetailScreenState extends State<CommitDetailScreen> {
  StreamSubscription? _sub;
  bool _loading = true;

  // Commit metadata
  String _author = '';
  String _date = '';
  String _fullMessage = '';
  List<Map<String, dynamic>> _files = [];
  String _error = '';

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();
    _sub = ws.messageStream.listen(_onMessage);
    context.read<GitOperations>().gitShow(widget.commitHash);
    _log.fine('请求 commit 详情: ${widget.shortHash}');
  }

  void _onMessage(WsMessage msg) {
    if (!mounted) return;
    if (msg.type == MessageType.gitShowResult) {
      final p = GitShowResultPayload.fromJson(msg.payload);
      setState(() {
        _loading = false;
        _error = p.error ?? '';
        _author = p.author;
        _date = p.date;
        _fullMessage = p.fullMessage;
        _files = p.files;
      });
      _log.fine('收到 commit 详情: ${_files.length} 个文件');
    }
    if (msg.type == MessageType.gitDiffCommitResult) {
      final p = GitDiffCommitResultPayload.fromJson(msg.payload);
      // NOTE: `path` not in generated payload — read from raw map
      final path = msg.payload['path'] as String? ?? '';
      _handleDiffResult(p, path);
    }
  }

  void _handleDiffResult(GitDiffCommitResultPayload p, String path) {
    final error = p.error ?? '';

    if (error.isNotEmpty) {
      AppToast.show(context, error, type: AppToastType.error);
      return;
    }
    if (p.oldContent.isEmpty && p.newContent.isEmpty) {
      AppToast.show(context, S.of(context).gitBinaryFileToast);
      return;
    }

    Navigator.push(
      context,
      AppPageRoute(
        type: PageTransitionType.slideUp,
        page: DiffViewerScreen(
          filePath: path,
          oldCode: p.oldContent,
          newCode: p.newContent,
          showAcceptReject: false,
        ),
      ),
    );
  }

  void _openFileDiff(String path) {
    context.read<GitOperations>().gitDiffCommit(hash: widget.commitHash, path: path);
    _log.fine('请求 commit diff: ${widget.shortHash} $path');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.shortHash,
                style: const TextStyle(
                    fontSize: 15, fontFamily: 'monospace')),
            Text(widget.message,
                style: TextStyle(
                    fontSize: 11, color: colors.onSurfaceMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          // Copy full hash
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: S.of(context).gitCopyHash,
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: widget.commitHash));
              AppToast.show(context, S.of(context).commonCopied);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Text(_error,
                      style: TextStyle(color: colors.error)))
              : _buildContent(colors),
    );
  }

  Widget _buildContent(dynamic colors) {
    return ListView(
      children: [
        // Commit metadata
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author + date row
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14,
                      color: colors.onSurfaceMuted),
                  const SizedBox(width: 4),
                  Text(_author,
                      style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant)),
                  const SizedBox(width: 12),
                  Icon(Icons.calendar_today, size: 12,
                      color: colors.onSurfaceMuted),
                  const SizedBox(width: 4),
                  Text(_date,
                      style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceMuted)),
                ],
              ),
              const SizedBox(height: 12),
              // Full commit message
              if (_fullMessage.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(_fullMessage,
                      style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                          height: 1.5)),
                ),
            ],
          ),
        ),
        // Changed files header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(S.of(context).gitChangedFiles(_files.length),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface)),
        ),
        const SizedBox(height: 4),
        // File list
        ..._files.map((f) => _buildFileItem(f, colors)),
      ],
    );
  }

  Widget _buildFileItem(Map<String, dynamic> file, dynamic colors) {
    final path = file['path'] as String? ?? '';
    final status = file['status'] as String? ?? 'M';
    final additions = file['additions'] as int? ?? 0;
    final deletions = file['deletions'] as int? ?? 0;
    final fileName = path.split('/').last;

    // Status color and label
    final (statusColor, statusLabel) = switch (status) {
      'A' => (colors.success as Color, 'A'),
      'D' => (colors.error as Color, 'D'),
      'R' => (colors.warning as Color, 'R'),
      _ => (colors.secondary as Color, 'M'),
    };

    return InkWell(
      onTap: () => _openFileDiff(path),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Status badge
            Container(
              width: 20, height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor)),
            ),
            const SizedBox(width: 8),
            // File name + path
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fileName,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  if (path != fileName)
                    Text(path,
                        style: TextStyle(
                            fontSize: 10,
                            color: colors.onSurfaceMuted),
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            // Additions / deletions
            if (additions > 0)
              Text('+$additions',
                  style: TextStyle(
                      fontSize: 11,
                      color: colors.success,
                      fontFamily: 'monospace')),
            if (additions > 0 && deletions > 0)
              const SizedBox(width: 4),
            if (deletions > 0)
              Text('-$deletions',
                  style: TextStyle(
                      fontSize: 11,
                      color: colors.error,
                      fontFamily: 'monospace')),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16,
                color: colors.onSurfaceMuted),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
