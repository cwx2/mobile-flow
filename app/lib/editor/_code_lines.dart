/// _code_lines.dart — Segmented storage for [CodeLines] with fast line counts.
///
/// [_CodeLineSegmentQuckLineCount] extends [CodeLineSegment] to cache the
/// total line count (including collapsed children), avoiding repeated
/// traversal. This supports the copy-on-write segmented storage model
/// that keeps large documents performant during edits.
part of editor;

class _CodeLineSegmentQuckLineCount extends CodeLineSegment {

  late int _lineCount;

  _CodeLineSegmentQuckLineCount({
    required super.codeLines,
    required super.dirty,
  }) {
    _lineCount = super.lineCount;
  }

  @override
  int get lineCount => _lineCount;

  @override
  set length(int newLength) {
    super.length = newLength;
    _lineCount = super.lineCount;
  }

  @override
  void add(CodeLine element) {
    super.add(element);
    _lineCount = super.lineCount;
  }

  @override
  void operator []=(int index, CodeLine value) {
    super[index] = value;
    _lineCount = super.lineCount;
  }
  
}

