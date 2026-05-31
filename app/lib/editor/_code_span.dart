/// _code_span.dart — Internal mouse-tracking text span wrapper.
///
/// [_MouseTrackerAnnotationTextSpan] is a private [TextSpan] subclass that
/// attaches pointer enter/exit callbacks with bounding-rect context to a
/// [MouseTrackerAnnotationTextSpan]. Used by the render layer to deliver
/// hover events with positional information for link-style interactions.
part of editor;

@immutable
class _MouseTrackerAnnotationTextSpan extends TextSpan {

  final int id;
  final MouseTrackerAnnotationTextSpan span;
  final List<Rect> rects;

  const _MouseTrackerAnnotationTextSpan({
    required this.id,
    required this.rects,
    required this.span,
  });

  @override
  PointerEnterEventListener? get onEnter => (event) {
    span.onEnterWithRect(event, id, rects);
  };

  @override
  PointerExitEventListener? get onExit => (event) {
    span.onExitWithRect(event, id, rects);
  };

  @override
  int get hashCode => span.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _MouseTrackerAnnotationTextSpan && span == other.span &&
      id == other.id;
  }

}