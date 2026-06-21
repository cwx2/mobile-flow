/// conflict_resolver_screen.dart — Merge conflict resolution UI.
///
/// Module: screens/
/// Responsibility:
///   Full-screen conflict resolver for a single file. Displays each
///   conflict block as a card with Current/Incoming content and
///   action buttons (Accept Current / Accept Incoming / Accept Both).
///
///   Mirrors VS Code's merge-conflict extension behavior:
///   - Immediate write on each resolution (no batching)
///   - Auto-scroll to next conflict after resolving one
///   - Accept All quick actions in overflow menu
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
import '../theme/theme_extensions.dart';
import '../utils/logger.dart';

final _log = getLogger('ConflictResolver');

/// Screen for resolving merge conflicts in a single file.
///
/// Loads conflict blocks from the agent, displays them as cards,
/// and resolves them one by one (immediate write mode).
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
        final msgRepo = msg.payload['repo'] as String? ?? '';
        final msgPath = msg.payload['path'] as String? ?? '';
        if (!_matchesFile(msgRepo, msgPath)) break;

        final error = msg.payload['error'] as String? ?? '';
        if (error.isNotEmpty) {
          setState(() {
            _loading = false;
            _error = error;
          });
        } else {
          final conflicts = (msg.payload['conflicts'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          setState(() {
            _conflicts = conflicts;
            _loading = false;
            _error = null;
          });
        }

      case MessageType.gitConflictResolveResult:
        final msgRepo = msg.payload['repo'] as String? ?? '';
        final msgPath = msg.payload['path'] as String? ?? '';
        if (!_matchesFile(msgRepo, msgPath)) break;

        final success = msg.payload['success'] as bool? ?? false;
        if (success) {
          final remaining = (msg.payload['remaining'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          setState(() => _conflicts = remaining);
          _log.fine('冲突解决成功, remaining=${remaining.length}');
        } else {
          final error = msg.payload['error'] as String? ?? 'Unknown error';
          AppToast.show(context, error, type: AppToastType.error);
        }

      case MessageType.gitConflictResolveAllResult:
        final msgRepo = msg.payload['repo'] as String? ?? '';
        final msgPath = msg.payload['path'] as String? ?? '';
        if (!_matchesFile(msgRepo, msgPath)) break;

        final success = msg.payload['success'] as bool? ?? false;
        if (success) {
          setState(() => _conflicts = []);
          _log.info('全部冲突解决成功');
        } else {
          final error = msg.payload['error'] as String? ?? 'Unknown error';
          AppToast.show(context, error, type: AppToastType.error);
        }
    }
  }

  bool _matchesFile(String repo, String path) {
    return repo.replaceAll('\\', '/') == widget.repoPath.replaceAll('\\', '/') &&
        path == widget.filePath;
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
    AppToast.show(context, S.of(context).gitConflictsFileStaged, type: AppToastType.success);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fileName = widget.filePath.split('/').last;
    final l = S.of(context);

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
              onSelected: (value) {
                switch (value) {
                  case 'all_current':
                    _resolveAll('current');
                  case 'all_incoming':
                    _resolveAll('incoming');
                  case 'all_both':
                    _resolveAll('both');
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'all_current',
                  child: Text(l.gitConflictsAcceptAllCurrent),
                ),
                PopupMenuItem(
                  value: 'all_incoming',
                  child: Text(l.gitConflictsAcceptAllIncoming),
                ),
                PopupMenuItem(
                  value: 'all_both',
                  child: Text(l.gitConflictsAcceptAllBoth),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(colors),
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

  Widget _buildBody(dynamic colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

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
      final l = S.of(context);
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
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final conflict = _conflicts[index];
        return _ConflictCard(
          conflict: conflict,
          onResolve: (resolution) =>
              _resolve(conflict['id'] as int? ?? index, resolution),
        );
      },
    );
  }
}

/// Single conflict block card with Current/Incoming display and action buttons.
class _ConflictCard extends StatelessWidget {
  final Map<String, dynamic> conflict;
  final void Function(String resolution) onResolve;

  const _ConflictCard({
    required this.conflict,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l = S.of(context);
    final currentLabel = conflict['current_label'] as String? ?? 'HEAD';
    final currentContent = conflict['current_content'] as String? ?? '';
    final incomingLabel = conflict['incoming_label'] as String? ?? '';
    final incomingContent = conflict['incoming_content'] as String? ?? '';
    final rangeStart = conflict['range_start'] as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Conflict header
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Conflict (line ${rangeStart + 1})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceMuted,
              ),
            ),
          ),

          // Current block (green)
          _CodeBlock(
            label: '$currentLabel (${l.gitConflictsCurrentChange})',
            content: currentContent,
            borderColor: const Color(0xFF4CAF50),
            backgroundColor: const Color(0x0D4CAF50),
          ),

          const SizedBox(height: 6),

          // Incoming block (blue)
          _CodeBlock(
            label: '$incomingLabel (${l.gitConflictsIncomingChange})',
            content: incomingContent,
            borderColor: const Color(0xFF2196F3),
            backgroundColor: const Color(0x0D2196F3),
          ),

          const SizedBox(height: 8),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: l.gitConflictsAcceptCurrent,
                  onPressed: () => onResolve('current'),
                  color: const Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: l.gitConflictsAcceptIncoming,
                  onPressed: () => onResolve('incoming'),
                  color: const Color(0xFF2196F3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: l.gitConflictsAcceptBoth,
                  onPressed: () => onResolve('both'),
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),
          Divider(color: colors.border.withValues(alpha: 0.3)),
        ],
      ),
    );
  }
}

/// Code content block with colored left border.
class _CodeBlock extends StatefulWidget {
  final String label;
  final String content;
  final Color borderColor;
  final Color backgroundColor;

  const _CodeBlock({
    required this.label,
    required this.content,
    required this.borderColor,
    required this.backgroundColor,
  });

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _expanded = false;

  /// Max lines to show before collapsing.
  static const _collapseThreshold = 15;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lines = widget.content.split('\n');
    final needsCollapse = lines.length > _collapseThreshold;
    final displayContent = needsCollapse && !_expanded
        ? lines.take(_collapseThreshold).join('\n')
        : widget.content;

    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        border: Border(
          left: BorderSide(color: widget.borderColor, width: 3),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label header
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceMuted,
              ),
            ),
          ),
          // Code content
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: widget.content.isEmpty
                ? Text(
                    '(empty)',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      fontFamily: 'monospace',
                      color: colors.onSurfaceMuted,
                    ),
                  )
                : Text(
                    displayContent,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.4,
                      color: colors.onSurface,
                    ),
                  ),
          ),
          // Expand/collapse toggle
          if (needsCollapse)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                alignment: Alignment.center,
                child: Text(
                  _expanded
                      ? '▲ Collapse'
                      : '▼ + ${lines.length - _collapseThreshold} more lines',
                  style: TextStyle(fontSize: 10, color: widget.borderColor),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact action button for conflict resolution.
class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color color;

  const _ActionButton({
    required this.label,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ),
    );
  }
}
