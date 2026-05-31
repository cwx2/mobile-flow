/// code_span.dart — Mouse hover event tracking for text spans.
///
/// Provides [MouseTrackerAnnotationTextSpan], a [TextSpan] subclass that
/// delivers pointer enter/exit events together with the bounding rectangles
/// of the span, enabling hover-aware features like link underlining.

part of editor;

/// Callback for pointer enter events, providing the span [id] and its
/// bounding [rects] in the editor coordinate space.
typedef PointerEnterEventWithRectListener = void Function(PointerEnterEvent event, int id, List<Rect> rects);

/// Callback for pointer exit events, providing the span [id] and its
/// bounding [rects] in the editor coordinate space.
typedef PointerExitEventWithRectListener = void Function(PointerExitEvent event, int id, List<Rect> rects);

/// A [TextSpan] that tracks mouse enter/exit events and reports the
/// bounding rectangles of the span alongside the pointer event.
///
/// Used internally by the editor to support hover-aware features such as
/// link highlighting and tooltip display.
@immutable
class MouseTrackerAnnotationTextSpan extends TextSpan {

  final PointerEnterEventWithRectListener onEnterWithRect;
  final PointerExitEventWithRectListener onExitWithRect;

  const MouseTrackerAnnotationTextSpan({
    super.text,
    super.children,
    super.style,
    super.recognizer,
    super.mouseCursor,
    super.semanticsLabel,
    super.locale,
    super.spellOut,
    required this.onEnterWithRect,
    required this.onExitWithRect,
  });

}