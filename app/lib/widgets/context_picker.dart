/// context_picker.dart — Context reference picker (# menu).
///
/// Replicates the IDE's # context reference system.
/// Tap # → show context type list → select type → show sub-picker →
/// return a structured [ContextReference] object.
///
/// Supported context types (matching IDE):
///   - Files: search project files (supports line ranges: file.ts:42-50)
///   - Folder: select project folder
///   - Current File: reference the currently viewed file
///   - Terminal: reference terminal output
///   - URL: input a web URL
///   - Git Diff: reference current git changes
///   - Problems: reference current problems/errors
///
/// Previously returned formatted text strings (e.g., `#file:path`).
/// Now returns typed [ContextReference] objects — the Agent resolves
/// actual content on its side (lightweight reference pattern).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/context_reference.dart';
import '../models/payloads/file_payloads.g.dart';
import '../models/protocol.dart';
import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';

final _log = getLogger('ContextPicker');

/// Context type definition for the UI type picker list.
///
/// Maps each [ContextRefType] to a human-readable label, hint text,
/// and icon for display in the bottom sheet type selector.
class ContextTypeItem {
  final ContextRefType type;
  final String label;
  final String hint;
  final IconData icon;

  const ContextTypeItem({
    required this.type,
    required this.label,
    required this.hint,
    required this.icon,
  });
}

/// All context types (ordered to match IDE screenshot).
List<ContextTypeItem> getContextTypes(BuildContext context) {
  final s = S.of(context);
  return [
  ContextTypeItem(
    type: ContextRefType.files,
    label: 'Files',
    hint: s.contextPickerFilesHint,
    icon: Icons.insert_drive_file_outlined,
  ),
  ContextTypeItem(
    type: ContextRefType.folder,
    label: 'Folder',
    hint: s.contextPickerFolderHint,
    icon: Icons.folder_outlined,
  ),
  ContextTypeItem(
    type: ContextRefType.currentFile,
    label: 'Current File',
    hint: s.contextPickerCurrentFileHint,
    icon: Icons.description_outlined,
  ),
  ContextTypeItem(
    type: ContextRefType.terminal,
    label: 'Terminal',
    hint: s.contextPickerTerminalHint,
    icon: Icons.terminal,
  ),
  ContextTypeItem(
    type: ContextRefType.url,
    label: 'URL',
    hint: s.contextPickerUrlHint,
    icon: Icons.language,
  ),
  ContextTypeItem(
    type: ContextRefType.gitDiff,
    label: 'Git Diff',
    hint: s.contextPickerGitDiffHint,
    icon: Icons.difference_outlined,
  ),
  ContextTypeItem(
    type: ContextRefType.problems,
    label: 'Problems',
    hint: s.contextPickerProblemsHint,
    icon: Icons.warning_amber_outlined,
  ),
];
}

/// Context reference picker — two-step interaction.
///
/// 1. Show type list (Files/Folder/Terminal/URL/...)
/// 2. Select type → show sub-picker → return [ContextReference]
///
/// Returns a structured [ContextReference] object instead of the
/// previous formatted text strings. The Agent resolves actual content
/// from these lightweight descriptors.
class ContextPicker {
  final WebSocketService ws;
  final BuildContext context;

  /// Currently viewed file path (for Current File reference).
  final String? currentFilePath;

  ContextPicker({
    required this.ws,
    required this.context,
    this.currentFilePath,
  });

  /// Show the context type picker, returns a [ContextReference] or null.
  Future<ContextReference?> show() async {
    final type = await _showTypePicker();
    if (type == null) return null;
    return _handleType(type);
  }

  /// Step 1: Show the type list.
  Future<ContextRefType?> _showTypePicker() {
    return showModalBottomSheet<ContextRefType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        final colors = sheetCtx.colors;
        final spacing = sheetCtx.spacing;

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  S.of(context).contextPickerTitle,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  S.of(context).contextPickerSubtitle,
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceMuted),
                ),
              ),
              SizedBox(height: spacing.xs),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: spacing.sm),
                itemCount: getContextTypes(context).length,
                itemBuilder: (_, i) {
                  final item = getContextTypes(context)[i];
                  return ListTile(
                    leading: Icon(item.icon,
                        size: 20, color: colors.onSurfaceVariant),
                    title: Text(item.label,
                        style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      item.hint,
                      style: TextStyle(
                          fontSize: 11, color: colors.onSurfaceMuted),
                    ),
                    dense: true,
                    onTap: () => Navigator.pop(sheetCtx, item.type),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Step 2: Dispatch to the appropriate sub-picker by type.
  Future<ContextReference?> _handleType(ContextRefType type) async {
    switch (type) {
      case ContextRefType.files:
        return _pickFile();
      case ContextRefType.folder:
        return _pickFolder();
      case ContextRefType.currentFile:
        return _pickCurrentFile();
      case ContextRefType.terminal:
        return _pickTerminal();
      case ContextRefType.url:
        return _pickUrl();
      case ContextRefType.gitDiff:
        return _pickGitDiff();
      case ContextRefType.problems:
        return ContextReference(type: ContextRefType.problems, path: '');
    }
  }

  /// Parse line range syntax from a file path string.
  ///
  /// Supports patterns like:
  ///   - `file.ts:42`     → LineRange(start: 42, end: 42)
  ///   - `file.ts:42-50`  → LineRange(start: 42, end: 50)
  ///   - `file.ts`        → null (no line range)
  ///
  /// Returns a record of (path, lineRange) where lineRange may be null.
  static (String, LineRange?) parseLineRange(String input) {
    // Match trailing `:digits` or `:digits-digits`
    final match = RegExp(r'^(.+?):(\d+)(?:-(\d+))?$').firstMatch(input);
    if (match == null) return (input, null);

    final path = match.group(1)!;
    final start = int.parse(match.group(2)!);
    final end = match.group(3) != null ? int.parse(match.group(3)!) : start;

    // Validate: start and end must be positive, start ≤ end
    if (start <= 0 || end <= 0 || start > end) return (input, null);

    return (path, LineRange(start: start, end: end));
  }

  /// Files: search project files, return [ContextReference] with optional line range.
  Future<ContextReference?> _pickFile() async {
    final completer = Completer<ContextReference?>();
    ws.fileOps.requestFileTree(depth: 3);

    late StreamSubscription sub;
    sub = ws.messageStream.listen((msg) {
      if (msg.type == MessageType.fileTreeResult) {
        sub.cancel();
        final p = FileTreeResultPayload.fromJson(msg.payload);
        final tree = p.data;
        if (!context.mounted) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }

        final files = <Map<String, dynamic>>[];
        _flattenTree(tree, '', files);

        _showFileSearchSheet(files).then((selected) {
          if (!completer.isCompleted) {
            if (selected == null) {
              completer.complete(null);
              return;
            }
            // Parse optional line range from the selected path string
            final (path, lineRange) = parseLineRange(selected);
            completer.complete(ContextReference(
              type: ContextRefType.files,
              path: path,
              lineRange: lineRange,
            ));
          }
        });
      }
    });

    // Timeout protection
    Future.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.complete(null);
      }
    });

    return completer.future;
  }

  /// Flatten the file tree into a flat list.
  void _flattenTree(
      List<dynamic> nodes, String prefix, List<Map<String, dynamic>> result) {
    for (final node in nodes) {
      if (node is! Map<String, dynamic>) continue;
      final name = node['name'] as String? ?? '';
      final type = node['type'] as String? ?? '';
      final path = prefix.isEmpty ? name : '$prefix/$name';

      if (type == 'dir') {
        // Include directories (used by folder picker too)
        result.add({'name': name, 'path': path, 'type': 'dir'});
        final children = node['children'] as List? ?? [];
        _flattenTree(children, path, result);
      } else {
        result.add({'name': name, 'path': path, 'type': 'file'});
      }
    }
  }

  /// File search bottom sheet (with search field).
  ///
  /// Returns the raw selected string which may include line range
  /// syntax (e.g., `src/auth.py:42-50`). The caller parses it.
  Future<String?> _showFileSearchSheet(List<Map<String, dynamic>> allFiles) {
    final files = allFiles.where((f) => f['type'] == 'file').toList();
    final searchController = TextEditingController();
    final colors = context.colors;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollCtrl) => StatefulBuilder(
          builder: (ctx, setSheetState) {
            final query = searchController.text.toLowerCase();
            final filtered = query.isEmpty
                ? files
                : files.where((f) {
                    final path = (f['path'] as String? ?? '').toLowerCase();
                    return path.contains(query);
                  }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: S.of(context).contextPickerFilesHint,
                      hintStyle:
                          TextStyle(fontSize: 13, color: colors.onSurfaceMuted),
                      prefixIcon: Icon(Icons.search,
                          size: 18, color: colors.onSurfaceVariant),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (_) => setSheetState(() {}),
                    onSubmitted: (value) {
                      // Allow direct input with line range syntax
                      if (value.trim().isNotEmpty) {
                        Navigator.pop(ctx, value.trim());
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        S.of(context).contextPickerFileCount(filtered.length),
                        style: TextStyle(
                            fontSize: 11, color: colors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final file = filtered[i];
                      final path = file['path'] as String? ?? '';
                      final name = file['name'] as String? ?? '';
                      return ListTile(
                        leading: Icon(Icons.insert_drive_file_outlined,
                            size: 16, color: colors.onSurfaceVariant),
                        title: Text(name, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(path,
                            style: TextStyle(
                                fontSize: 10, color: colors.onSurfaceMuted)),
                        dense: true,
                        onTap: () => Navigator.pop(ctx, path),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Folder: select a project folder.
  Future<ContextReference?> _pickFolder() async {
    final completer = Completer<ContextReference?>();
    ws.fileOps.requestFileTree(depth: 3);

    late StreamSubscription sub;
    sub = ws.messageStream.listen((msg) {
      if (msg.type == MessageType.fileTreeResult) {
        sub.cancel();
        final p = FileTreeResultPayload.fromJson(msg.payload);
        final tree = p.data;
        if (!context.mounted) {
          completer.complete(null);
          return;
        }

        final allItems = <Map<String, dynamic>>[];
        _flattenTree(tree, '', allItems);
        final folders = allItems.where((f) => f['type'] == 'dir').toList();

        showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: context.colors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (sheetCtx) {
            final maxHeight = MediaQuery.sizeOf(sheetCtx).height * 0.82;
            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(S.of(context).contextPickerFolderHint,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: folders.isEmpty
                          ? Center(
                              child: Text(
                                S.of(context).contextPickerNoFolders,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: sheetCtx.colors.onSurfaceMuted,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: folders.length,
                              itemBuilder: (_, i) {
                                final path =
                                    folders[i]['path'] as String? ?? '';
                                return ListTile(
                                  leading: Icon(Icons.folder_outlined,
                                      size: 20, color: sheetCtx.colors.warning),
                                  title: Text(path,
                                      style: const TextStyle(fontSize: 13)),
                                  dense: true,
                                  onTap: () => Navigator.pop(sheetCtx, path),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ).then((selected) {
          if (selected != null) {
            completer.complete(ContextReference(
              type: ContextRefType.folder,
              path: selected,
            ));
          } else {
            completer.complete(null);
          }
        });
      }
    });

    // Timeout protection
    Future.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.complete(null);
      }
    });

    return completer.future;
  }

  /// Current File: return a reference to the currently viewed file.
  Future<ContextReference?> _pickCurrentFile() async {
    if (currentFilePath != null && currentFilePath!.isNotEmpty) {
      return ContextReference(
        type: ContextRefType.currentFile,
        path: currentFilePath!,
      );
    }
    if (context.mounted) {
      AppToast.show(context, S.of(context).contextPickerNoCurrentFile);
    }
    return null;
  }

  /// Terminal: return a lightweight terminal reference.
  ///
  /// The Agent resolves actual terminal content on its side.
  /// Only checks that terminal output exists; does not fetch content.
  Future<ContextReference?> _pickTerminal() async {
    final outputs = ws.terminalOutputs;
    if (outputs.isEmpty) {
      if (context.mounted) {
        AppToast.show(context, S.of(context).contextPickerNoTerminalOutput);
      }
      return null;
    }

    // Single terminal — return reference directly
    if (outputs.length == 1) {
      return ContextReference(type: ContextRefType.terminal, path: '');
    }

    // Multiple terminals — let user choose, but still return lightweight ref
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        final maxHeight = MediaQuery.sizeOf(sheetCtx).height * 0.82;
        final terminals = outputs.entries.toList();
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              children: [
                    Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(S.of(context).contextPickerSelectTerminal,
                      style:
                          const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: terminals.length,
                    itemBuilder: (_, i) {
                      final e = terminals[i];
                      return ListTile(
                        leading: Icon(Icons.terminal,
                            size: 20, color: sheetCtx.colors.secondary),
                        title: Text(S.of(context).contextPickerTerminalN(e.key),
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          S.of(context).contextPickerTerminalLines(e.value.length),
                          style: TextStyle(
                            fontSize: 11,
                            color: sheetCtx.colors.onSurfaceMuted,
                          ),
                        ),
                        onTap: () => Navigator.pop(sheetCtx, e.key),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return null;
    // Path carries the terminal ID so the Agent can resolve the right one
    return ContextReference(type: ContextRefType.terminal, path: selected);
  }

  /// URL: input a web URL.
  Future<ContextReference?> _pickUrl() async {
    final controller = TextEditingController();
    final colors = context.colors;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(S.of(context).contextPickerEnterUrl, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'https://...',
            hintStyle: TextStyle(color: colors.onSurfaceMuted),
          ),
          keyboardType: TextInputType.url,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).commonCancel, style: TextStyle(color: colors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(S.of(context).commonConfirm, style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      return ContextReference(type: ContextRefType.url, path: result);
    }
    return null;
  }

  /// Git Diff: return a lightweight git-diff reference.
  ///
  /// The Agent resolves actual diff content on its side.
  /// No longer fetches diff content in the App — just returns the
  /// reference descriptor for the Agent to resolve.
  Future<ContextReference?> _pickGitDiff() async {
    _log.fine('📋 git diff 引用已创建（Agent 端解析内容）');
    return ContextReference(type: ContextRefType.gitDiff, path: '');
  }
}
