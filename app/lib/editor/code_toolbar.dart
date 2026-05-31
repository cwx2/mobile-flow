/// code_toolbar.dart — Selection toolbar (copy/paste/cut menu) API.
///
/// Provides [SelectionToolbarController] (abstract toolbar interface) and
/// [MobileSelectionToolbarController] (mobile-specific implementation that
/// shows a floating toolbar near the selection).

part of editor;

/// Signature for a builder that creates the selection toolbar menu widget.
typedef ToolbarMenuBuilder = Widget Function({
  required BuildContext context,
  required TextSelectionToolbarAnchors anchors,
  required CodeLineEditingController controller,
  required VoidCallback onDismiss,
  required VoidCallback onRefresh,
});

/// Abstract controller for the text selection toolbar (copy/paste/cut menu).
///
/// Pass an implementation to [CodeEditor.toolbarController] to customize
/// the toolbar behavior.
abstract class SelectionToolbarController {

  /// Show the toolbar anchored near the current selection.
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  });

  /// Hide the toolbar.
  void hide(BuildContext context);

}

/// Mobile-specific selection toolbar that shows a floating overlay menu
/// built by [ToolbarMenuBuilder].
abstract class MobileSelectionToolbarController implements SelectionToolbarController {

  factory MobileSelectionToolbarController({
    required ToolbarMenuBuilder builder
  }) => _MobileSelectionToolbarController(
    builder: builder
  );

}