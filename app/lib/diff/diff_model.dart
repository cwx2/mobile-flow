/// diff_model.dart — Diff data models.
//
// Data structures for diff computation and rendering:
// - DiffLineType: line classification (context/added/deleted)
// - CharChange: inline character-level change range
// - DiffLine: single line diff info
// - DiffHunk: group of consecutive changed lines
// - DiffResult: complete diff output

/// Line type classification.
enum DiffLineType {
  context, // unchanged context line
  added, // newly added line
  deleted, // removed line
}

/// Inline character-level change (second layer of two-layer highlighting).
class CharChange {
  final int start; // start character position
  final int end; // end character position

  const CharChange(this.start, this.end);
}

/// Single diff line with metadata.
class DiffLine {
  final DiffLineType type;
  final String text;
  final int? oldLineNum; // old file line number (set for deleted/context)
  final int? newLineNum; // new file line number (set for added/context)
  final List<CharChange> charChanges; // inline character-level changes

  const DiffLine({
    required this.type,
    required this.text,
    this.oldLineNum,
    this.newLineNum,
    this.charChanges = const [],
  });
}

/// A group of consecutive changed lines (hunk).
class DiffHunk {
  final int oldStart; // old file start line number
  final int newStart; // new file start line number
  final List<DiffLine> lines; // context + changed lines

  const DiffHunk({
    required this.oldStart,
    required this.newStart,
    required this.lines,
  });

  /// Number of added lines in this hunk.
  int get addedCount => lines.where((l) => l.type == DiffLineType.added).length;

  /// Number of deleted lines in this hunk.
  int get deletedCount =>
      lines.where((l) => l.type == DiffLineType.deleted).length;
}

/// Complete diff result.
class DiffResult {
  final String filePath;
  final List<DiffHunk> hunks;
  final int totalAdded;
  final int totalDeleted;
  final int totalContext;

  const DiffResult({
    required this.filePath,
    required this.hunks,
    required this.totalAdded,
    required this.totalDeleted,
    required this.totalContext,
  });

  bool get hasChanges => hunks.isNotEmpty;
  List<DiffLine> get allLines => hunks.expand((h) => h.lines).toList();
}

/// Unchanged region used to collapse large blocks of unmodified code
/// in split diff mode.
class UnchangedRegion {
  final int originalStart; // old file start line number (1-based)
  final int modifiedStart; // new file start line number (1-based)
  final int lineCount; // number of unchanged lines

  // Expandable line counts (user can progressively reveal lines)
  int visibleTop; // lines revealed from the top
  int visibleBottom; // lines revealed from the bottom

  UnchangedRegion({
    required this.originalStart,
    required this.modifiedStart,
    required this.lineCount,
    this.visibleTop = 0,
    this.visibleBottom = 0,
  });

  /// Number of hidden lines.
  int get hiddenCount => lineCount - visibleTop - visibleBottom;

  /// Whether fully expanded.
  bool get isFullyExpanded => hiddenCount <= 0;

  /// Reveal more lines from the top.
  void showMoreAbove([int count = 10]) {
    visibleTop = (visibleTop + count).clamp(0, lineCount - visibleBottom);
  }

  /// Reveal more lines from the bottom.
  void showMoreBelow([int count = 10]) {
    visibleBottom = (visibleBottom + count).clamp(0, lineCount - visibleTop);
  }

  /// Expand all hidden lines.
  void showAll() {
    visibleTop = lineCount;
    visibleBottom = 0;
  }
}

/// Split diff result for full-file side-by-side comparison.
class SplitDiffResult {
  final String filePath;
  final List<String> oldLines;
  final List<String> newLines;

  /// Set of changed line numbers in the old file.
  final Set<int> deletedLineNums;

  /// Set of changed line numbers in the new file.
  final Set<int> addedLineNums;

  /// Old file character-level changes: line number → CharChange list.
  final Map<int, List<CharChange>> oldCharChanges;

  /// New file character-level changes: line number → CharChange list.
  final Map<int, List<CharChange>> newCharChanges;

  /// Unchanged regions (collapsible).
  final List<UnchangedRegion> unchangedRegions;

  /// Ordered change line numbers for navigation.
  final List<int> oldChangeLineNums;
  final List<int> newChangeLineNums;

  /// Statistics.
  final int totalAdded;
  final int totalDeleted;

  const SplitDiffResult({
    required this.filePath,
    required this.oldLines,
    required this.newLines,
    required this.deletedLineNums,
    required this.addedLineNums,
    required this.oldCharChanges,
    required this.newCharChanges,
    required this.unchangedRegions,
    required this.oldChangeLineNums,
    required this.newChangeLineNums,
    required this.totalAdded,
    required this.totalDeleted,
  });

  bool get hasChanges => deletedLineNums.isNotEmpty || addedLineNums.isNotEmpty;
}
