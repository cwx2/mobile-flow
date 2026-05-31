/// code_paragraph.dart — Text layout abstraction for code lines.
///
/// Defines [IParagraph], the interface that wraps platform text layout
/// (e.g. [TextPainter]) and provides hit-testing, position lookup, and
/// drawing for a single rendered code line.

part of editor;

/// Abstract text layout interface for a single code line.
///
/// Wraps the platform text engine and exposes metrics, hit-testing,
/// and drawing. The internal implementation uses [TextPainter].
abstract class IParagraph {

  /// The laid-out width of the paragraph.
  double get width;

  /// The laid-out height of the paragraph.
  double get height;

  /// The height of a single line in the paragraph's font.
  double get preferredLineHeight;

  /// Whether the paragraph text was truncated during layout.
  bool get trucated;

  /// The number of characters in the paragraph.
  int get length;

  /// The number of visual lines after word-wrapping.
  int get lineCount;

  /// Paint the paragraph onto [canvas] at [offset].
  void draw(Canvas canvas, Offset offset);

  /// Return the [TextPosition] closest to the given pixel [offset].
  TextPosition getPosition(Offset offset);

  /// Return the word boundary at the given pixel [offset].
  TextRange getWord(Offset offset);

  /// Return the [InlineSpan] at [position], or null if none.
  InlineSpan? getSpanForPosition(TextPosition position);

  /// Return the text range covered by [span].
  TextRange getRangeForSpan(InlineSpan span);

  /// Return the line boundary containing [position].
  TextRange getLineBoundary(TextPosition position);

  /// Return the pixel offset of [position], or null if not laid out.
  Offset? getOffset(TextPosition position);

  /// Return the bounding rectangles for the given text [range].
  List<Rect> getRangeRects(TextRange range);

}