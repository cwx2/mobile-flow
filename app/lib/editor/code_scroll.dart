/// code_scroll.dart — Scroll control API for the code editor.
///
/// Provides [CodeScrollController] which exposes the vertical and horizontal
/// [ScrollController]s used by the editor viewport, plus convenience methods
/// to programmatically scroll a given [CodeLinePosition] into view.

part of editor;

/// Signature for a builder that wraps the scrollable content with a custom
/// scrollbar widget.
typedef CodeScrollbarBuilder = Widget Function(BuildContext context, Widget child, ScrollableDetails details);

/// Controls horizontal and vertical scrolling of the code editor viewport.
///
/// Wraps a pair of [ScrollController]s and provides helper methods to
/// scroll a specific [CodeLinePosition] into the visible area.
///
/// Pass an instance to [CodeEditor.scrollController] to share scroll state
/// across widgets, or let the editor create one internally.
class CodeScrollController {

  /// The underlying vertical [ScrollController].
  final ScrollController verticalScroller;

  /// The underlying horizontal [ScrollController].
  final ScrollController horizontalScroller;

  GlobalKey? _editorKey;

  CodeScrollController({
    ScrollController? verticalScroller,
    ScrollController? horizontalScroller,
  }) : verticalScroller = verticalScroller ?? ScrollController(),
    horizontalScroller = horizontalScroller ?? ScrollController();

  /// Scroll the viewport so that [position] is centered, but only if it is
  /// currently outside the visible area.
  void makeCenterIfInvisible(CodeLinePosition position) {
    _render?.makePositionCenterIfInvisible(position);
  }

  /// Scroll the viewport so that [position] is visible (at the nearest edge).
  void makeVisible(CodeLinePosition position) {
    _render?.makePositionVisible(position);
  }

  void bindEditor(GlobalKey key) {
    _editorKey = key;
  }

  _CodeFieldRender? get _render => _editorKey?.currentContext?.findRenderObject() as _CodeFieldRender?;

  void dispose() {
    _editorKey = null;
  }

}