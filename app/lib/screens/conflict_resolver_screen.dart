/// conflict_resolver_screen.dart — Merge conflict resolution UI (V3).
///
/// Module: screens/
/// Responsibility:
///   VS Code-style 3-way merge editor adapted for mobile. Displays three
///   full-file thumbnails (current / incoming / both) at the top — each
///   showing the entire file with conflict lines highlighted. Tapping a
///   thumbnail expands it into a full-screen scrollable code view below.
///
///   Like VS Code's merge editor: each panel shows the COMPLETE file
///   content (not just the conflict snippet), with conflict regions
///   highlighted in color.
///
/// Navigation:
///   GitChangesTab → tap conflict file → ConflictResolverScreen
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/protocol.dart';
import '../services/git_state.dart';
import '../services/websocket_service.dart';
import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../screens/file_viewer_screen.dart';
import '../theme/theme_extensions.dart';

/// Full-file merge conflict resolver screen.
class ConflictResolverScreen extends StatefulWidget {
  final String repoPath;
  final String filePath;

  const ConflictResolverScreen({
    super.key,
    required this.repoPath,
    required this.filePath,
  });

  @override
  State<ConflictResolverScreen> createState() => _ConflictResolverScreenState();
}

class _ConflictResolverScreenState extends State<ConflictResolverScreen> {
  // Conflict data
  List<Map<String, dynamic>> _conflicts = [];
  String _fileCurrent = '';
  String _fileIncoming = '';
  String _fileBoth = '';
  List<List<int>> _rangesCurrent = [];
  List<List<int>> _rangesIncoming = [];
  List<List<int>> _rangesBoth = [];

  bool _loading = true;
  String? _error;
  int _selected = 0; // 0=current, 1=incoming, 2=both
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();
    _sub = ws.messageStream.listen(_onMessage);
    _requestConflicts();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _requestConflicts() {
    final ws = context.read<WebSocketService>();
    ws.gitOps.gitConflicts(repo: widget.repoPath, path: widget.filePath);
  }

  void _onMessage(WsMessage msg) {
    if (!mounted) return;
    switch (msg.type) {
      case MessageType.gitConflictsResult:
        if (!_matchesFile(msg.payload)) break;
        final error = msg.payload['error'] as String? ?? '';
        if (error.isNotEmpty) {
          setState(() { _loading = false; _error = error; });
        } else {
          setState(() {
            _conflicts = (msg.payload['conflicts'] as List?)
                ?.cast<Map<String, dynamic>>() ?? [];
            _fileCurrent = msg.payload['file_current'] as String? ?? '';
            _fileIncoming = msg.payload['file_incoming'] as String? ?? '';
            _fileBoth = msg.payload['file_both'] as String? ?? '';
            _rangesCurrent = _parseRanges(msg.payload['conflict_ranges_current']);
            _rangesIncoming = _parseRanges(msg.payload['conflict_ranges_incoming']);
            _rangesBoth = _parseRanges(msg.payload['conflict_ranges_both']);
            _loading = false;
            _error = null;
          });
        }

      case MessageType.gitConflictResolveAllResult:
        if (!_matchesFile(msg.payload)) break;
        final success = msg.payload['success'] as bool? ?? false;
        if (success) {
          setState(() => _conflicts = []);
        } else {
          AppToast.show(context, msg.payload['error'] as String? ?? 'Error',
              type: AppToastType.error);
        }
    }
  }

  List<List<int>> _parseRanges(dynamic data) {
    if (data is! List) return [];
    return data.map((r) {
      if (r is List) return r.cast<int>();
      return <int>[];
    }).toList();
  }

  bool _matchesFile(Map<String, dynamic> payload) {
    final repo = (payload['repo'] as String? ?? '').replaceAll('\\', '/');
    final path = payload['path'] as String? ?? '';
    return repo == widget.repoPath.replaceAll('\\', '/') &&
        path == widget.filePath;
  }

  void _resolveAll(String resolution) {
    final ws = context.read<WebSocketService>();
    ws.gitOps.gitConflictResolveAll(
      repo: widget.repoPath,
      path: widget.filePath,
      resolution: resolution,
    );
  }

  void _stageFile() {
    final git = context.read<GitStateProvider>();
    git.stage([widget.filePath], repo: widget.repoPath);
    AppToast.show(context, S.of(context).gitConflictsFileStaged,
        type: AppToastType.success);
    Navigator.pop(context, true);
  }

  String _fileForIndex(int i) =>
      i == 0 ? _fileCurrent : i == 1 ? _fileIncoming : _fileBoth;

  List<List<int>> _rangesForIndex(int i) =>
      i == 0 ? _rangesCurrent : i == 1 ? _rangesIncoming : _rangesBoth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l = S.of(context);
    final fileName = widget.filePath.split('/').last;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fileName, style: const TextStyle(fontSize: 15)),
            Text(
              _conflicts.isEmpty && !_loading
                  ? l.gitConflictsAllResolved
                  : l.gitConflictsRemaining(_conflicts.length),
              style: TextStyle(fontSize: 11, color: colors.onSurfaceMuted),
            ),
          ],
        ),
        actions: [
          // Edit in editor
          IconButton(
            icon: const Icon(Icons.edit_note, size: 20),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FileViewerScreen(filePath: widget.filePath),
            )),
            tooltip: 'Edit',
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.colors;
    final l = S.of(context);

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }

    if (_conflicts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: colors.secondary),
            const SizedBox(height: 12),
            Text(l.gitConflictsAllResolved,
                style: TextStyle(fontSize: 16, color: colors.onSurface)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _stageFile,
              icon: const Icon(Icons.check),
              label: Text(l.gitConflictsStageFile),
            ),
          ],
        ),
      );
    }

    final labels = [
      l.gitConflictsAcceptCurrent,
      l.gitConflictsAcceptIncoming,
      l.gitConflictsAcceptBoth,
    ];
    final tabColors = [
      const Color(0xFF4CAF50),
      const Color(0xFF2196F3),
      const Color(0xFF9C27B0),
    ];

    return Column(
      children: [
        // Three full-file thumbnails at the top
        SizedBox(
          height: 120,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: List.generate(3, (i) {
                final isSelected = _selected == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      margin: EdgeInsets.only(
                        left: i == 0 ? 0 : 3,
                        right: i == 2 ? 0 : 3,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? tabColors[i].withValues(alpha: 0.08)
                            : colors.surfaceVariant.withValues(alpha: 0.3),
                        border: Border.all(
                          color: isSelected
                              ? tabColors[i]
                              : colors.border.withValues(alpha: 0.3),
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Label bar
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 3),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? tabColors[i].withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(5),
                                topRight: Radius.circular(5),
                              ),
                            ),
                            child: Text(
                              labels[i],
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? tabColors[i]
                                    : colors.onSurfaceMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Full file miniature
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(5),
                                bottomRight: Radius.circular(5),
                              ),
                              child: _FileThumbnail(
                                content: _fileForIndex(i),
                                ranges: _rangesForIndex(i),
                                highlightColor: tabColors[i],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),

        // Full-size file preview (expanded, scrollable)
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _FullFilePreview(
              key: ValueKey(_selected),
              content: _fileForIndex(_selected),
              ranges: _rangesForIndex(_selected),
              highlightColor: tabColors[_selected],
            ),
          ),
        ),

        // Bottom action bar
        SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: colors.border.withValues(alpha: 0.3))),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                onPressed: () {
                  final resolutions = ['current', 'incoming', 'both'];
                  _resolveAll(resolutions[_selected]);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: tabColors[_selected],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  '${l.commonConfirm} — ${labels[_selected]}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Miniature file thumbnail showing full file content as tiny text.
/// Conflict regions are highlighted with colored background strips.
class _FileThumbnail extends StatelessWidget {
  final String content;
  final List<List<int>> ranges;
  final Color highlightColor;

  const _FileThumbnail({
    required this.content,
    required this.ranges,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lines = content.split('\n');

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: lines.length,
      itemExtent: 3.5, // Each line is 3.5px tall in thumbnail
      itemBuilder: (_, i) {
        final isHighlighted = _isInRange(i);
        return Container(
          color: isHighlighted
              ? highlightColor.withValues(alpha: 0.35)
              : null,
          child: Text(
            lines[i],
            style: TextStyle(
              fontSize: 3,
              fontFamily: 'monospace',
              height: 1.0,
              color: isHighlighted
                  ? colors.onSurface
                  : colors.onSurface.withValues(alpha: 0.4),
            ),
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        );
      },
    );
  }

  bool _isInRange(int line) {
    for (final range in ranges) {
      if (range.length >= 2 && line >= range[0] && line <= range[1]) {
        return true;
      }
    }
    return false;
  }
}

/// Full-size file preview with line numbers and conflict highlighting.
/// Takes up the remaining vertical space, fully scrollable.
class _FullFilePreview extends StatelessWidget {
  final String content;
  final List<List<int>> ranges;
  final Color highlightColor;

  const _FullFilePreview({
    super.key,
    required this.content,
    required this.ranges,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lines = content.split('\n');
    // Remove trailing empty line
    final displayLines =
        lines.isNotEmpty && lines.last.isEmpty ? lines.sublist(0, lines.length - 1) : lines;
    final lineNumWidth = '${displayLines.length}'.length * 8.0 + 8;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: displayLines.length,
      itemExtent: 18, // Fixed line height for performance
      itemBuilder: (_, i) {
        final isHighlighted = _isInRange(i);
        return Container(
          color: isHighlighted
              ? highlightColor.withValues(alpha: 0.12)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Line number
              SizedBox(
                width: lineNumWidth,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: isHighlighted
                        ? highlightColor.withValues(alpha: 0.7)
                        : colors.onSurfaceMuted.withValues(alpha: 0.4),
                  ),
                ),
              ),
              // Code content
              Expanded(
                child: Text(
                  displayLines[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.3,
                    color: isHighlighted
                        ? colors.onSurface
                        : colors.onSurfaceMuted.withValues(alpha: 0.8),
                    fontWeight:
                        isHighlighted ? FontWeight.w500 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isInRange(int line) {
    for (final range in ranges) {
      if (range.length >= 2 && line >= range[0] && line <= range[1]) {
        return true;
      }
    }
    return false;
  }
}
