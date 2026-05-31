/// diff_viewer.dart — Inline diff viewer widget.
//
// IDE-grade diff rendering in inline mode:
// - Line-level highlighting (red for deleted, green for added)
// - Character-level highlighting (deeper color for changed characters)
// - Dual-column line numbers (old/new)
// - Hunk headers (@@ -1,3 +1,4 @@ format)
// - Collapsible unchanged regions
// - Mobile-optimized single-column inline layout

import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../theme/code_theme.dart';
import '../utils/language_detect.dart';
import 'diff_engine.dart';
import 'diff_model.dart';
import 'diff_theme.dart';

class DiffViewer extends StatefulWidget {
  final String oldText;
  final String newText;
  final String filePath;
  final int contextLines;

  const DiffViewer({
    super.key,
    required this.oldText,
    required this.newText,
    this.filePath = '',
    this.contextLines = 3,
  });

  @override
  State<DiffViewer> createState() => _DiffViewerState();
}

class _DiffViewerState extends State<DiffViewer> {
  late DiffResult _result;
  // Syntax highlighting: per-line TextSpan maps for old and new files
  late Map<int, List<TextSpan>> _oldLineSpans;
  late Map<int, List<TextSpan>> _newLineSpans;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  void _compute() {
    final engine = DiffEngine(contextLines: widget.contextLines);
    _result = engine.compute(widget.oldText, widget.newText,
        filePath: widget.filePath);

    final lang = detectLanguage(widget.filePath);
    final hlTheme = context.read<CodeThemeNotifier>().theme;
    _oldLineSpans = _buildLineSpanMap(widget.oldText, lang, hlTheme);
    _newLineSpans = _buildLineSpanMap(widget.newText, lang, hlTheme);
  }

  /// Syntax-highlight the entire file and return {lineNum(1-based): spans} map.
  static Map<int, List<TextSpan>> _buildLineSpanMap(
      String code, String lang, Map<String, TextStyle> hlTheme) {
    if (code.isEmpty) return {};
    final result = highlight.parse(code, language: lang);
    final allSpans = <TextSpan>[];
    _flattenNodes(result.nodes ?? [], allSpans, hlTheme);
    final lines = _splitSpansByLine(allSpans);
    final map = <int, List<TextSpan>>{};
    for (int i = 0; i < lines.length; i++) {
      map[i + 1] = lines[i]; // 1-based
    }
    return map;
  }

  static void _flattenNodes(
      List<Node> nodes, List<TextSpan> spans, Map<String, TextStyle> theme,
      [String? parentClassName]) {
    for (final node in nodes) {
      final cls = node.className ?? parentClassName;
      if (node.children != null && node.children!.isNotEmpty) {
        _flattenNodes(node.children!, spans, theme, cls);
      } else {
        final text = node.value ?? '';
        if (text.isNotEmpty) {
          final style =
              cls != null ? theme[cls] ?? const TextStyle() : const TextStyle();
          spans.add(TextSpan(text: text, style: style));
        }
      }
    }
  }

  static List<List<TextSpan>> _splitSpansByLine(List<TextSpan> spans) {
    final lines = <List<TextSpan>>[[]];
    for (final span in spans) {
      final text = span.text ?? '';
      final parts = text.split('\n');
      for (int i = 0; i < parts.length; i++) {
        if (i > 0) lines.add([]);
        if (parts[i].isNotEmpty) {
          lines.last.add(TextSpan(text: parts[i], style: span.style));
        }
      }
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    if (!_result.hasChanges) {
      return Center(
        child: Text(S.of(context).diffNoChanges, style: TextStyle(color: DiffTheme.contextText)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStats(_result),
        Expanded(
          child: ListView.builder(
            itemCount: _countItems(_result),
            itemBuilder: (ctx, index) => _buildItem(_result, index),
          ),
        ),
      ],
    );
  }

  /// Stats bar: +N -N
  Widget _buildStats(DiffResult result) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: DiffTheme.hunkHeaderBg,
      child: Row(
        children: [
          if (widget.filePath.isNotEmpty)
            Expanded(
              child: Text(
                widget.filePath.split('/').last,
                style: const TextStyle(
                  fontSize: 13,
                  color: DiffTheme.hunkHeaderText,
                  fontFamily: DiffTheme.fontFamily,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            '+${result.totalAdded}',
            style: const TextStyle(
                fontSize: 12,
                color: DiffTheme.addedGutter,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '-${result.totalDeleted}',
            style: const TextStyle(
                fontSize: 12,
                color: DiffTheme.deletedGutter,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Count ListView items (hunks + fold separators + lines).
  int _countItems(DiffResult result) {
    int count = 0;
    for (int h = 0; h < result.hunks.length; h++) {
      count++; // hunk header
      count += result.hunks[h].lines.length; // lines
      if (h < result.hunks.length - 1) count++; // fold separator
    }
    return count;
  }

  /// Build a single item (hunk header / diff line / fold separator).
  Widget _buildItem(DiffResult result, int index) {
    int pos = 0;
    for (int h = 0; h < result.hunks.length; h++) {
      final hunk = result.hunks[h];

      // Hunk header
      if (pos == index) {
        return _buildHunkHeader(hunk);
      }
      pos++;

      // Diff lines
      for (int l = 0; l < hunk.lines.length; l++) {
        if (pos == index) {
          return _buildDiffLine(hunk.lines[l]);
        }
        pos++;
      }

      // Fold separator
      if (h < result.hunks.length - 1) {
        if (pos == index) {
          return _buildFoldSeparator();
        }
        pos++;
      }
    }
    return const SizedBox.shrink();
  }

  /// Hunk header (@@ -1,3 +1,4 @@).
  Widget _buildHunkHeader(DiffHunk hunk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: DiffTheme.hunkHeaderBg,
      child: Text(
        '@@ -${hunk.oldStart},${hunk.deletedCount + hunk.lines.where((l) => l.type == DiffLineType.context).length} '
        '+${hunk.newStart},${hunk.addedCount + hunk.lines.where((l) => l.type == DiffLineType.context).length} @@',
        style: const TextStyle(
          fontSize: 11,
          color: DiffTheme.hunkHeaderText,
          fontFamily: DiffTheme.fontFamily,
        ),
      ),
    );
  }

  /// Render a single diff line (line numbers + symbol + character-level highlighting).
  Widget _buildDiffLine(DiffLine line) {
    final Color bgColor;
    final Color textColor;
    final String symbol;

    switch (line.type) {
      case DiffLineType.deleted:
        bgColor = DiffTheme.deletedBg;
        textColor = DiffTheme.deletedText;
        symbol = '-';
      case DiffLineType.added:
        bgColor = DiffTheme.addedBg;
        textColor = DiffTheme.addedText;
        symbol = '+';
      case DiffLineType.context:
        bgColor = DiffTheme.contextBg;
        textColor = DiffTheme.contextText;
        symbol = ' ';
    }

    return Container(
      color: bgColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Old line number
          _buildLineNum(line.oldLineNum),
          // New line number
          _buildLineNum(line.newLineNum),
          // +/- symbol
          SizedBox(
            width: 16,
            child: Text(
              symbol,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DiffTheme.fontSize,
                fontFamily: DiffTheme.fontFamily,
                color: line.type == DiffLineType.deleted
                    ? DiffTheme.deletedGutter
                    : line.type == DiffLineType.added
                        ? DiffTheme.addedGutter
                        : DiffTheme.lineNumText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Code content (with character-level highlighting)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: line.charChanges.isEmpty
                  ? _buildSyntaxLine(line, textColor)
                  : _buildCharHighlightedText(line),
            ),
          ),
        ],
      ),
    );
  }

  /// Syntax-highlighted code line (used when no character-level diff).
  Widget _buildSyntaxLine(DiffLine line, Color textColor) {
    // Select the highlight map based on line type
    final spans = line.type == DiffLineType.deleted
        ? _oldLineSpans[line.oldLineNum]
        : _newLineSpans[line.newLineNum];

    if (spans != null && spans.isNotEmpty) {
      return RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: DiffTheme.fontSize,
            fontFamily: DiffTheme.fontFamily,
            color: textColor,
            height: DiffTheme.lineHeight,
          ),
          children: spans,
        ),
      );
    }
    return Text(
      line.text,
      style: TextStyle(
        fontSize: DiffTheme.fontSize,
        fontFamily: DiffTheme.fontFamily,
        color: textColor,
        height: DiffTheme.lineHeight,
      ),
    );
  }

  /// Line number column.
  Widget _buildLineNum(int? num) {
    return Container(
      width: 36,
      padding: const EdgeInsets.only(right: 4),
      color: DiffTheme.lineNumBg,
      child: Text(
        num?.toString() ?? '',
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: DiffTheme.fontSize,
          fontFamily: DiffTheme.fontFamily,
          color: DiffTheme.lineNumText,
          height: DiffTheme.lineHeight,
        ),
      ),
    );
  }

  /// Character-level highlight rendering (second layer of two-layer highlighting).
  Widget _buildCharHighlightedText(DiffLine line) {
    final charBg = line.type == DiffLineType.deleted
        ? DiffTheme.deletedCharBg
        : DiffTheme.addedCharBg;
    final textColor = line.type == DiffLineType.deleted
        ? DiffTheme.deletedText
        : DiffTheme.addedText;

    final spans = <InlineSpan>[];
    int pos = 0;

    for (final change in line.charChanges) {
      // Unchanged portion
      if (pos < change.start) {
        spans.add(TextSpan(
          text: line.text.substring(pos, change.start),
          style: TextStyle(
            fontSize: DiffTheme.fontSize,
            fontFamily: DiffTheme.fontFamily,
            color: textColor,
            height: DiffTheme.lineHeight,
          ),
        ));
      }
      // Changed portion (deeper background color)
      spans.add(TextSpan(
        text: line.text.substring(change.start, change.end),
        style: TextStyle(
          fontSize: DiffTheme.fontSize,
          fontFamily: DiffTheme.fontFamily,
          color: textColor,
          backgroundColor: charBg,
          height: DiffTheme.lineHeight,
        ),
      ));
      pos = change.end;
    }

    // Remaining unchanged portion
    if (pos < line.text.length) {
      spans.add(TextSpan(
        text: line.text.substring(pos),
        style: TextStyle(
          fontSize: DiffTheme.fontSize,
          fontFamily: DiffTheme.fontFamily,
          color: textColor,
          height: DiffTheme.lineHeight,
        ),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }

  /// Fold separator (collapsed unchanged region between hunks).
  Widget _buildFoldSeparator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: DiffTheme.foldedBg,
      child: const Row(
        children: [
          Icon(Icons.unfold_more, size: 14, color: DiffTheme.foldedText),
          SizedBox(width: 4),
          Text(
            '···',
            style: TextStyle(
              fontSize: 11,
              color: DiffTheme.foldedText,
              fontFamily: DiffTheme.fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}
