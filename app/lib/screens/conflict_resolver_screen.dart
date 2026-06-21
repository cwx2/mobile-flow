/// conflict_resolver_screen.dart — Merge conflict resolution UI (V3).
///
/// Module: screens/
/// Responsibility:
///   VS Code-style 3-way merge editor adapted for mobile. Three full-file
///   thumbnails at top, full-size code preview below using CodeEditorView
///   (same component as FileViewerScreen — syntax highlighting, line numbers,
///   horizontal scroll, word wrap).
///
/// Navigation:
///   GitChangesTab → tap conflict file → ConflictResolverScreen
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../editor/editor.dart';
import '../models/protocol.dart';
import '../services/git_state.dart';
import '../services/websocket_service.dart';
import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../screens/file_viewer_screen.dart';
import '../theme/theme_extensions.dart';
import '../widgets/code_editor_view.dart';

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
  // Conflict data from Agent
  List<Map<String, dynamic>> _conflicts = [];
  int _currentIndex = 0; // Which conflict we're looking at
  int _selected = 0; // 0=current, 1=incoming, 2=both

  bool _loading = true;
  String? _error;
  StreamSubscription? _sub;

  // Code editor controller for the large preview
  CodeLineEditingController? _codeController;
  CodeScrollController? _scrollController;

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
    _codeController?.dispose();
    _scrollController?.dispose();
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
          _conflicts = (msg.payload['conflicts'] as List?)
              ?.cast<Map<String, dynamic>>() ?? [];
          _currentIndex = 0;
          _selected = 0;
          _updateEditorContent();
          setState(() { _loading = false; _error = null; });
        }

      case MessageType.gitConflictResolveResult:
        if (!_matchesFile(msg.payload)) break;
        final success = msg.payload['success'] as bool? ?? false;
        if (success) {
          // Re-request conflicts (file has changed, IDs recalculated)
          _requestConflicts();
        } else {
          AppToast.show(context, msg.payload['error'] as String? ?? 'Error',
              type: AppToastType.error);
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

  void _updateEditorContent() {
    final content = _currentPreview();
    _codeController?.dispose();
    _scrollController?.dispose();
    _codeController = CodeLineEditingController.fromText(content);
    _scrollController = CodeScrollController();
  }

  /// Get the preview content for the current conflict + selected resolution.
  String _currentPreview() {
    if (_conflicts.isEmpty || _currentIndex >= _conflicts.length) return '';
    final conflict = _conflicts[_currentIndex];
    final key = 'preview_${['current', 'incoming', 'both'][_selected]}';
    return conflict[key] as String? ?? '';
  }

  /// Get highlight range for current conflict + selected resolution.
  /// (Reserved for future use when editor supports line decorations.)

  bool _matchesFile(Map<String, dynamic> payload) {
    final repo = (payload['repo'] as String? ?? '').replaceAll('\\', '/');
    final path = payload['path'] as String? ?? '';
    return repo == widget.repoPath.replaceAll('\\', '/') &&
        path == widget.filePath;
  }

  void _resolve() {
    if (_conflicts.isEmpty || _currentIndex >= _conflicts.length) return;
    final conflict = _conflicts[_currentIndex];
    final conflictId = conflict['id'] as int? ?? _currentIndex;
    final resolution = ['current', 'incoming', 'both'][_selected];
    final ws = context.read<WebSocketService>();
    ws.gitOps.gitConflictResolve(
      repo: widget.repoPath,
      path: widget.filePath,
      conflictId: conflictId,
      resolution: resolution,
    );
  }

  void _resolveAll(String resolution) {
    final ws = context.read<WebSocketService>();
    ws.gitOps.gitConflictResolveAll(
      repo: widget.repoPath,
      path: widget.filePath,
      resolution: resolution,
    );
  }

  void _selectTab(int i) {
    if (i == _selected) return;
    setState(() => _selected = i);
    _updateEditorContent();
  }

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
          if (_conflicts.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) => _resolveAll(v),
              itemBuilder: (_) {
                final l = S.of(context);
                return [
                  PopupMenuItem(value: 'current', child: Text(l.gitConflictsAcceptAllCurrent)),
                  PopupMenuItem(value: 'incoming', child: Text(l.gitConflictsAcceptAllIncoming)),
                  PopupMenuItem(value: 'both', child: Text(l.gitConflictsAcceptAllBoth)),
                ];
              },
            ),
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
              onPressed: () {
                final git = context.read<GitStateProvider>();
                git.stage([widget.filePath], repo: widget.repoPath);
                AppToast.show(context, l.gitConflictsFileStaged,
                    type: AppToastType.success);
                Navigator.pop(context, true);
              },
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

    final conflict = _conflicts[_currentIndex];
    final currentLabel = conflict['current_label'] as String? ?? 'HEAD';
    final incomingLabel = conflict['incoming_label'] as String? ?? '';

    return Column(
      children: [
        // Conflict progress indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Text(
                'Conflict ${_currentIndex + 1} / ${_conflicts.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$currentLabel ↔ $incomingLabel',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceMuted),
              ),
            ],
          ),
        ),

        // Three thumbnails
        SizedBox(
          height: 100,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: List.generate(3, (i) {
                final isSelected = _selected == i;
                final previewKey = 'preview_${['current', 'incoming', 'both'][i]}';
                final previewContent = conflict[previewKey] as String? ?? '';
                final highlightKey = 'highlight_${['current', 'incoming', 'both'][i]}';
                final highlight = conflict[highlightKey] as List? ?? [];

                return Expanded(
                  child: GestureDetector(
                    onTap: () => _selectTab(i),
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
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(5),
                                bottomRight: Radius.circular(5),
                              ),
                              child: _FileThumbnail(
                                content: previewContent,
                                ranges: highlight.isNotEmpty
                                    ? [highlight.cast<int>()] : [],
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

        const SizedBox(height: 4),

        // Full code preview using CodeEditorView
        Expanded(
          child: _codeController != null
              ? CodeEditorView(
                  controller: _codeController!,
                  scrollController: _scrollController,
                  filePath: widget.filePath,
                  readOnly: true,
                )
              : const SizedBox.shrink(),
        ),

        // Bottom action bar: confirm current conflict
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
                onPressed: _resolve,
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

/// Miniature file thumbnail (tiny text with colored conflict line markers).
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
      itemExtent: 3.5,
      itemBuilder: (_, i) {
        final isHighlighted = _isInRange(i);
        return Container(
          color: isHighlighted
              ? highlightColor.withValues(alpha: 0.4)
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
