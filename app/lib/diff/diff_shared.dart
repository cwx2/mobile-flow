/// diff_shared.dart — Shared data classes, algorithms, and rendering for diff viewers.
///
/// Contains the line alignment algorithm, fold region management, syntax
/// highlighting pipeline, scroll sync, change navigation, and row rendering
/// widgets shared by [SplitDiffViewer] and [SideBySideDiffViewer].
///
/// Each viewer mixes in [DiffViewerMixin] for state logic and calls the
/// shared widget builders for consistent rendering.
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

import 'diff_minimap.dart';
import 'diff_model.dart';
import 'diff_theme.dart';

// Re-export types that viewers need from diff_model.
export 'diff_model.dart' show SplitDiffResult, CharChange;

// ── Data classes ──

enum DiffSide { old, new_ }

enum AlignedRowType { context, deleted, added, modified, fold }

/// A single aligned row in the diff display list.
///
/// For context/modified rows, both old and new line data are present.
/// For deleted rows, only old data is present (new is null → placeholder).
/// For added rows, only new data is present (old is null → placeholder).
class AlignedRow {
  final int? oldLineNum;
  final String? oldText;
  final int? newLineNum;
  final String? newText;
  final AlignedRowType type;
  final int foldCount;
  final int? foldIndex;

  const AlignedRow({
    this.oldLineNum,
    this.oldText,
    this.newLineNum,
    this.newText,
    required this.type,
  })  : foldCount = 0,
        foldIndex = null;

  const AlignedRow.fold(this.foldCount, this.foldIndex)
      : oldLineNum = null,
        oldText = null,
        newLineNum = null,
        newText = null,
        type = AlignedRowType.fold;
}

/// Collapsible region of unchanged lines.
class FoldRegion {
  final int startIndex;
  final int length;
  int visibleTop;
  int visibleBottom;

  FoldRegion({required this.startIndex, required this.length})
      : visibleTop = 0,
        visibleBottom = 0;

  /// Number of hidden lines (total minus context boundaries minus revealed).
  int get hiddenCount => length - 6 - visibleTop - visibleBottom;

  void showMoreAbove([int n = 10]) {
    visibleTop = (visibleTop + n).clamp(0, length - 6 - visibleBottom);
  }

  void showMoreBelow([int n = 10]) {
    visibleBottom = (visibleBottom + n).clamp(0, length - 6 - visibleTop);
  }

  void showAll() => visibleTop = length;
}

// ── Algorithms ──

/// Build aligned rows from a [SplitDiffResult].
///
/// Walks old and new lines in parallel, producing context/deleted/added/modified
/// rows with placeholder gaps for alignment.
List<AlignedRow> buildAlignedRows(SplitDiffResult diff) {
  final rows = <AlignedRow>[];
  int oi = 0, ni = 0;
  while (oi < diff.oldLines.length || ni < diff.newLines.length) {
    final oln = oi + 1, nln = ni + 1;
    final del = diff.deletedLineNums.contains(oln);
    final add = diff.addedLineNums.contains(nln);
    if (oi >= diff.oldLines.length) {
      rows.add(AlignedRow(newLineNum: nln, newText: diff.newLines[ni], type: AlignedRowType.added));
      ni++;
    } else if (ni >= diff.newLines.length) {
      rows.add(AlignedRow(oldLineNum: oln, oldText: diff.oldLines[oi], type: AlignedRowType.deleted));
      oi++;
    } else if (del && !add) {
      rows.add(AlignedRow(oldLineNum: oln, oldText: diff.oldLines[oi], type: AlignedRowType.deleted));
      oi++;
    } else if (!del && add) {
      rows.add(AlignedRow(newLineNum: nln, newText: diff.newLines[ni], type: AlignedRowType.added));
      ni++;
    } else if (del && add) {
      rows.add(AlignedRow(
          oldLineNum: oln, oldText: diff.oldLines[oi],
          newLineNum: nln, newText: diff.newLines[ni], type: AlignedRowType.modified));
      oi++; ni++;
    } else {
      rows.add(AlignedRow(
          oldLineNum: oln, oldText: diff.oldLines[oi],
          newLineNum: nln, newText: diff.newLines[ni], type: AlignedRowType.context));
      oi++; ni++;
    }
  }
  return rows;
}

/// Apply fold regions to aligned rows, producing the display list.
///
/// Returns a record of (displayRows, changeIndices, updatedFoldRegions).
/// On first call pass empty [foldRegions] to auto-detect foldable regions.
({List<AlignedRow> displayRows, List<int> changeIndices}) applyFolding(
    List<AlignedRow> alignedRows, List<FoldRegion> foldRegions,
    {int contextLines = 3}) {
  // Auto-detect fold regions on first call
  if (foldRegions.isEmpty) {
    int i = 0;
    while (i < alignedRows.length) {
      if (alignedRows[i].type == AlignedRowType.context) {
        final s = i;
        while (i < alignedRows.length && alignedRows[i].type == AlignedRowType.context) i++;
        if (i - s >= contextLines * 2 + 3) {
          foldRegions.add(FoldRegion(startIndex: s, length: i - s));
        }
      } else {
        i++;
      }
    }
  }

  final displayRows = <AlignedRow>[];
  final changeIndices = <int>[];
  int si = 0, fi = 0;
  while (si < alignedRows.length) {
    if (fi < foldRegions.length && si == foldRegions[fi].startIndex) {
      final r = foldRegions[fi];
      final h = r.hiddenCount;
      if (h <= 0) {
        for (int j = 0; j < r.length; j++) displayRows.add(alignedRows[si + j]);
      } else {
        final top = contextLines + r.visibleTop;
        for (int j = 0; j < top && j < r.length; j++) displayRows.add(alignedRows[si + j]);
        displayRows.add(AlignedRow.fold(h, fi));
        final bs = r.length - contextLines - r.visibleBottom;
        for (int j = max(bs, top); j < r.length; j++) displayRows.add(alignedRows[si + j]);
      }
      si += r.length;
      fi++;
    } else {
      final isChange = alignedRows[si].type != AlignedRowType.context;
      final prevIsChange = displayRows.isNotEmpty &&
          displayRows.last.type != AlignedRowType.context &&
          displayRows.last.type != AlignedRowType.fold;
      if (isChange && !prevIsChange) changeIndices.add(displayRows.length);
      displayRows.add(alignedRows[si]);
      si++;
    }
  }
  return (displayRows: displayRows, changeIndices: changeIndices);
}

// ── Syntax highlighting ──

/// Parse and highlight code, returning per-line TextSpan lists.
List<List<TextSpan>> highlightLines(
    String code, String lang, Map<String, TextStyle> hlTheme) {
  if (code.isEmpty) return [];
  final r = highlight.parse(code, language: lang);
  final s = <TextSpan>[];
  _flatten(r.nodes ?? [], s, hlTheme);
  return _splitByLine(s);
}

void _flatten(List<Node> nodes, List<TextSpan> spans,
    Map<String, TextStyle> theme, [String? parent]) {
  for (final n in nodes) {
    final c = n.className ?? parent;
    if (n.children != null && n.children!.isNotEmpty) {
      _flatten(n.children!, spans, theme, c);
    } else {
      final t = n.value ?? '';
      if (t.isNotEmpty) {
        spans.add(TextSpan(
            text: t,
            style: c != null ? theme[c] ?? const TextStyle() : const TextStyle()));
      }
    }
  }
}

List<List<TextSpan>> _splitByLine(List<TextSpan> spans) {
  final lines = <List<TextSpan>>[[]];
  for (final s in spans) {
    final parts = (s.text ?? '').split('\n');
    for (int i = 0; i < parts.length; i++) {
      if (i > 0) lines.add([]);
      if (parts[i].isNotEmpty) lines.last.add(TextSpan(text: parts[i], style: s.style));
    }
  }
  return lines;
}

// ── Shared widget builders ──

/// Build a syntax-highlighted or plain text widget for a code line.
Widget buildSyntaxWidget(String text, List<TextSpan> spans, bool changed,
    {bool wordWrap = false, double fontSize = 11}) {
  final c = changed ? const Color(0xFFE0DEF4) : DiffTheme.contextText;
  final st = TextStyle(fontSize: fontSize, fontFamily: DiffTheme.fontFamily, color: c);
  if (spans.isEmpty || text.isEmpty) {
    return Text(text.isEmpty ? ' ' : text,
        style: st,
        overflow: wordWrap ? TextOverflow.visible : TextOverflow.clip,
        maxLines: wordWrap ? null : 1, softWrap: wordWrap);
  }
  return RichText(
      text: TextSpan(style: st, children: spans),
      overflow: wordWrap ? TextOverflow.visible : TextOverflow.clip,
      maxLines: wordWrap ? null : 1, softWrap: wordWrap);
}

/// Build a character-level diff highlighted widget.
Widget buildCharHighlightWidget(String text, List<CharChange> changes,
    Color cbg, Color tc, {bool wordWrap = false, double fontSize = 11}) {
  final spans = <InlineSpan>[];
  int p = 0;
  final st = TextStyle(fontSize: fontSize, fontFamily: DiffTheme.fontFamily, color: tc);
  for (final c in changes) {
    if (p < c.start) spans.add(TextSpan(text: text.substring(p, c.start), style: st));
    spans.add(TextSpan(
        text: text.substring(c.start, min(c.end, text.length)),
        style: st.copyWith(backgroundColor: cbg)));
    p = c.end;
  }
  if (p < text.length) spans.add(TextSpan(text: text.substring(p), style: st));
  return RichText(
      text: TextSpan(children: spans),
      overflow: wordWrap ? TextOverflow.visible : TextOverflow.clip,
      maxLines: wordWrap ? null : 1, softWrap: wordWrap);
}

/// Build a fold row widget (collapsed unchanged region).
Widget buildFoldRow(AlignedRow row, {
  required VoidCallback? onExpandAll,
  required VoidCallback? onExpandAbove,
  required VoidCallback? onExpandBelow,
}) {
  return Container(
    height: 20,
    color: DiffTheme.foldedBg,
    child: Row(children: [
      const SizedBox(width: 4),
      GestureDetector(
          onTap: onExpandAbove,
          child: const Icon(Icons.keyboard_arrow_up, size: 14, color: DiffTheme.foldedText)),
      const SizedBox(width: 2),
      Expanded(
        child: GestureDetector(
          onTap: onExpandAll,
          child: Text('··· ${row.foldCount} lines ···',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10, color: DiffTheme.foldedText,
                  fontFamily: DiffTheme.fontFamily, fontStyle: FontStyle.italic)),
        ),
      ),
      const SizedBox(width: 2),
      GestureDetector(
          onTap: onExpandBelow,
          child: const Icon(Icons.keyboard_arrow_down, size: 14, color: DiffTheme.foldedText)),
      const SizedBox(width: 4),
    ]),
  );
}

/// Default font size for split diff viewer (portrait, full-width panels).
const kSplitDiffFontSize = 11.0;

/// Default font size for side-by-side diff viewer (landscape, half-width panels).
const kSideBySideDiffFontSize = 10.0;

/// Minimum font size for diff viewers (pinch-to-zoom lower bound).
const kDiffMinFontSize = 8.0;

/// Maximum font size for diff viewers (pinch-to-zoom upper bound).
const kDiffMaxFontSize = 18.0;

/// Font size step for A+/A- toolbar buttons.
const kDiffFontSizeStep = 1.0;

/// Font zoom controller for diff viewers.
///
/// Encapsulates pinch-to-zoom and A+/A- button logic so both
/// [SplitDiffViewer] and [SideBySideDiffViewer] share the same
/// implementation without code duplication.
///
/// Usage: create an instance with the default font size, wire
/// [onScaleStart]/[onScaleUpdate] to a [GestureDetector], and
/// call [fontSizeUp]/[fontSizeDown] from toolbar buttons.
/// Read [fontSize] for the current value and [itemExtent] for
/// the scaled row height.
class DiffFontZoom {
  final double _defaultSize;
  final VoidCallback _onChanged;
  double _fontSize;
  double _baseFontSize;

  DiffFontZoom({
    required double defaultSize,
    required VoidCallback onChanged,
  })  : _defaultSize = defaultSize,
        _fontSize = defaultSize,
        _baseFontSize = defaultSize,
        _onChanged = onChanged;

  /// Current font size.
  double get fontSize => _fontSize;

  /// Row height scaled proportionally to font size (base 20px).
  double get itemExtent => (_fontSize / _defaultSize * 20).roundToDouble();

  /// Call from [GestureDetector.onScaleStart].
  void onScaleStart(ScaleStartDetails _) {
    _baseFontSize = _fontSize;
  }

  /// Call from [GestureDetector.onScaleUpdate].
  ///
  /// Ignores single-finger drags (scale stays at 1.0) so vertical
  /// and horizontal scrolling are not affected.
  void onScaleUpdate(ScaleUpdateDetails details) {
    if (details.scale == 1.0) return;
    _fontSize = (_baseFontSize * details.scale)
        .clamp(kDiffMinFontSize, kDiffMaxFontSize);
    _onChanged();
  }

  /// Increase font size by one step (A+ button).
  void fontSizeUp() {
    _fontSize = (_fontSize + kDiffFontSizeStep)
        .clamp(kDiffMinFontSize, kDiffMaxFontSize);
    _onChanged();
  }

  /// Decrease font size by one step (A- button).
  void fontSizeDown() {
    _fontSize = (_fontSize - kDiffFontSizeStep)
        .clamp(kDiffMinFontSize, kDiffMaxFontSize);
    _onChanged();
  }
}

/// Monospace character width ratio (char width ≈ fontSize * this ratio).
///
/// Empirically measured for the Fira Code / JetBrains Mono family used
/// by [DiffTheme.fontFamily]. Slightly conservative to avoid clipping.
const kMonospaceWidthRatio = 0.6;

/// Estimate the horizontal content width for a diff panel.
///
/// Used by both [SplitDiffViewer] and [SideBySideDiffViewer] to set the
/// [SizedBox] width inside the horizontal [SingleChildScrollView], so
/// the [ListView] knows the content boundary for non-wrapping mode.
///
/// [lineNumColumnWidth] is the gutter width (line number column + marker).
/// [maxLineLength] is the longest line's character count.
/// [fontSize] is the monospace font size used for code rendering.
double estimateDiffContentWidth({
  required double lineNumColumnWidth,
  required int maxLineLength,
  required double fontSize,
}) {
  final charWidth = fontSize * kMonospaceWidthRatio;
  // gutter (3px marker + lineNumCol + 3px gap) + code + 20px right padding
  return 3 + lineNumColumnWidth + 3 + (maxLineLength * charWidth) + 20;
}

/// Build a single code row widget.
Widget buildCodeRow({
  required AlignedRow row,
  required DiffSide side,
  required int lineNumWidth,
  required Color tint,
  required Color lineBg,
  required Color charBg,
  required SplitDiffResult diff,
  required List<List<TextSpan>> hlSpans,
  required bool wordWrap,
  double fontSize = 11,
  double lineNumColumnWidth = 0,
}) {
  final ln = side == DiffSide.old ? row.oldLineNum : row.newLineNum;
  final tx = side == DiffSide.old ? row.oldText : row.newText;
  final placeholder = tx == null;
  final changed = side == DiffSide.old
      ? (row.type == AlignedRowType.deleted || row.type == AlignedRowType.modified)
      : (row.type == AlignedRowType.added || row.type == AlignedRowType.modified);

  // Row height scales with font size (base 20px at default 11px font)
  final rowH = (fontSize / kSplitDiffFontSize * 20).roundToDouble();

  if (placeholder) {
    return Container(
        height: wordWrap ? null : rowH,
        constraints: wordWrap ? BoxConstraints(minHeight: rowH) : null,
        color: DiffTheme.foldedBg.withValues(alpha: 0.3));
  }

  final cMap = side == DiffSide.old ? diff.oldCharChanges : diff.newCharChanges;
  final chars = ln != null ? cMap[ln] : null;
  final hi = (ln ?? 0) - 1;
  final spans = (hi >= 0 && hi < hlSpans.length) ? hlSpans[hi] : <TextSpan>[];

  Widget code = (chars != null && chars.isNotEmpty)
      ? buildCharHighlightWidget(tx, chars, charBg,
          changed ? const Color(0xFFE0DEF4) : DiffTheme.contextText,
          wordWrap: wordWrap, fontSize: fontSize)
      : buildSyntaxWidget(tx, spans, changed,
          wordWrap: wordWrap, fontSize: fontSize);

  // Use caller-provided column width, or compute a default
  final lnColWidth = lineNumColumnWidth > 0
      ? lineNumColumnWidth
      : lineNumWidth * 8.0 + 8;

  return Container(
    height: wordWrap ? null : rowH,
    constraints: wordWrap ? BoxConstraints(minHeight: rowH) : null,
    color: changed ? lineBg : Colors.transparent,
    child: Row(
      crossAxisAlignment: wordWrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Container(width: 3, color: changed ? tint : Colors.transparent),
        Container(
          width: lnColWidth,
          padding: const EdgeInsets.only(right: 3, top: 2),
          color: changed ? tint.withValues(alpha: 0.12) : DiffTheme.lineNumBg,
          alignment: Alignment.topRight,
          child: Text(ln?.toString() ?? '',
              style: TextStyle(
                  fontSize: fontSize - 1, fontFamily: DiffTheme.fontFamily,
                  color: changed ? tint : DiffTheme.lineNumText)),
        ),
        const SizedBox(width: 3),
        Expanded(child: code),
      ],
    ),
  );
}

/// Build the diff toolbar widget.
Widget buildDiffToolbar({
  required String filePath,
  required int totalAdded,
  required int totalDeleted,
  required List<int> changeIndices,
  required int currentChangeIdx,
  required bool wordWrap,
  required VoidCallback onPrev,
  required VoidCallback onNext,
  required VoidCallback onToggleWrap,
  VoidCallback? onFontSizeUp,
  VoidCallback? onFontSizeDown,
  double? fontSize,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    color: DiffTheme.hunkHeaderBg,
    child: Row(children: [
      if (filePath.isNotEmpty)
        Expanded(
          child: Text(filePath.split('/').last,
              style: const TextStyle(
                  fontSize: 13, color: DiffTheme.hunkHeaderText,
                  fontFamily: DiffTheme.fontFamily),
              overflow: TextOverflow.ellipsis),
        ),
      Text('+$totalAdded',
          style: const TextStyle(
              fontSize: 12, color: DiffTheme.addedGutter, fontWeight: FontWeight.bold)),
      const SizedBox(width: 4),
      Text('-$totalDeleted',
          style: const TextStyle(
              fontSize: 12, color: DiffTheme.deletedGutter, fontWeight: FontWeight.bold)),
      const SizedBox(width: 8),
      if (changeIndices.isNotEmpty)
        Text('${currentChangeIdx >= 0 ? currentChangeIdx + 1 : '-'}/${changeIndices.length}',
            style: const TextStyle(
                fontSize: 11, color: DiffTheme.hunkHeaderText, fontFamily: DiffTheme.fontFamily)),
      const SizedBox(width: 4),
      GestureDetector(onTap: onPrev,
          child: const Icon(Icons.keyboard_arrow_up, size: 20, color: DiffTheme.hunkHeaderText)),
      GestureDetector(onTap: onNext,
          child: const Icon(Icons.keyboard_arrow_down, size: 20, color: DiffTheme.hunkHeaderText)),
      const SizedBox(width: 4),
      // Font size controls (A- / A+)
      if (onFontSizeDown != null)
        SizedBox(
          width: 32, height: 32,
          child: GestureDetector(
              onTap: onFontSizeDown,
              behavior: HitTestBehavior.opaque,
              child: const Center(
                child: Text('A-', style: TextStyle(
                    fontSize: 12, color: DiffTheme.hunkHeaderText,
                    fontWeight: FontWeight.bold)),
              )),
        ),
      if (fontSize != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Text('${fontSize.round()}',
              style: const TextStyle(
                  fontSize: 10, color: DiffTheme.hunkHeaderText,
                  fontFamily: DiffTheme.fontFamily)),
        ),
      if (onFontSizeUp != null)
        SizedBox(
          width: 32, height: 32,
          child: GestureDetector(
              onTap: onFontSizeUp,
              behavior: HitTestBehavior.opaque,
              child: const Center(
                child: Text('A+', style: TextStyle(
                    fontSize: 12, color: DiffTheme.hunkHeaderText,
                    fontWeight: FontWeight.bold)),
              )),
        ),
      const SizedBox(width: 4),
      GestureDetector(
          onTap: onToggleWrap,
          child: Icon(wordWrap ? Icons.wrap_text : Icons.short_text,
              size: 18,
              color: wordWrap ? const Color(0xFFC4A7E7) : DiffTheme.hunkHeaderText)),
    ]),
  );
}

/// Build change markers for the minimap.
List<ChangeMarker> buildChangeMarkers(
    List<AlignedRow> displayRows, DiffSide side) {
  final markers = <ChangeMarker>[];
  for (int i = 0; i < displayRows.length; i++) {
    final r = displayRows[i];
    if (side == DiffSide.old &&
        (r.type == AlignedRowType.deleted || r.type == AlignedRowType.modified)) {
      markers.add(ChangeMarker(index: i,
          type: r.type == AlignedRowType.modified ? ChangeType.modified : ChangeType.deleted));
    } else if (side == DiffSide.new_ &&
        (r.type == AlignedRowType.added || r.type == AlignedRowType.modified)) {
      markers.add(ChangeMarker(index: i,
          type: r.type == AlignedRowType.modified ? ChangeType.modified : ChangeType.added));
    }
  }
  return markers;
}

// ── Drag divider ──

/// Drag divider between diff panels (horizontal or vertical).
///
/// A thin line with a circular handle in the center. Press-and-hold
/// highlights the line and handle, then drag to resize. Double-tap
/// resets to 50/50. Touch target is 28dp (Material minimum) while
/// the visible line is only 1px.
///
/// [axis] controls the drag direction and visual orientation:
/// - [Axis.vertical] → horizontal line, vertical drag (top/bottom split)
/// - [Axis.horizontal] → vertical line, horizontal drag (left/right split)
class DiffDragDivider extends StatefulWidget {
  final Axis axis;
  final ValueChanged<double> onDrag;
  final VoidCallback onDoubleTap;

  const DiffDragDivider({
    super.key,
    required this.axis,
    required this.onDrag,
    required this.onDoubleTap,
  });

  @override
  State<DiffDragDivider> createState() => _DiffDragDividerState();
}

class _DiffDragDividerState extends State<DiffDragDivider> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final lineColor = _active ? const Color(0xFF43E6C3) : const Color(0xFF393952);
    final handleColor = _active ? const Color(0xFF43E6C3) : const Color(0xFF6E6A86);
    final isVerticalDrag = widget.axis == Axis.vertical;

    return GestureDetector(
      onVerticalDragStart: isVerticalDrag ? (_) => setState(() => _active = true) : null,
      onVerticalDragUpdate: isVerticalDrag ? (d) => widget.onDrag(d.delta.dy) : null,
      onVerticalDragEnd: isVerticalDrag ? (_) => setState(() => _active = false) : null,
      onVerticalDragCancel: isVerticalDrag ? () => setState(() => _active = false) : null,
      onHorizontalDragStart: !isVerticalDrag ? (_) => setState(() => _active = true) : null,
      onHorizontalDragUpdate: !isVerticalDrag ? (d) => widget.onDrag(d.delta.dx) : null,
      onHorizontalDragEnd: !isVerticalDrag ? (_) => setState(() => _active = false) : null,
      onHorizontalDragCancel: !isVerticalDrag ? () => setState(() => _active = false) : null,
      onDoubleTap: widget.onDoubleTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: isVerticalDrag ? double.infinity : 28,
        height: isVerticalDrag ? 28 : double.infinity,
        child: Center(
          child: Stack(alignment: Alignment.center, children: [
            // Line
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isVerticalDrag ? double.infinity : (_active ? 2 : 1),
              height: isVerticalDrag ? (_active ? 2 : 1) : double.infinity,
              color: lineColor,
            ),
            // Handle
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _active ? 20 : 16,
              height: _active ? 20 : 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10182A),
                border: Border.all(color: handleColor, width: 1.5),
              ),
              child: Icon(Icons.drag_handle,
                  size: _active ? 12 : 10, color: handleColor),
            ),
          ]),
        ),
      ),
    );
  }
}
