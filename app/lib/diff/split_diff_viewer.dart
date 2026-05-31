/// split_diff_viewer.dart — Split diff viewer (top/bottom comparison).
///
/// Portrait-optimized diff layout:
/// - Top panel: old file (BEFORE), bottom panel: new file (AFTER)
/// - Synchronized vertical scrolling
/// - Draggable horizontal divider to resize panels
/// - All diff logic (alignment, folding, highlighting) from [diff_shared.dart]
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/code_theme.dart';
import '../utils/language_detect.dart';
import 'diff_engine.dart';
import 'diff_minimap.dart';
import 'diff_shared.dart';
import 'diff_theme.dart';

// Re-export SplitDiffResult so callers don't need a separate import.
export 'diff_model.dart' show SplitDiffResult;

/// Top/bottom split diff viewer for portrait orientation.
class SplitDiffViewer extends StatefulWidget {
  final String oldText;
  final String newText;
  final String filePath;

  const SplitDiffViewer({
    super.key,
    required this.oldText,
    required this.newText,
    this.filePath = '',
  });

  @override
  State<SplitDiffViewer> createState() => _SplitDiffViewerState();
}

class _SplitDiffViewerState extends State<SplitDiffViewer> {
  final _oldScroll = ScrollController();
  final _newScroll = ScrollController();
  final _oldHScroll = ScrollController();
  final _newHScroll = ScrollController();
  bool _syncing = false;
  bool _hSyncing = false;
  bool _wordWrap = false;
  double _splitRatio = 0.5;
  late final DiffFontZoom _fontZoom = DiffFontZoom(
    defaultSize: kSplitDiffFontSize,
    onChanged: () => setState(() {}),
  );

  late SplitDiffResult _diff;
  late List<AlignedRow> _alignedRows;
  late List<AlignedRow> _displayRows;
  late List<FoldRegion> _foldRegions;
  late List<int> _changeIndices;
  int _currentChangeIdx = -1;
  late List<List<TextSpan>> _oldHl;
  late List<List<TextSpan>> _newHl;
  // Cached max line lengths for content width estimation (avoid
  // re-computing on every build — only changes when diff changes).
  int _maxOldLineLen = 0;
  int _maxNewLineLen = 0;

  @override
  void initState() {
    super.initState();
    _compute();
    _oldScroll.addListener(() => _sync(_oldScroll, _newScroll));
    _newScroll.addListener(() => _sync(_newScroll, _oldScroll));
    _oldHScroll.addListener(() => _hSync(_oldHScroll, _newHScroll));
    _newHScroll.addListener(() => _hSync(_newHScroll, _oldHScroll));
  }

  void _compute() {
    const engine = DiffEngine();
    _diff = engine.computeSplitDiff(widget.oldText, widget.newText,
        filePath: widget.filePath);
    final lang = detectLanguage(widget.filePath);
    final hlTheme = context.read<CodeThemeNotifier>().theme;
    _oldHl = highlightLines(widget.oldText, lang, hlTheme);
    _newHl = highlightLines(widget.newText, lang, hlTheme);
    _alignedRows = buildAlignedRows(_diff);
    _foldRegions = [];
    _maxOldLineLen = _diff.oldLines.fold<int>(0, (m, l) => max(m, l.length));
    _maxNewLineLen = _diff.newLines.fold<int>(0, (m, l) => max(m, l.length));
    _rebuildDisplay();
  }

  void _rebuildDisplay() {
    final result = applyFolding(_alignedRows, _foldRegions);
    _displayRows = result.displayRows;
    _changeIndices = result.changeIndices;
  }

  void _sync(ScrollController src, ScrollController tgt) {
    if (_syncing || !tgt.hasClients) return;
    _syncing = true;
    tgt.jumpTo(src.offset.clamp(0, tgt.position.maxScrollExtent));
    _syncing = false;
  }

  void _hSync(ScrollController src, ScrollController tgt) {
    if (_hSyncing || !tgt.hasClients) return;
    _hSyncing = true;
    tgt.jumpTo(src.offset.clamp(0, tgt.position.maxScrollExtent));
    _hSyncing = false;
  }

  void _next() {
    if (_changeIndices.isEmpty) return;
    setState(() => _currentChangeIdx = (_currentChangeIdx + 1) % _changeIndices.length);
    _scrollTo(_changeIndices[_currentChangeIdx]);
  }

  void _prev() {
    if (_changeIndices.isEmpty) return;
    setState(() => _currentChangeIdx = _currentChangeIdx <= 0
        ? _changeIndices.length - 1 : _currentChangeIdx - 1);
    _scrollTo(_changeIndices[_currentChangeIdx]);
  }

  void _scrollTo(int idx) {
    final o = idx * _fontZoom.itemExtent;
    if (_oldScroll.hasClients) {
      _oldScroll.animateTo(o.clamp(0, _oldScroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _expandFold(int i) => setState(() { _foldRegions[i].showAll(); _rebuildDisplay(); });
  void _expandAbove(int i) => setState(() { _foldRegions[i].showMoreAbove(); _rebuildDisplay(); });
  void _expandBelow(int i) => setState(() { _foldRegions[i].showMoreBelow(); _rebuildDisplay(); });

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final nw = max(
        max(_diff.oldLines.length, _diff.newLines.length).toString().length, 2);
    return Column(children: [
      buildDiffToolbar(
        filePath: widget.filePath,
        totalAdded: _diff.totalAdded,
        totalDeleted: _diff.totalDeleted,
        changeIndices: _changeIndices,
        currentChangeIdx: _currentChangeIdx,
        wordWrap: _wordWrap,
        onPrev: _prev,
        onNext: _next,
        onToggleWrap: () => setState(() => _wordWrap = !_wordWrap),
        onFontSizeUp: _fontZoom.fontSizeUp,
        onFontSizeDown: _fontZoom.fontSizeDown,
        fontSize: _fontZoom.fontSize,
      ),
      Expanded(child: GestureDetector(
        onScaleStart: _fontZoom.onScaleStart,
        onScaleUpdate: _fontZoom.onScaleUpdate,
        child: LayoutBuilder(builder: (context, constraints) {
        final topFlex = (_splitRatio * 1000).round().clamp(150, 850);
        final bottomFlex = 1000 - topFlex;
        final totalH = constraints.maxHeight;
        return Column(children: [
          Expanded(
            flex: topFlex,
            child: _panel('BEFORE', _oldScroll, _oldHScroll, DiffSide.old, nw,
                DiffTheme.deletedGutter, DiffTheme.deletedBg, DiffTheme.deletedCharBg,
                _diff.oldLines.length),
          ),
          DiffDragDivider(
            axis: Axis.vertical,
            onDrag: (dy) {
              setState(() {
                _splitRatio = ((_splitRatio * totalH + dy) / totalH).clamp(0.15, 0.85);
              });
            },
            onDoubleTap: () => setState(() => _splitRatio = 0.5),
          ),
          Expanded(
            flex: bottomFlex,
            child: _panel('AFTER', _newScroll, _newHScroll, DiffSide.new_, nw,
                DiffTheme.addedGutter, DiffTheme.addedBg, DiffTheme.addedCharBg,
                _diff.newLines.length),
          ),
        ]);
      }))),
    ]);
  }

  Widget _panel(String label, ScrollController scroll, ScrollController hScroll,
      DiffSide side, int nw,
      Color tint, Color lbg, Color cbg, int lc) {
    final markers = buildChangeMarkers(_displayRows, side);
    final lnColWidth = nw * 8.0 + 8;
    final contentWidth = estimateDiffContentWidth(
      lineNumColumnWidth: lnColWidth,
      maxLineLength: side == DiffSide.old ? _maxOldLineLen : _maxNewLineLen,
      fontSize: _fontZoom.fontSize,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        color: tint.withValues(alpha: 0.08),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3)),
            child: Text(label,
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.bold,
                    color: tint, letterSpacing: 1)),
          ),
          const SizedBox(width: 6),
          Text('$lc lines', style: TextStyle(fontSize: 9, color: Colors.grey[600])),
        ]),
      ),
      Expanded(
        child: Row(children: [
          Expanded(
            child: _buildScrollableList(scroll, hScroll, side, nw, tint, lbg, cbg, lnColWidth, contentWidth),
          ),
          DiffMinimap(
            totalRows: _displayRows.length,
            markers: markers,
            scrollController: scroll,
            itemExtent: 20,
          ),
        ]),
      ),
    ]);
  }

  /// Build the code list with optional horizontal scrolling.
  ///
  /// When [_wordWrap] is true, the list fills available width (no horizontal
  /// scroll). When false, wraps in a [SingleChildScrollView] with estimated
  /// content width so the user can pan to see long lines.
  Widget _buildScrollableList(
    ScrollController scroll, ScrollController hScroll,
    DiffSide side, int nw,
    Color tint, Color lbg, Color cbg,
    double lnColWidth, double contentWidth,
  ) {
    final list = _buildListView(scroll, side, nw, tint, lbg, cbg, lnColWidth);
    if (_wordWrap) return list;
    return SingleChildScrollView(
      controller: hScroll,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: max(contentWidth, 200),
        child: list,
      ),
    );
  }

  /// Build the vertical [ListView] of diff rows.
  Widget _buildListView(
    ScrollController scroll, DiffSide side, int nw,
    Color tint, Color lbg, Color cbg, double lnColWidth,
  ) {
    final itemH = _wordWrap ? null : _fontZoom.itemExtent;
    return ListView.builder(
      controller: scroll,
      itemCount: _displayRows.length,
      itemExtent: itemH,
      itemBuilder: (_, i) {
        final row = _displayRows[i];
        if (row.type == AlignedRowType.fold) {
          return buildFoldRow(row,
            onExpandAll: row.foldIndex != null ? () => _expandFold(row.foldIndex!) : null,
            onExpandAbove: row.foldIndex != null ? () => _expandAbove(row.foldIndex!) : null,
            onExpandBelow: row.foldIndex != null ? () => _expandBelow(row.foldIndex!) : null,
          );
        }
        return buildCodeRow(
          row: row, side: side, lineNumWidth: nw,
          tint: tint, lineBg: lbg, charBg: cbg,
          diff: _diff, hlSpans: side == DiffSide.old ? _oldHl : _newHl,
          wordWrap: _wordWrap, fontSize: _fontZoom.fontSize,
          lineNumColumnWidth: lnColWidth,
        );
      },
    );
  }

  @override
  void dispose() {
    _oldScroll.dispose();
    _newScroll.dispose();
    _oldHScroll.dispose();
    _newHScroll.dispose();
    super.dispose();
  }
}
