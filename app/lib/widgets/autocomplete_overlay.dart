/// autocomplete_overlay.dart — Inline autocomplete for # context references.
///
/// Displays a filtered list of project files matching the text after `#`.
/// Positioned above the ChatInputBar via an [OverlayEntry] managed by
/// the parent widget (ChatInputBar, Task 9).
///
/// File tree data is obtained by listening to [WebSocketService.messageStream]
/// for `fileTreeResult` messages, mirroring the approach in
/// `context_picker.dart`. The flattened file list is cached in widget state
/// so subsequent queries filter instantly without re-fetching.
///
/// See also: [ContextReference], [kAutocompleteMaxResults].
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/context_reference.dart';
import '../models/payloads/file_payloads.g.dart';
import '../models/protocol.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';

final _log = getLogger('AutocompleteOverlay');

/// Inline autocomplete overlay for # context references.
///
/// Filters the project file tree by case-insensitive substring match on
/// [query]. Results are capped at [kAutocompleteMaxResults]. Shows a
/// loading indicator while the file tree is being fetched, and an empty
/// state message when no files match.
///
/// On item selection, creates a [ContextReference] with type
/// [ContextRefType.files] and calls [onSelect]. The parent widget is
/// responsible for inserting the overlay and dismissing it via [onDismiss].
class AutocompleteOverlay extends StatefulWidget {
  /// The search text after `#` (e.g., user typed `#auth` → query = "auth").
  final String query;

  /// WebSocket service for accessing the file tree.
  final WebSocketService ws;

  /// Called when the user picks a file from the results.
  final void Function(ContextReference ref) onSelect;

  /// Called to dismiss the overlay (e.g., on backdrop tap).
  final VoidCallback onDismiss;

  /// Create an autocomplete overlay.
  const AutocompleteOverlay({
    super.key,
    required this.query,
    required this.ws,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  State<AutocompleteOverlay> createState() => _AutocompleteOverlayState();
}

class _AutocompleteOverlayState extends State<AutocompleteOverlay> {
  /// Flattened file list cached from the file tree response.
  /// Each entry: {'name': String, 'path': String, 'type': 'file'|'dir'}.
  List<Map<String, dynamic>>? _cachedFiles;

  /// Whether we are waiting for the file tree from the Agent.
  bool _loading = true;

  StreamSubscription<WsMessage>? _treeSub;

  @override
  void initState() {
    super.initState();
    _requestFileTree();
  }

  @override
  void dispose() {
    _treeSub?.cancel();
    super.dispose();
  }

  /// Request the file tree and listen for the result.
  ///
  /// Checks [WebSocketService.cachedFileTree] first to avoid a
  /// round-trip to the Agent when the cache is still fresh. On cache
  /// miss, subscribes to [ws.messageStream] for a single
  /// `fileTreeResult` message, flattens the tree, and caches the
  /// result. If no response arrives within 10 seconds, stops loading
  /// to avoid an infinite spinner.
  void _requestFileTree() {
    // Check WebSocketService cache first — avoids re-fetching on
    // every overlay open when files haven't changed.
    final cached = widget.ws.cachedFileTree;
    if (cached != null) {
      _log.fine('文件树命中缓存: ${cached.length} entries');
      setState(() {
        _cachedFiles = cached;
        _loading = false;
      });
      return;
    }

    // Cache miss — request from Agent (existing logic)
    _treeSub?.cancel();
    _treeSub = widget.ws.messageStream.listen((msg) {
      if (msg.type == MessageType.fileTreeResult) {
        _treeSub?.cancel();
        final p = FileTreeResultPayload.fromJson(msg.payload);
        final tree = p.data;
        final files = <Map<String, dynamic>>[];
        _flattenTree(tree, '', files);
        if (mounted) {
          setState(() {
            _cachedFiles = files;
            _loading = false;
          });
        }
      }
    });

    widget.ws.fileOps.requestFileTree(depth: 3);
    _log.fine('文件树缓存未命中，请求 Agent');

    // Timeout: stop loading after 10s to avoid infinite spinner.
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _loading) {
        _treeSub?.cancel();
        setState(() => _loading = false);
        _log.warning('文件树请求超时 (10s)');
      }
    });
  }

  /// Recursively flatten a nested file tree into a flat list.
  ///
  /// Mirrors the logic in `context_picker.dart` `_flattenTree`.
  /// Includes both files and directories so folder matches can appear.
  void _flattenTree(
    List<dynamic> nodes,
    String prefix,
    List<Map<String, dynamic>> result,
  ) {
    for (final node in nodes) {
      if (node is! Map<String, dynamic>) continue;
      final name = node['name'] as String? ?? '';
      final type = node['type'] as String? ?? '';
      final path = prefix.isEmpty ? name : '$prefix/$name';

      result.add({'name': name, 'path': path, 'type': type});

      if (type == 'dir') {
        final children = node['children'] as List? ?? [];
        _flattenTree(children, path, result);
      }
    }
  }

  /// Filter cached files by the current query (case-insensitive substring).
  ///
  /// Returns at most [kAutocompleteMaxResults] items. Only includes
  /// files (not directories) to match the autocomplete UX — users
  /// type `#filename` to reference files, not folders.
  List<Map<String, dynamic>> _filterResults() {
    if (_cachedFiles == null) return [];
    final q = widget.query.toLowerCase();
    if (q.isEmpty) return [];

    final matches = <Map<String, dynamic>>[];
    for (final file in _cachedFiles!) {
      final path = (file['path'] as String? ?? '').toLowerCase();
      if (path.contains(q)) {
        matches.add(file);
        if (matches.length >= kAutocompleteMaxResults) break;
      }
    }
    return matches;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      elevation: 4,
      color: colors.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        // Compact overlay: max 200px tall, full width from parent.
        constraints: const BoxConstraints(maxHeight: 200),
        child: _buildContent(),
      ),
    );
  }

  /// Build the overlay body: loading, empty state, or result list.
  Widget _buildContent() {
    final colors = context.colors;
    final typography = context.typography;

    // Loading state: file tree not yet received.
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final results = _filterResults();

    // Empty state: no matches.
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            S.of(context).widgetNoMatchingFiles,
            style: typography.bodySmall.copyWith(
              color: colors.onSurfaceMuted,
            ),
          ),
        ),
      );
    }

    // Result list.
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: results.length,
      itemBuilder: (ctx, i) {
        final item = results[i];
        final name = item['name'] as String? ?? '';
        final path = item['path'] as String? ?? '';
        final isDir = item['type'] == 'dir';

        return InkWell(
          onTap: () => _onItemSelected(path, isDir),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // File/folder icon.
                Icon(
                  isDir
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                // File name + path.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: typography.labelMedium.copyWith(
                          color: colors.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (path != name)
                        Text(
                          path,
                          style: typography.labelSmall.copyWith(
                            color: colors.onSurfaceMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Handle item selection: create a [ContextReference] and notify parent.
  void _onItemSelected(String path, bool isDir) {
    final ref = ContextReference(
      type: isDir ? ContextRefType.folder : ContextRefType.files,
      path: path,
    );
    _log.fine('自动补全选中: type=${ref.typeString}, path=$path');
    widget.onSelect(ref);
  }
}
