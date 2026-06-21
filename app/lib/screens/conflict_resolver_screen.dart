/// conflict_resolver_screen.dart — Merge conflict resolution UI (V2).
///
/// Module: screens/
/// Responsibility:
///   Three-panel thumbnail preview with animated zoom for conflict resolution.
///   Shows three versions (Current / Incoming / Both) as miniature previews,
///   tapping one expands it with smooth animation to full-size readable code.
///
///   Design mirrors VS Code's 3-way merge editor adapted for mobile:
///   - Three thumbnails at top for quick visual comparison
///   - Full preview below with file context (lines before/after conflict)
///   - Swipe or tap to switch between versions
///   - Confirm button to apply the selected resolution
///   - Edit button to open in FileViewerScreen for manual changes
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

/// Screen for resolving merge conflicts in a single file.
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
  List<Map<String, dynamic>> _conflicts = [];
  bool _loading = true;
  String? _error;
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
          final conflicts = (msg.payload['conflicts'] as List?)
              ?.cast<Map<String, dynamic>>() ?? [];
          setState(() { _conflicts = conflicts; _loading = false; _error = null; });
        }

      case MessageType.gitConflictResolveResult:
        if (!_matchesFile(msg.payload)) break;
        final success = msg.payload['success'] as bool? ?? false;
        if (success) {
          // Re-request to get fresh context for remaining conflicts
          _requestConflicts();
        } else {
          final error = msg.payload['error'] as String? ?? 'Unknown error';
          AppToast.show(context, error, type: AppToastType.error);
        }

      case MessageType.gitConflictResolveAllResult:
        if (!_matchesFile(msg.payload)) break;
        final success = msg.payload['success'] as bool? ?? false;
        if (success) {
          setState(() => _conflicts = []);
        } else {
          final error = msg.payload['error'] as String? ?? 'Unknown error';
          AppToast.show(context, error, type: AppToastType.error);
        }
    }
  }

  bool _matchesFile(Map<String, dynamic> payload) {
    final repo = (payload['repo'] as String? ?? '').replaceAll('\\', '/');
    final path = payload['path'] as String? ?? '';
    return repo == widget.repoPath.replaceAll('\\', '/') && path == widget.filePath;
  }

  void _resolve(int conflictId, String resolution) {
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

  void _stageFile() {
    final git = context.read<GitStateProvider>();
    git.stage([widget.filePath], repo: widget.repoPath);
    AppToast.show(context, S.of(context).gitConflictsFileStaged,
        type: AppToastType.success);
    Navigator.pop(context, true);
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
              icon: const Icon(Icons.more_vert),
              onSelected: (v) => _resolveAll(v),
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'current', child: Text(l.gitConflictsAcceptAllCurrent)),
                PopupMenuItem(
                    value: 'incoming', child: Text(l.gitConflictsAcceptAllIncoming)),
                PopupMenuItem(
                    value: 'both', child: Text(l.gitConflictsAcceptAllBoth)),
              ],
            ),
        ],
      ),
      body: _buildBody(context),
      bottomNavigationBar: _conflicts.isEmpty && !_loading && _error == null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _stageFile,
                  icon: const Icon(Icons.check),
                  label: Text(l.gitConflictsStageFile),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.colors;
    final l = S.of(context);

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 40, color: colors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
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
            const SizedBox(height: 4),
            Text(l.gitConflictsAllResolvedDesc,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceMuted)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _conflicts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final conflict = _conflicts[index];
        return _ConflictResolver(
          conflict: conflict,
          filePath: widget.filePath,
          onResolve: (resolution) =>
              _resolve(conflict['id'] as int? ?? index, resolution),
        );
      },
    );
  }
}

/// Per-conflict resolver with thumbnail 3-panel preview.
class _ConflictResolver extends StatefulWidget {
  final Map<String, dynamic> conflict;
  final String filePath;
  final void Function(String resolution) onResolve;

  const _ConflictResolver({
    required this.conflict,
    required this.filePath,
    required this.onResolve,
  });

  @override
  State<_ConflictResolver> createState() => _ConflictResolverState();
}

class _ConflictResolverState extends State<_ConflictResolver> {
  /// Selected version: 0=current, 1=incoming, 2=both
  int _selected = 0;

  String get _currentContent =>
      widget.conflict['current_content'] as String? ?? '';
  String get _incomingContent =>
      widget.conflict['incoming_content'] as String? ?? '';
  String get _contextBefore =>
      widget.conflict['context_before'] as String? ?? '';
  String get _contextAfter =>
      widget.conflict['context_after'] as String? ?? '';
  int get _rangeStart => widget.conflict['range_start'] as int? ?? 0;

  /// Build full preview for a given resolution index.
  String _buildPreview(int index) {
    final resolved = index == 0
        ? _currentContent
        : index == 1
            ? _incomingContent
            : _currentContent + _incomingContent;
    return _contextBefore + resolved + _contextAfter;
  }

  String _resolutionFor(int index) =>
      const ['current', 'incoming', 'both'][index];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l = S.of(context);

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with conflict info + edit button
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  'Conflict (line ${_rangeStart + 1})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceMuted,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FileViewerScreen(filePath: widget.filePath),
                  )),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note, size: 16, color: colors.primary),
                      const SizedBox(width: 2),
                      Text('Edit',
                          style: TextStyle(fontSize: 11, color: colors.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Three thumbnail previews side by side
          SizedBox(
            height: 90,
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
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? tabColors[i].withValues(alpha: 0.12)
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
                          // Label
                          Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? tabColors[i]
                                  : colors.onSurfaceMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          // Miniature code (tiny font for shape overview)
                          Expanded(
                            child: ClipRect(
                              child: Text(
                                _buildPreview(i),
                                style: TextStyle(
                                  fontSize: 5,
                                  fontFamily: 'monospace',
                                  height: 1.2,
                                  color: colors.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                                overflow: TextOverflow.clip,
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

          const SizedBox(height: 10),

          // Full preview with animated content switching
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _FullPreview(
              key: ValueKey(_selected),
              content: _buildPreview(_selected),
              conflictContent: _selected == 0
                  ? _currentContent
                  : _selected == 1
                      ? _incomingContent
                      : _currentContent + _incomingContent,
              contextBefore: _contextBefore,
              color: tabColors[_selected],
              label: labels[_selected],
            ),
          ),

          const SizedBox(height: 10),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: () => widget.onResolve(_resolutionFor(_selected)),
              style: FilledButton.styleFrom(
                backgroundColor: tabColors[_selected],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                '${l.commonConfirm} — ${labels[_selected]}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: 8),
          Divider(color: colors.border.withValues(alpha: 0.3)),
        ],
      ),
    );
  }
}

/// Full-size code preview with line numbers and conflict highlighting.
class _FullPreview extends StatelessWidget {
  final String content;
  final String conflictContent;
  final String contextBefore;
  final Color color;
  final String label;

  const _FullPreview({
    super.key,
    required this.content,
    required this.conflictContent,
    required this.contextBefore,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lines = content.split('\n');
    final displayLines =
        lines.isNotEmpty && lines.last.isEmpty ? lines.sublist(0, lines.length - 1) : lines;

    // Calculate which lines are the resolved conflict (for highlighting)
    final beforeCount = contextBefore.isEmpty
        ? 0
        : contextBefore.split('\n').length -
            (contextBefore.endsWith('\n') ? 1 : 0);
    final conflictCount = conflictContent.isEmpty
        ? 0
        : conflictContent.split('\n').length -
            (conflictContent.endsWith('\n') ? 1 : 0);

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.2),
        border: Border(left: BorderSide(color: color, width: 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Text(
                '▶ $label',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: color),
              ),
            ),
            // Code lines
            ...List.generate(displayLines.length, (i) {
              final isHighlighted =
                  i >= beforeCount && i < beforeCount + conflictCount;
              return Container(
                width: double.infinity,
                color: isHighlighted ? color.withValues(alpha: 0.1) : null,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color:
                              colors.onSurfaceMuted.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        displayLines[i],
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                          color: isHighlighted
                              ? colors.onSurface
                              : colors.onSurfaceMuted,
                          fontWeight: isHighlighted
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
