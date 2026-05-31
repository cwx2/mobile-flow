/// context_reference.dart — Structured context reference data models.
///
/// Defines [ContextReference], [LineRange], and [ContextRefType] for
/// attaching code context (files, folders, git diffs, etc.) to chat
/// messages. Replaces the previous formatted text string representation
/// (e.g., `#file:path`) with typed objects serialized to JSON for the
/// `context_references` field in `chat.send`.
///
/// See also: `context_picker.dart` which produces these objects,
/// and `websocket_service.dart` which stores them in
/// `pendingContextReferences`.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// App configuration constants for context references.
// These are compile-time constants since the App has no persistent config
// store (zero data storage principle). Could move to remote config later.
// ---------------------------------------------------------------------------

/// Maximum number of autocomplete results shown in the overlay.
const int kAutocompleteMaxResults = 8;

/// Maximum character length for the truncated path shown in context chips.
const int kChipPathMaxLength = 30;

/// Context reference type.
///
/// Each value maps to a protocol type string used in the `chat.send`
/// payload. The enum values match the existing `ContextRefType` in
/// `context_picker.dart` for backward compatibility.
enum ContextRefType {
  files,
  folder,
  currentFile,
  terminal,
  url,
  gitDiff,
  problems,
}

/// Line range for file references (e.g., lines 42–50).
///
/// Both [start] and [end] are 1-based inclusive line numbers.
/// Used when the user specifies a sub-range of a file via syntax
/// like `file.ts:42-50`.
class LineRange {
  /// First line (1-based, inclusive).
  final int start;

  /// Last line (1-based, inclusive).
  final int end;

  /// Create a line range.
  ///
  /// Both [start] and [end] must be positive, and [start] ≤ [end].
  const LineRange({required this.start, required this.end});

  /// Serialize to JSON for the `line_range` field in the protocol payload.
  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  /// Deserialize from a JSON map (e.g., from a protocol payload).
  factory LineRange.fromJson(Map<String, dynamic> json) => LineRange(
        start: json['start'] as int,
        end: json['end'] as int,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineRange && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'LineRange($start-$end)';
}

/// Structured reference to a code artifact attached to a chat message.
///
/// Replaces the previous formatted text string representation
/// (e.g., `#file:path`). Each reference carries a [type], a [path]
/// (file/folder path or URL), an optional [lineRange], and a unique
/// [id] for chip removal in the UI.
///
/// Serialized to JSON for the `context_references` array in the
/// `chat.send` WebSocket payload. The Agent-side `ContextResolver`
/// reads these and resolves them to actual file content.
class ContextReference {
  /// Unique identifier for this reference.
  ///
  /// Used by the UI to identify chips for removal. Auto-generated
  /// from the current timestamp in base-36 if not provided.
  final String id;

  /// The kind of context being referenced.
  final ContextRefType type;

  /// File path, folder path, or URL depending on [type].
  ///
  /// Empty string for types that don't need a path (terminal,
  /// git-diff, problems).
  final String path;

  /// Optional line range for file references.
  ///
  /// Only meaningful when [type] is [ContextRefType.files] or
  /// [ContextRefType.currentFile]. Null means the entire file.
  final LineRange? lineRange;

  /// Create a context reference.
  ///
  /// [id] is auto-generated if not provided. [type] and [path] are
  /// required. [lineRange] is optional and only applies to file types.
  ContextReference({
    String? id,
    required this.type,
    required this.path,
    this.lineRange,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toRadixString(36);

  /// Protocol type string for JSON serialization.
  ///
  /// Maps Dart enum values to the snake-case strings used in the
  /// WebSocket protocol (e.g., `files` → `"file"`,
  /// `gitDiff` → `"git-diff"`).
  String get typeString => switch (type) {
        ContextRefType.files => 'file',
        ContextRefType.folder => 'folder',
        ContextRefType.currentFile => 'current-file',
        ContextRefType.terminal => 'terminal',
        ContextRefType.url => 'url',
        ContextRefType.gitDiff => 'git-diff',
        ContextRefType.problems => 'problems',
      };

  /// Truncated display name for context chips.
  ///
  /// Shows the filename and its parent directory to give enough
  /// context without overflowing the chip. Paths longer than
  /// [kChipPathMaxLength] are truncated with a leading `…/`.
  ///
  /// Special cases:
  /// - Empty path: returns a human-readable label for the type.
  /// - URL: shows the URL, truncated if too long.
  /// - Paths with line ranges: appends `:start-end` to the name.
  String get displayName {
    // Types that don't use a path get a descriptive label.
    if (path.isEmpty) {
      return switch (type) {
        ContextRefType.terminal => 'Terminal',
        ContextRefType.gitDiff => 'Git Diff',
        ContextRefType.problems => 'Problems',
        ContextRefType.currentFile => 'Current File',
        _ => typeString,
      };
    }

    // Build the base name from the path.
    String name;
    if (type == ContextRefType.url) {
      // URLs: show as-is, truncate if too long.
      name = path;
    } else {
      // File/folder paths: show filename + parent dir.
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.length <= 1) {
        name = segments.isEmpty ? path : segments.last;
      } else {
        // e.g., "services/auth.py" from "src/services/auth.py"
        name = '${segments[segments.length - 2]}/${segments.last}';
      }
    }

    // Append line range suffix if present.
    if (lineRange != null) {
      name = '$name:${lineRange!.start}-${lineRange!.end}';
    }

    // Truncate to max length with leading ellipsis.
    if (name.length > kChipPathMaxLength) {
      // Keep the tail (most informative part: filename + range).
      name = '…${name.substring(name.length - kChipPathMaxLength + 1)}';
    }

    return name;
  }

  /// Icon for this reference type.
  ///
  /// Matches the icons used in [contextTypes] in `context_picker.dart`
  /// so chips and picker items look consistent.
  IconData get icon => switch (type) {
        ContextRefType.files => Icons.insert_drive_file_outlined,
        ContextRefType.folder => Icons.folder_outlined,
        ContextRefType.currentFile => Icons.description_outlined,
        ContextRefType.terminal => Icons.terminal,
        ContextRefType.url => Icons.language,
        ContextRefType.gitDiff => Icons.difference_outlined,
        ContextRefType.problems => Icons.warning_amber_outlined,
      };

  /// Serialize to JSON for the `context_references` array in `chat.send`.
  ///
  /// Uses [typeString] for the `type` field and includes `line_range`
  /// only when present.
  Map<String, dynamic> toJson() => {
        'type': typeString,
        'path': path,
        if (lineRange != null) 'line_range': lineRange!.toJson(),
      };

  /// Deserialize from a JSON map received in a protocol payload.
  ///
  /// Parses the `type` string back to [ContextRefType] and optionally
  /// reconstructs the [LineRange]. Generates a new [id] since IDs are
  /// local to the App session.
  factory ContextReference.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = _typeFromString(typeStr);
    final lineRangeJson = json['line_range'] as Map<String, dynamic>?;

    return ContextReference(
      type: type,
      path: json['path'] as String? ?? '',
      lineRange: lineRangeJson != null ? LineRange.fromJson(lineRangeJson) : null,
    );
  }

  /// Map a protocol type string back to the enum value.
  ///
  /// Inverse of [typeString]. Defaults to [ContextRefType.files] for
  /// unrecognized strings to avoid crashes on protocol evolution.
  static ContextRefType _typeFromString(String typeStr) => switch (typeStr) {
        'file' => ContextRefType.files,
        'folder' => ContextRefType.folder,
        'current-file' => ContextRefType.currentFile,
        'terminal' => ContextRefType.terminal,
        'url' => ContextRefType.url,
        'git-diff' => ContextRefType.gitDiff,
        'problems' => ContextRefType.problems,
        // Fallback for forward compatibility — unknown types treated as file.
        _ => ContextRefType.files,
      };

  @override
  String toString() =>
      'ContextReference(type: $typeString, path: $path, lineRange: $lineRange)';
}
