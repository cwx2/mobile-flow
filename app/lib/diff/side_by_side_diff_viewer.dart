/// side_by_side_diff_viewer.dart — Left-right side-by-side diff viewer.
///
/// Landscape-optimized diff layout (VS Code style):
/// - Left panel: old file, right panel: new file
/// - Synchronized vertical scrolling
/// - Draggable vertical divider to resize panels
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

export 'diff_model.dart' show SplitDiffResult;

/// Left-right side-by-side diff viewer for landscape orientation.
class SideBySideDiffViewer extends StatefulWidget {
  final String oldText;
  final String newText;
  final String filePath;

  const SideBySideDiffViewer({
    super.key,
    required this.oldText,
    required this.newText,
    this.filePath = '',
  });

  @override
  State<SideBySideDiffViewer> createState() => _SideBySideDiffViewerState();
}

class _SideBySideDiffViewerState extends State<SideBySideDiffViewer> {
  final _oldScroll = ScrollController();
  final _newScroll = ScrollController();
  final _oldHScroll = ScrollController();
  final _newHScroll = ScrollController();
  bool _syncing = false;
  bool _hSyncing = false;
  bool _wordWrap = false;
  double _splitRatio = 0.5;
  late final DiffFontZoom _fontZoom = DiffFontZoom(
    defaultSize: kSideBySideDiffFontSize,
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
  // Cached max line lengths for content width estimation
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
        final leftFlex = (_splitRatio * 1000).round().clamp(200, 800);
        final rightFlex = 1000 - leftFlex;
        final totalW = constraints.maxWidth;
        return Row(children: [
          Expanded(
            flex: leftFlex,
            child: _panel(DiffSide.old, _oldScroll, _oldHScroll, nw,
                DiffTheme.deletedGutter, DiffTheme.deletedBg, DiffTheme.deletedCharBg),
          ),
          DiffDragDivider(
            axis: Axis.horizontal,
            onDrag: (dx) {
              setState(() {
                _splitRatio = ((_splitRatio * totalW + dx) / totalW).clamp(0.2, 0.8);
              });
            },
            onDoubleTap: () => setState(() => _splitRatio = 0.5),
          ),
          Expanded(
            flex: rightFlex,
            child: _panel(DiffSide.new_, _newScroll, _newHScroll, nw,
                DiffTheme.addedGutter, DiffTheme.addedBg, DiffTheme.addedCharBg),
          ),
        ]);
      }))),
    ]);
  }

  Widget _panel(DiffSide side, ScrollController scroll,
      ScrollController hScroll, int nw,
      Color tint, Color lbg, Color cbg) {
    final markers = buildChangeMarkers(_displayRows, side);
    final lnColWidth = nw * 7.0 + 6;
    final contentWidth = estimateDiffContentWidth(
      lineNumColumnWidth: lnColWidth,
      maxLineLength: side == DiffSide.old ? _maxOldLineLen : _maxNewLineLen,
      fontSize: _fontZoom.fontSize,
    );

    final itemH = _wordWrap ? null : _fontZoom.itemExtent;
    Widget list = ListView.builder(
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

    // Wrap in horizontal scroll only when word wrap is off
    if (!_wordWrap) {
      list = SingleChildScrollView(
        controller: hScroll,
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: max(contentWidth, 200), child: list),
      );
    }

    return Row(children: [
      Expanded(child: list),
      DiffMinimap(
        totalRows: _displayRows.length,
        markers: markers,
        scrollController: scroll,
        itemExtent: 20,
        width: 6,
      ),
    ]);
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

