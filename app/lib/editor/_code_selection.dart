/// _code_selection.dart — Gesture handling for text selection.
///
/// [_CodeSelectionGestureDetector] translates tap, double-tap, long-press,
/// and drag gestures into selection operations on both mobile and desktop.
/// On mobile it uses [GestureDetector] for long-press word selection and
/// drag-to-extend; on desktop it adds mouse-click word/line selection and
/// shift-click range extension. Delegates hit testing to [_CodeFieldRender].
part of editor;

/// Top-level gesture handler widget that wraps the entire code editor content.
///
/// This widget is the single entry point for ALL touch and mouse interactions
/// in the editor. It translates raw pointer events (taps, drags, long-presses)
/// into text selection operations via [_CodeFieldRender] hit testing.
///
/// Mobile and desktop follow fundamentally different interaction models:
/// - Mobile: uses [GestureDetector] with long-press for word selection,
///   drag-to-extend, and double-tap for word select. Selection handles
///   (drag dots) and a copy/paste toolbar are shown via overlay.
/// - Desktop: uses a [Listener] + [GestureDetector] combo for click-to-place,
///   click-drag to select, double-click for word select, shift-click for
///   range extension, and right-click for context menu. No selection handles.
///
/// The split is necessary because mobile gestures (long-press, haptic feedback,
/// handle dragging) have no desktop equivalent, and desktop gestures
/// (shift-click, right-click) have no mobile equivalent.
class _CodeSelectionGestureDetector extends StatefulWidget {

  final CodeLineEditingController controller;
  final _CodeInputController inputController;
  final CodeChunkController chunkController;
  final HitTestBehavior? behavior;
  final GlobalKey editorKey;
  final _SelectionOverlayController selectionOverlayController;
  final Widget child;

  const _CodeSelectionGestureDetector({
    required this.controller,
    required this.inputController,
    required this.chunkController,
    this.behavior,
    required this.editorKey,
    required this.selectionOverlayController,
    required this.child,
  });

  @override
  State<StatefulWidget> createState() => _CodeSelectionGestureDetectorState();

}

/// Mutable state for [_CodeSelectionGestureDetector].
///
/// Manages all transient gesture state: drag tracking, double-tap detection
/// timing, deferred tap handling, and anchor points for word-level selection
/// extension. Each field serves a specific role in the gesture state machine.
class _CodeSelectionGestureDetectorState extends State<_CodeSelectionGestureDetector> {
  /// Current pointer position during an active drag gesture (global coords).
  /// Used by [_autoScrollWhenDragging] to continuously extend selection and
  /// auto-scroll while the finger/mouse is held near the editor edge.
  /// Set to null when no drag is in progress.
  Offset? _dragPosition;

  /// Whether a drag gesture is currently in progress.
  /// Guards the auto-scroll timer loop — when false, the loop stops.
  bool _dragging = false;

  /// Timestamp of the last tap-up event, used for double-tap detection.
  /// A second tap within [kDoubleTapTimeout] at the same position triggers
  /// word selection via [_onDoubleTap].
  DateTime? _pointerTapTimestamp;

  /// Position of the last tap-up event (global coords), paired with
  /// [_pointerTapTimestamp] for double-tap proximity checking.
  Offset? _pointerTapPosition;

  /// Deferred tap handling flag for tap-on-selection scenarios.
  /// When the user taps down on an existing selection, we don't immediately
  /// move the cursor (that would deselect). Instead we set this to true and
  /// wait for tap-up to decide: if the user drags, it's a move; if they
  /// release, we collapse the selection to the tap position.
  bool? _handleByNextEvent;

  /// Whether the current long-press gesture started on an existing selection.
  /// When true, the long-press shows the toolbar (copy/paste menu) instead
  /// of starting a new word selection — this lets users access clipboard
  /// actions on already-selected text.
  bool _longPressOnSelection = false;

  /// Anchor selection for word-level drag extension.
  /// When the user double-taps (or long-presses on mobile) to select a word,
  /// this stores that initial word selection. Subsequent drag movements
  /// extend from this anchor in word-sized increments rather than
  /// character-by-character, giving a more natural selection feel.
  CodeLineSelection? _anchorSelection;

  _CodeFieldRender get render => widget.editorKey.currentContext?.findRenderObject() as _CodeFieldRender;

  /// Desktop only: whether the pointer-down occurred within the editor bounds.
  /// Prevents drag gestures that started outside the editor (e.g. on scrollbar
  /// or gutter) from being treated as text selection drags.
  /// See: https://github.com/flutter/flutter/issues/114889
  bool _tapping = false;

  @override
  Widget build(BuildContext context) {
    // Mobile and desktop use completely different gesture detector stacks
    // because their interaction models are incompatible:
    // - Mobile relies on GestureDetector's long-press recognizer for word
    //   selection and drag-to-extend, which conflicts with desktop's
    //   click-drag model.
    // - Desktop wraps the child in a Listener (for raw pointer events that
    //   bypass GestureDetector's tap-vs-drag disambiguation) plus a
    //   GestureDetector (for drag tracking and right-click).
    if (_isMobile) {
      return GestureDetector(
        onLongPressMoveUpdate: (details) {
          if (_longPressOnSelection == true) {
            return;
          }
          if (details.localOffsetFromOrigin.distance < 1) {
            return;
          }
          _dragging = true;
          _onLongPressMove(details);
        },
        onLongPressStart: (details) {
          _dragPosition = details.globalPosition;
          widget.inputController.ensureInput();
          _longPressOnSelection = _isPositionOnSelection(details.globalPosition);
          if (_longPressOnSelection != true) {
            _onMobileLongPressedStart(details.globalPosition);
            _autoScrollWhenDragging();
          } else {
            widget.selectionOverlayController.showToolbar(context, details.globalPosition);
          }
          widget.selectionOverlayController.showHandle(context);
        },
        onLongPressEnd: (details) {
          if (_longPressOnSelection != true) {
            widget.selectionOverlayController.showToolbar(context, details.globalPosition);
          }
          _dragPosition = null;
          _longPressOnSelection = false;
          _dragging = false;
          widget.selectionOverlayController.showHandle(context);
        },
        onLongPressCancel: () {
          _dragPosition = null;
          _longPressOnSelection = false;
          _dragging = false;
          widget.selectionOverlayController.hideToolbar();
          widget.selectionOverlayController.hideHandle();
        },
        onLongPressUp: () {
          _dragPosition = null;
        },
        onTapUp: (details) {
          _onMobileTapUp(details.globalPosition);
        },
        onTapDown: (details) {
          if (!render.hasFocus) {
            _onMobileTapDown(details.globalPosition);
          }
        },
        behavior: widget.behavior,
        child: widget.child,
      );
    } else {
      return GestureDetector(
        onVerticalDragUpdate: _onDrag,
        onHorizontalDragUpdate: _onDrag,
        onVerticalDragStart: (details) {
          if (!_tapping) {
            return;
          }
          _dragPosition = details.globalPosition;
          _dragging = true;
          _autoScrollWhenDragging();
        },
        onVerticalDragEnd: (_) {
          _dragPosition = null;
          _dragging = false;
        },
        onVerticalDragCancel: () {
          _dragPosition = null;
          _dragging = false;
        },
        onHorizontalDragStart: (details) {
          if (!_tapping) {
            return;
          }
          _dragPosition = details.globalPosition;
          _dragging = true;
          _autoScrollWhenDragging();
        },
        onHorizontalDragEnd: (_) {
          _dragPosition = null;
          _dragging = false;
        },
        onHorizontalDragCancel: () {
          _dragPosition = null;
          _dragging = false;
        },
        behavior: widget.behavior,
        onSecondaryTapDown: (detail) {
          _onSecondaryTapDown(context, detail);
        },
        onTapUp: (_) {
          widget.inputController.ensureInput();
        },
        child: Listener(
          onPointerDown: (event) {
            _tapping = render.isValidPointer2(event.position);
            // A trick, delay the focus request here to avoid loss.
            Future(widget.inputController.ensureInput);
            _onDesktopTapDown(event.position);
          },
          onPointerUp: (event) {
            _tapping = false;
            _onDesktopTapUp(event.position);
          },
          onPointerCancel: (event) {
            _tapping = false;
            _handleByNextEvent = false;
            _pointerTapTimestamp = null;
            _pointerTapPosition = null;
          },
          behavior: widget.behavior ?? HitTestBehavior.translucent,
          child: widget.child,
        ),
      );
    }
  }

  bool get _isMobile => kIsAndroid || kIsIOS;

  bool get _isShiftPressed => _isMobile ? false : HardwareKeyboard.instance.logicalKeysPressed
    .any(<LogicalKeyboardKey>{
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
    }.contains);

  /// Handles the first tap-down on mobile when the editor does not yet have focus.
  ///
  /// Moves the cursor to the tapped position and dismisses any visible
  /// selection handles or toolbar. This only fires when [render.hasFocus]
  /// is false (i.e. the editor is gaining focus for the first time).
  void _onMobileTapDown(Offset position) {
    _selectPosition(position, _SelectionChangedCause.tapDown);
    widget.selectionOverlayController.hideHandle();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      widget.selectionOverlayController.hideToolbar();
    });
  }

  /// Handles tap-up on mobile — the main single-tap and double-tap dispatcher.
  ///
  /// Double-tap detection: if this tap-up is within [kDoubleTapTimeout] of the
  /// previous tap and at the same position, triggers word selection via
  /// [_onDoubleTap] and shows both handles and toolbar.
  ///
  /// Single tap: moves cursor to the tapped position and hides handles/toolbar.
  /// Also ensures the soft keyboard is shown via [ensureInput].
  void _onMobileTapUp(Offset position) {
    final DateTime now = DateTime.now();
    if (_pointerTapTimestamp != null && (now.millisecondsSinceEpoch - _pointerTapTimestamp!.millisecondsSinceEpoch) <
      kDoubleTapTimeout.inMilliseconds && _pointerTapPosition != null && _pointerTapPosition!.isSamePosition(position)) {
      _onDoubleTap(position);
      widget.selectionOverlayController.showHandle(context);
      widget.selectionOverlayController.showToolbar(context, position);
    } else {
      _pointerTapTimestamp = now;
      _pointerTapPosition = position;
      _selectPosition(position, _SelectionChangedCause.tapUp);
      widget.selectionOverlayController.hideHandle();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        widget.selectionOverlayController.hideToolbar();
      });
    }
    widget.inputController.ensureInput();
  }

  /// Selects the word at the long-press position on mobile.
  ///
  /// Uses [render.selectWord] to find word boundaries at the press location,
  /// then sets the controller's selection to span that word. Stores the
  /// resulting selection as [_anchorSelection] so that subsequent drag
  /// movements (long-press-move) extend from this word rather than from
  /// a single character position.
  void _onMobileLongPressedStart(Offset position) {
    final CodeLineRange? range = render.selectWord(
      position: position,
    );
    if (range == null) {
      return;
    }
    final CodeLineSelection selection = CodeLineSelection.fromRange(
      range: range
    );
    widget.controller.selection = selection;
    widget.controller.makeCursorVisible();
    _anchorSelection = selection;
    widget.selectionOverlayController.hideHandle();
    widget.selectionOverlayController.hideToolbar();
  }

  /// Handles desktop pointer-down: double-click detection and shift-click.
  ///
  /// Ignores events during IME composition to avoid disrupting input.
  /// If within double-tap timeout of the previous click at the same position,
  /// triggers word selection. Otherwise, if Shift is held and a selection
  /// already exists, extends the selection to the click position.
  /// Falls back to placing the cursor at the click position.
  void _onDesktopTapDown(Offset position) {
    if (widget.controller.isComposing) {
      return;
    }
    final DateTime now = DateTime.now();
    if (_pointerTapTimestamp != null && (now.millisecondsSinceEpoch - _pointerTapTimestamp!.millisecondsSinceEpoch) <
      kDoubleTapTimeout.inMilliseconds && _pointerTapPosition != null && _pointerTapPosition!.isSamePosition(position)) {
      _onDoubleTap(position);
    } else {
      if (widget.controller.selection.baseOffset != -1) {
        if (_isShiftPressed) {
          _extendSelection(position, _SelectionChangedCause.tapDown);
          return;
        }
      }
      _pointerTapTimestamp = now;
      _pointerTapPosition = position;
      _selectPosition(position, _SelectionChangedCause.tapDown);
    }
  }

  /// Handles desktop pointer-up: completes deferred tap-on-selection.
  ///
  /// Clears the anchor selection (no longer needed after pointer release).
  /// If [_handleByNextEvent] was set during tap-down (user tapped on an
  /// existing selection), this is where we finally collapse the cursor to
  /// the tap position — but only if no drag occurred in between.
  void _onDesktopTapUp(Offset position) {
    _anchorSelection = null;
    if (_dragPosition != null) {
      return;
    }
    if (_handleByNextEvent != true) {
      return;
    }
    _handleByNextEvent = false;
    _selectPosition(position, _SelectionChangedCause.tapUp);
  }

  /// Selects the word at the given position (double-tap / double-click).
  ///
  /// On desktop with Shift held, extends the existing selection to include
  /// the double-clicked word rather than replacing it. The extension direction
  /// depends on whether the clicked word is before or after the current
  /// selection base, preserving natural left-to-right or right-to-left feel.
  ///
  /// Stores the result as [_anchorSelection] so subsequent drag movements
  /// extend in word-sized increments from this anchor.
  void _onDoubleTap(Offset position) {
    final CodeLineRange? range = render.selectWord(
      position: position,
    );
    if (range == null) {
      return;
    }
    final CodeLineSelection selection;
    if (_isShiftPressed && widget.controller.selection.base.offset <= range.start) {
      selection = widget.controller.selection.copyWith(
        extentIndex: range.index,
        extentOffset: range.end
      );
    } else if (_isShiftPressed && widget.controller.selection.base.offset >= range.end) {
      selection = widget.controller.selection.copyWith(
        extentIndex: range.index,
        extentOffset: range.start
      );
    } else {
      selection = CodeLineSelection.fromRange(
        range: range
      );
    }
    widget.controller.selection = selection;
    widget.controller.makeCursorVisible();
    _anchorSelection = selection;
  }

  /// Extends the selection during a desktop mouse drag.
  ///
  /// Guards against drags that started outside the editor bounds (Flutter
  /// issue #114889 — GestureDetector can fire drag updates for pointers
  /// that never hit the widget). Also skips during IME composition and
  /// on mobile (mobile uses [_onLongPressMove] instead).
  void _onDrag(DragUpdateDetails details) {
    if (!_tapping) {
      // https://github.com/flutter/flutter/issues/114889
      return;
    }
    if (widget.controller.isComposing) {
      return;
    }
    if (_isMobile) {
      return;
    }
    _dragPosition = details.globalPosition;
    _extendSelection(details.globalPosition, _SelectionChangedCause.drag);
  }

  /// Extends the selection during a mobile long-press drag.
  ///
  /// This is the mobile equivalent of [_onDrag] — it fires continuously
  /// as the user moves their finger after a long-press. Updates
  /// [_dragPosition] so the auto-scroll timer can keep scrolling and
  /// extending even when the finger is held still near the edge.
  void _onLongPressMove(LongPressMoveUpdateDetails details) {
    if (widget.controller.isComposing) {
      return;
    }
    if (!_isMobile) {
      return;
    }
    _dragPosition = details.globalPosition;
    _extendSelection(details.globalPosition, _SelectionChangedCause.drag);
  }

  /// Handles right-click (secondary tap) on desktop.
  ///
  /// Shows the context menu (toolbar) at the click position. Clears any
  /// active IME composition first, since the context menu actions (cut/copy/
  /// paste) operate on the committed text, not the composing region.
  void _onSecondaryTapDown(BuildContext context, TapDownDetails details) {
    _handleByNextEvent = false;
    if (!render.size.contains(render.globalToLocal(details.globalPosition))) {
      return;
    }
    widget.controller.clearComposing();
    widget.selectionOverlayController.showToolbar(context, details.globalPosition);
  }

  /// Extends the current selection to the given offset.
  ///
  /// First checks if the tap/click hit a collapsed code chunk indicator —
  /// if so, expands the chunk instead of changing selection.
  /// On desktop, uses [_anchorSelection] for word-level extension after
  /// double-click; on mobile, anchor is null so extension is character-level.
  /// The [allowOverflow] flag (true during drag) permits selection to extend
  /// beyond visible bounds, enabling auto-scroll behavior.
  void _extendSelection(Offset offset, _SelectionChangedCause cause) {
    if (cause == _SelectionChangedCause.tapDown || cause == _SelectionChangedCause.tapUp) {
      if (expandChunkIfNeeded(render.chunkIndicatorHitIndex(offset))) {
        return;
      }
    }
    final CodeLineSelection? selection = render.extendPositionTo(
      oldSelection: widget.controller.selection,
      position: offset,
      anchor: _isMobile ? null : _anchorSelection,
      allowOverflow: cause == _SelectionChangedCause.drag,
    );
    if (selection == null) {
      return;
    }
    if (widget.controller.selection == selection) {
      return;
    }
    widget.controller.value = widget.controller.value.copyWith(
      selection: selection,
      composing: TextRange.empty,
    );
    widget.controller.makeCursorVisible();
  }

  /// Places the cursor at the given offset (collapsed selection).
  ///
  /// Handles the tap-on-selection deferral: if the user taps down on an
  /// existing non-collapsed selection, we don't move the cursor immediately.
  /// Instead, [_handleByNextEvent] is set to true, and the actual cursor
  /// placement is deferred to tap-up. This allows the user to start a drag
  /// from within the selection without accidentally collapsing it.
  void _selectPosition(Offset offset, _SelectionChangedCause cause) {
    if (cause == _SelectionChangedCause.tapDown || cause == _SelectionChangedCause.tapUp) {
      if (expandChunkIfNeeded(render.chunkIndicatorHitIndex(offset))) {
        return;
      }
    }
    final CodeLineSelection? selection = render.setPositionAt(
      position: offset,
    );
    if (selection == null) {
      return;
    }
    if (widget.controller.selection == selection) {
      return;
    }

    if (cause == _SelectionChangedCause.tapDown) {
      if (!widget.controller.selection.isCollapsed && widget.controller.selection.contains(selection)) {
        _handleByNextEvent = true;
        return;
      }
    }
    widget.controller.value = widget.controller.value.copyWith(
      selection: selection,
      composing: TextRange.empty,
    );
    widget.controller.makeCursorVisible();
  }

  /// Checks whether the given position falls within the current selection.
  ///
  /// Used by long-press handling to decide whether to show the toolbar
  /// (long-press on selection) or start a new word selection (long-press
  /// on unselected text).
  bool _isPositionOnSelection(Offset position) {
    final CodeLineSelection? selection = render.setPositionAt(
      position: position,
    );
    if (selection == null) {
      return false;
    }
    if (widget.controller.selection == selection) {
      return false;
    }
    return widget.controller.selection.contains(selection);
  }

  /// Starts a recursive auto-scroll timer that runs every 100ms while dragging.
  ///
  /// When the user drags near the edge of the editor, this timer continuously
  /// scrolls the viewport and extends the selection to follow the drag
  /// position. The loop self-terminates when [_dragging] becomes false or
  /// [_dragPosition] is set to null (drag ended).
  void _autoScrollWhenDragging() {
    final Offset? position = _dragPosition;
    Future.delayed(const Duration(milliseconds: 100), (() {
      if (_dragPosition == null || position == null) {
        return;
      }
      if (_dragging) {
        render.autoScrollWhenDragging(_dragPosition!);
        _extendSelection(_dragPosition!, _SelectionChangedCause.drag);
      }
      _autoScrollWhenDragging();
    }));
  }

  /// Expands a collapsed code chunk if the tap hit its indicator.
  ///
  /// Returns true if a chunk was expanded (caller should skip normal
  /// selection handling), false otherwise.
  bool expandChunkIfNeeded(int index) {
    if (index < 0) {
      return false;
    }
    widget.chunkController.expand(index);
    return true;
  }

}

enum _SelectionChangedCause {
  /// The user tapped down on the text and that caused the selection (or the location
  /// of the cursor) to change.
  tapDown,

  /// The user tapped up on the text and that caused the selection (or the location
  /// of the cursor) to change.
  tapUp,

  /// The user used the mouse to change the selection by dragging over a piece
  /// of text.
  drag,

}

/// Abstract interface for managing selection overlay UI elements.
///
/// The selection overlay consists of two independent parts:
/// - Handles: the draggable dots at the start/end of a text selection
///   (mobile only — desktop selections have no visible handles).
/// - Toolbar: the floating menu with clipboard actions (copy/paste/cut).
///   On mobile this appears above the selection; on desktop it appears
///   at the right-click position.
///
/// Implementations split by platform because mobile needs handle management
/// (overlay entries, drag tracking, haptic feedback) while desktop only
/// needs toolbar show/hide.
abstract class _SelectionOverlayController {

  void showHandle(BuildContext context);

  void hideHandle();

  void showToolbar(BuildContext context, Offset position);

  void hideToolbar();

  void dispose();

}

typedef OnToolbarShow = void Function(BuildContext context, TextSelectionToolbarAnchors anchors, Rect? renderRect);

/// Desktop selection overlay controller — no handles, toolbar on right-click only.
///
/// Desktop text selection uses the native cursor and has no visible drag
/// handles. The toolbar (context menu) is shown only on right-click
/// (secondary tap) and dismissed on any other interaction. Handle methods
/// are intentionally empty no-ops.
class _DesktopSelectionOverlayController implements _SelectionOverlayController {

  final OnToolbarShow onShowToolbar;
  final VoidCallback onHideToolbar;

  const _DesktopSelectionOverlayController({
    required this.onShowToolbar,
    required this.onHideToolbar
  });

  @override
  void hideHandle() {
  }

  @override
  void showHandle(BuildContext context) {
  }

  @override
  void hideToolbar() {
    onHideToolbar();
  }

  @override
  void showToolbar(BuildContext context, Offset? position) {
    if (position == null) {
      return;
    }
    onShowToolbar(context, TextSelectionToolbarAnchors(
      primaryAnchor: position
    ), null);
  }

  @override
  void dispose() {
  }

}

/// Mobile selection overlay controller — manages both selection handles and toolbar.
///
/// This is the most complex overlay controller because mobile selection
/// requires three coordinated overlay elements:
///
/// 1. Start handle (left drag dot) — positioned at selection.start via
///    [startHandleLayerLink]. Dragging it moves the selection start while
///    keeping the end fixed. On Android, base/extent map to start/end;
///    on iOS, base stays at end and extent moves (platform convention).
///
/// 2. End handle (right drag dot) — positioned at selection.end via
///    [endHandleLayerLink]. Same drag logic, mirrored.
///
/// 3. Toolbar (copy/paste menu) — shown above or below the selection.
///    [showToolbar] calculates the optimal anchor position by comparing
///    the gesture position to the selection start/end screen coordinates,
///    placing the toolbar near whichever endpoint is closer to the tap.
///
/// Handle drag updates the selection in real-time with haptic feedback
/// ([HapticFeedback.selectionClick]) on each line change. Handles prevent
/// order swapping (start handle can't cross past end handle and vice versa).
///
/// Both handles and toolbar are wrapped in [CodeEditorTapRegion] so that
/// tapping on them doesn't trigger the editor's own tap-down handler,
/// which would dismiss the toolbar before button actions can execute.
///
/// Uses platform-specific selection controls: [materialTextSelectionControls]
/// on Android, [cupertinoTextSelectionControls] on iOS.
class _MobileSelectionOverlayController implements _SelectionOverlayController {

  final CodeLineEditingController controller;
  final GlobalKey editorKey;
  final LayerLink startHandleLayerLink;
  final LayerLink endHandleLayerLink;
  final ValueNotifier<bool> toolbarVisibility;
  final FocusNode focusNode;
  final OnToolbarShow onShowToolbar;
  final VoidCallback onHideToolbar;

  bool _inited = false;
  bool _handlesVisible = false;

  final ValueNotifier<bool> _effectiveStartHandleVisibility = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _effectiveEndHandleVisibility = ValueNotifier<bool>(false);

  late BuildContext _context;
  // The contact position of the gesture at the current start handle location.
  // Updated when the handle moves.
  late double _startHandleDragPosition;
  late Offset _startHandleDragLastPosition;
  bool _startHandleDragging = false;

  // The distance from _startHandleDragPosition to the center of the line that
  // it corresponds to.
  late double _startHandleDragPositionToCenterOfLine;

  // The contact position of the gesture at the current end handle location.
  // Updated when the handle moves.
  late double _endHandleDragPosition;
  late Offset _endHandleDragLastPosition;
  bool _endHandleDragging = false;

  // The distance from _endHandleDragPosition to the center of the line that it
  // corresponds to.
  late double _endHandleDragPositionToCenterOfLine;

  List<OverlayEntry>? _handles;
  bool? _handleCollapsed;

  _MobileSelectionOverlayController({
    required BuildContext context,
    required this.controller,
    required this.editorKey,
    required this.startHandleLayerLink,
    required this.endHandleLayerLink,
    required this.toolbarVisibility,
    required this.focusNode,
    required this.onShowToolbar,
    required this.onHideToolbar,
  }) {
    _context = context;
    controller.addListener(_updateTextSelectionHandle);
  }

  TextSelectionControls get selectionControls {
    if (kIsAndroid) {
      return materialTextSelectionControls;
    } else {
      return cupertinoTextSelectionControls;
    }
  }

  @override
  void showHandle(BuildContext context) {
    _context = context;
    _handlesVisible = true;
    if (!_inited) {
      init();
    }
    _updateTextSelectionOverlayVisibilities();
    _buildHandles(context);
  }

  @override
  void hideHandle() {
    _handlesVisible = false;
    _handleCollapsed = null;
    if (_handles != null) {
      _handles![0].remove();
      _handles![1].remove();
      _handles = null;
    }
  }

  @override
  void hideToolbar() {
    onHideToolbar();
  }

  @override
  /// Shows the floating toolbar (copy/paste menu) near the selection.
  ///
  /// Calculates the optimal anchor position for the toolbar based on:
  /// - For collapsed selections: places toolbar at the cursor position.
  /// - For range selections: compares the gesture position to both
  ///   selection endpoints and anchors the toolbar near the closer one.
  /// - When the selection spans nearly the full visible area, falls back
  ///   to anchoring at the gesture position itself.
  ///
  /// The "trick" with primaryAnchor = (-10000, -10000) forces Flutter's
  /// toolbar positioning to use the secondaryAnchor instead, which is
  /// needed when the toolbar should appear below the selection end
  /// rather than above the selection start.
  void showToolbar(BuildContext context, Offset globalPosition) {
    globalPosition = _clampPosition(globalPosition);
    final Rect editingRegion = Rect.fromPoints(
      ensureRender.localToGlobal(Offset.zero),
      ensureRender.localToGlobal(ensureRender.size.bottomRight(Offset.zero)),
    );
    final CodeLineSelection selection = controller.selection;
    final TextSelectionToolbarAnchors anchors;
    if (selection.isCollapsed) {
      anchors = TextSelectionToolbarAnchors(
        primaryAnchor: ensureRender.calculateTextPositionScreenOffset(selection.start, false) ?? globalPosition,
      );
    } else {
      Offset startPosition = ensureRender.calculateTextPositionScreenOffset(selection.start, false) ?? editingRegion.topLeft;
      Offset endPosition = ensureRender.calculateTextPositionScreenOffset(selection.end, true) ?? editingRegion.bottomRight;
      if (startPosition.dy < editingRegion.top) {
        startPosition = Offset(startPosition.dx, editingRegion.top);
      }
      if (endPosition.dy > editingRegion.bottom) {
        endPosition = Offset(endPosition.dx, editingRegion.bottom);
      }
      if (startPosition.dy <= editingRegion.top + lineHeight && endPosition.dy >= editingRegion.bottom - lineHeight) {
        anchors = TextSelectionToolbarAnchors(
          primaryAnchor: globalPosition,
        );
      } else {
        final double distanceToStart = (globalPosition - startPosition).distance;
        final double distanceToEnd = (globalPosition - endPosition).distance;
        if (distanceToStart < distanceToEnd) {
          anchors = TextSelectionToolbarAnchors(
            primaryAnchor: startPosition,
            secondaryAnchor: endPosition
          );
        } else {
          anchors = TextSelectionToolbarAnchors(
            // This is trick, make secondary anchor takes effect
            primaryAnchor: const Offset(-10000, -10000),
            secondaryAnchor: endPosition
          );
        }
      }

    }
    onShowToolbar(context, anchors, editingRegion);
  }

  void init() {
    _inited = true;
    ensureRender.selectionStartInViewport.addListener(_updateTextSelectionOverlayVisibilities);
    ensureRender.selectionEndInViewport.addListener(_updateTextSelectionOverlayVisibilities);
  }

  @override
  void dispose() {
    _startHandleDragging = false;
    _endHandleDragging = false;
    hideHandle();
    controller.removeListener(_updateTextSelectionHandle);
    _effectiveStartHandleVisibility.dispose();
    _effectiveEndHandleVisibility.dispose();
    final _CodeFieldRender? render = editorKey.currentContext?.findRenderObject() as _CodeFieldRender?;
    if (render == null) {
      return;
    }
    render.selectionStartInViewport.removeListener(_updateTextSelectionOverlayVisibilities);
    render.selectionEndInViewport.removeListener(_updateTextSelectionOverlayVisibilities);
  }

  double get lineHeight {
    final _CodeFieldRender? render = editorKey.currentContext?.findRenderObject() as _CodeFieldRender?;
    if (render == null) {
      return 0;
    }
    return render.lineHeight;
  }

  bool get attached {
    final _CodeFieldRender? render = editorKey.currentContext?.findRenderObject() as _CodeFieldRender?;
    return render != null && render.attached;
  }

  _CodeFieldRender get ensureRender => editorKey.currentContext?.findRenderObject() as _CodeFieldRender;

  void _updateTextSelectionHandle() {
    if (!_handlesVisible) {
      return;
    }
    if (!focusNode.hasFocus) {
      return;
    }
    showHandle(_context);
  }

  void _updateTextSelectionOverlayVisibilities() {
    final _CodeFieldRender? render = editorKey.currentContext?.findRenderObject() as _CodeFieldRender?;
    if (render == null) {
      return;
    }
    _effectiveStartHandleVisibility.value = _handlesVisible && render.selectionStartInViewport.value;
    _effectiveEndHandleVisibility.value = _handlesVisible && render.selectionEndInViewport.value;
  }

  /// Builds or rebuilds the two selection handle overlay entries.
  ///
  /// Only rebuilds when the collapsed state changes (collapsed selections
  /// show a single caret handle; range selections show left + right handles).
  /// This avoids unnecessary overlay churn during rapid selection updates.
  /// Inserts handles into the root overlay so they render above all other content.
  void _buildHandles(BuildContext context) {
    final bool isCollapsed = controller.selection.isCollapsed;
    if (_handleCollapsed == isCollapsed) {
      return;
    }
    _handleCollapsed = isCollapsed;
    if (_handles != null) {
      _handles![0].remove();
      _handles![1].remove();
      _handles = null;
    }
    _handles = <OverlayEntry>[
      OverlayEntry(builder: (context) {
        return _buildStartHandle(context, isCollapsed ? TextSelectionHandleType.collapsed : TextSelectionHandleType.left);
      }),
      OverlayEntry(builder: (context) {
        return _buildEndHandle(context, isCollapsed ? TextSelectionHandleType.collapsed : TextSelectionHandleType.right);
      }),
    ];
    Overlay.of(context, rootOverlay: true).insertAll(_handles!);
  }

  /// Builds the start (left) selection handle overlay widget.
  ///
  /// On iOS with a collapsed selection, uses [TextSelectionHandleType.right]
  /// instead of collapsed — iOS convention shows a thin caret handle even
  /// for collapsed selections, unlike Android which hides it.
  ///
  /// Wrapped in [CodeEditorTapRegion] to prevent handle taps from being
  /// treated as editor taps (which would dismiss the toolbar).
  Widget _buildStartHandle(BuildContext context, TextSelectionHandleType type) {
    if (kIsIOS && type == TextSelectionHandleType.collapsed) {
      type = TextSelectionHandleType.right;
    }
    return CodeEditorTapRegion(
      child: ExcludeSemantics(
        child: _SelectionHandleOverlay(
          type: type,
          handleLayerLink: startHandleLayerLink,
          onSelectionHandleTapped: () {
            final Offset? position = ensureRender.calculateTextPositionScreenOffset(controller.selection.start, false);
            if (position == null) {
              return;
            }
            showToolbar(_context, position);
          },
          onSelectionHandleDragStart: _handleStartHandleDragStart,
          onSelectionHandleDragUpdate: (details) {
            _handleStartHandleDragUpdate(details.globalPosition);
          },
          onSelectionHandleDragEnd: _handleStartHandleDragEnd,
          onSelectionHandleDragCancel: () {
            _startHandleDragging = false;
          },
          selectionControls: selectionControls,
          visibility: _effectiveStartHandleVisibility,
          preferredLineHeight: lineHeight,
        )
      ),
    );
  }

  /// Builds the end (right) selection handle overlay widget.
  ///
  /// When the selection is collapsed, returns [SizedBox.shrink] to hide
  /// the second handle entirely — only the start handle is visible for
  /// collapsed selections (caret mode).
  Widget _buildEndHandle(BuildContext context, TextSelectionHandleType type) {
    final Widget handle;
    if (type == TextSelectionHandleType.collapsed) {
      // Hide the second handle when collapsed.
      handle = const SizedBox.shrink();
    } else {
      handle = _SelectionHandleOverlay(
        type: type,
        handleLayerLink: endHandleLayerLink,
        onSelectionHandleTapped: () {
          final Offset? position = ensureRender.calculateTextPositionScreenOffset(controller.selection.end, false);
          if (position == null) {
            return;
          }
          showToolbar(_context, position);
        },
        onSelectionHandleDragStart: _handleEndHandleDragStart,
        onSelectionHandleDragUpdate: (details) {
          _handleEndHandleDragUpdate(details.globalPosition);
        },
        onSelectionHandleDragEnd: _handleEndHandleDragEnd,
        onSelectionHandleDragCancel: () {
          _endHandleDragging = false;
        },
        selectionControls: selectionControls,
        visibility: _effectiveEndHandleVisibility,
        preferredLineHeight: lineHeight,
      );
    }
    return CodeEditorTapRegion(
      child: ExcludeSemantics(
        child: handle,
      ),
    );
  }

  /// Called when the user starts dragging the start selection handle.
  ///
  /// Records the initial drag position and calculates the offset from the
  /// drag contact point to the center of the text line. This offset is
  /// applied during drag updates so the handle tracks smoothly even if
  /// the user didn't grab it exactly at its center. Hides the toolbar
  /// during drag to avoid visual clutter, and starts the auto-scroll timer.
  void _handleStartHandleDragStart(DragStartDetails details) {
    _startHandleDragging = true;
    _startHandleDragLastPosition = details.globalPosition;
    _startHandleDragPosition = details.globalPosition.dy;
    final Offset startPoint = ensureRender.localToGlobal(ensureRender.calculateTextPositionViewportOffset(controller.selection.start)!);
    final double centerOfLine = startPoint.dy + ensureRender.lineHeight / 2;
    _startHandleDragPositionToCenterOfLine = centerOfLine - _startHandleDragPosition;
    toolbarVisibility.value = false;
    _autoScrollWhenStartHandleDragging();
  }

  /// Updates the selection as the user drags the start handle.
  ///
  /// Converts the drag position to a text position, then updates the
  /// selection accordingly. Platform-specific behavior:
  /// - Android: moves the base (start) of the selection, keeps extent (end) fixed.
  /// - iOS: keeps base at the end, moves extent — iOS convention treats
  ///   the dragged handle as the extent regardless of direction.
  ///
  /// Prevents handle order swapping: if the start handle would cross past
  /// the end handle position, the update is silently dropped.
  /// Triggers [HapticFeedback.selectionClick] when the selection changes.
  void _handleStartHandleDragUpdate(Offset offset) {
    if (!attached) {
      return;
    }
    _startHandleDragPosition = _getHandleDy(offset.dy, _startHandleDragPosition);
    _startHandleDragLastPosition = offset;
    final Offset adjustedOffset = ensureRender.globalToLocal(Offset(
      offset.dx,
      _startHandleDragPosition + _startHandleDragPositionToCenterOfLine,
    ));
    final CodeLinePosition? position = ensureRender.calculateTextPosition(adjustedOffset);
    if (position == null) {
      return;
    }
    final CodeLineSelection newSelection;
    if (controller.selection.isCollapsed) {
      newSelection = CodeLineSelection.fromPosition(
        position : position
      );
      if (controller.selection != newSelection) {
        HapticFeedback.selectionClick();
      }
      controller.selection = newSelection;
      return;
    }
    if (kIsAndroid) {
      newSelection = CodeLineSelection(
        baseIndex: position.index,
        baseOffset: position.offset,
        baseAffinity: position.affinity,
        extentIndex: controller.selection.endIndex,
        extentOffset: controller.selection.endOffset,
        extentAffinity: controller.selection.end.affinity
      );
      if (position.index >= controller.selection.endIndex && position.offset >= controller.selection.endOffset) {
        // Don't allow order swapping.
        return;
      }
      if (controller.selection != newSelection) {
        HapticFeedback.selectionClick();
      }
    } else {
      newSelection = CodeLineSelection(
        baseIndex: controller.selection.endIndex,
        baseOffset: controller.selection.endOffset,
        baseAffinity: controller.selection.end.affinity,
        extentIndex: position.index,
        extentOffset: position.offset,
        extentAffinity: position.affinity,
      );
      if (newSelection.extentIndex >= controller.selection.endIndex && newSelection.extentOffset >= controller.selection.endOffset) {
        // Don't allow order swapping.
        return;
      }
    }
    controller.selection = newSelection;
  }

  /// Called when the user finishes dragging the start handle.
  /// Re-shows the toolbar at the last drag position.
  void _handleStartHandleDragEnd(DragEndDetails details) {
    _startHandleDragging = false;
    toolbarVisibility.value = true;
    showToolbar(_context, _startHandleDragLastPosition);
  }

  /// Called when the user starts dragging the end selection handle.
  /// Same offset-to-center-of-line calculation as [_handleStartHandleDragStart],
  /// but for the end handle position.
  void _handleEndHandleDragStart(DragStartDetails details) {
    // This adjusts for the fact that the selection handles may not
    // perfectly cover the TextPosition that they correspond to.
    _endHandleDragging = true;
    _endHandleDragPosition = details.globalPosition.dy;
    _endHandleDragLastPosition = details.globalPosition;
    final Offset endPoint =
        ensureRender.localToGlobal(ensureRender.calculateTextPositionViewportOffset(controller.selection.end)!);
    final double centerOfLine = endPoint.dy + ensureRender.lineHeight / 2;
    _endHandleDragPositionToCenterOfLine = centerOfLine - _endHandleDragPosition;
    toolbarVisibility.value = false;
    _autoScrollWhenEndHandleDragging();
  }

  /// Updates the selection as the user drags the end handle.
  ///
  /// Mirror of [_handleStartHandleDragUpdate] but for the end handle.
  /// Platform-specific behavior:
  /// - Android: moves extent (end), keeps base (start) fixed.
  /// - iOS: moves extent, keeps base at start — same direction convention.
  ///
  /// Prevents order swapping: if the end handle would cross before the
  /// start handle, the update is dropped.
  void _handleEndHandleDragUpdate(Offset offset) {
    if (!attached) {
      return;
    }
    _endHandleDragPosition = _getHandleDy(offset.dy, _endHandleDragPosition);
    _endHandleDragLastPosition = offset;
    final Offset adjustedOffset = ensureRender.globalToLocal(Offset(
      offset.dx,
      _endHandleDragPosition + _endHandleDragPositionToCenterOfLine,
    ));
    final CodeLinePosition? position = ensureRender.calculateTextPosition(adjustedOffset);
    if (position == null) {
      return;
    }
    final CodeLineSelection newSelection;
    if (controller.selection.isCollapsed) {
      newSelection = CodeLineSelection.fromPosition(
        position : position
      );
      if (controller.selection != newSelection) {
        HapticFeedback.selectionClick();
      }
      controller.selection = newSelection;
      return;
    }

    if (kIsAndroid) {
      newSelection = CodeLineSelection(
        baseIndex: controller.selection.baseIndex,
        baseOffset: controller.selection.baseOffset,
        baseAffinity: controller.selection.baseAffinity,
        extentIndex: position.index,
        extentOffset: position.offset,
        extentAffinity: position.affinity,
      );
      if (newSelection.baseIndex >= newSelection.extentIndex && newSelection.baseOffset >= newSelection.extentOffset) {
        // Don't allow order swapping.
        return;
      }
      if (controller.selection != newSelection) {
        HapticFeedback.selectionClick();
      }
    } else {
      newSelection = CodeLineSelection(
        extentIndex: position.index,
        extentOffset: position.offset,
        extentAffinity: position.affinity,
        baseIndex: controller.selection.startIndex,
        baseOffset: controller.selection.startOffset,
        baseAffinity: controller.selection.start.affinity,
      );
      if (position.index <= controller.selection.startIndex && position.offset <= controller.selection.startOffset) {
        // Don't allow order swapping.
        return;
      }
    }
    controller.selection = newSelection;
  }

  /// Called when the user finishes dragging the end handle.
  /// Re-shows the toolbar at the last drag position.
  void _handleEndHandleDragEnd(DragEndDetails details) {
    _endHandleDragging = false;
    toolbarVisibility.value = true;
    showToolbar(_context, _endHandleDragLastPosition);
  }

  /// Auto-scroll timer for start handle dragging.
  /// Runs every 100ms while [_startHandleDragging] is true, scrolling the
  /// viewport and updating the selection to follow the handle position.
  void _autoScrollWhenStartHandleDragging() {
    Future.delayed(const Duration(milliseconds: 100), (() {
      if (!_startHandleDragging) {
        return;
      }
      ensureRender.autoScrollWhenDragging(_startHandleDragLastPosition);
      _handleStartHandleDragUpdate(_startHandleDragLastPosition);
      _autoScrollWhenStartHandleDragging();
    }));
  }

  /// Auto-scroll timer for end handle dragging.
  /// Mirror of [_autoScrollWhenStartHandleDragging] for the end handle.
  void _autoScrollWhenEndHandleDragging() {
    Future.delayed(const Duration(milliseconds: 100), (() {
      if (!_endHandleDragging) {
        return;
      }
      ensureRender.autoScrollWhenDragging(_endHandleDragLastPosition);
      _handleEndHandleDragUpdate(_endHandleDragLastPosition);
      _autoScrollWhenEndHandleDragging();
    }));
  }

  /// Given a handle position and drag position, returns the position of handle
  /// after the drag.
  ///
  /// The handle jumps instantly between lines when the drag reaches a full
  /// line's height away from the original handle position. In other words, the
  /// line jump happens when the contact point would be located at the same
  /// place on the handle at the new line as when the gesture started.
  double _getHandleDy(double dragDy, double handleDy) {
    final double distanceDragged = dragDy - handleDy;
    final int dragDirection = distanceDragged < 0.0 ? -1 : 1;
    final int linesDragged =
        dragDirection * (distanceDragged.abs() / ensureRender.lineHeight).floor();
    return handleDy + linesDragged * ensureRender.lineHeight;
  }

  /// Clamps a global position to the editor's visible bounds.
  ///
  /// Prevents the toolbar from being anchored outside the editor area,
  /// which would cause it to render off-screen or in unexpected positions.
  Offset _clampPosition(Offset position) {
    final RenderBox box = _context.findRenderObject() as RenderBox;
    final Offset offset = box.globalToLocal(position);
    return box.localToGlobal(Offset(min(max(0, offset.dx), box.size.width), min(max(0, offset.dy), box.size.height)));
  }

}

/// Renders a single selection handle (start or end drag dot) with drag support.
///
/// Each handle is a [CompositedTransformFollower] linked to a [LayerLink]
/// that tracks the corresponding selection endpoint in the editor's render
/// tree. This keeps the handle visually attached to the text position even
/// as the editor scrolls.
///
/// The handle's interactive area is expanded beyond its visual size to meet
/// the minimum touch target of [kMinInteractiveDimension] (48dp), ensuring
/// comfortable touch interaction on mobile devices.
///
/// Uses [PanGestureRecognizer] restricted to touch/stylus input only —
/// mouse events are excluded because desktop selection doesn't use handles.
/// Fades in/out via [AnimationController] driven by the [visibility] notifier,
/// which tracks whether the handle's text position is within the viewport.
class _SelectionHandleOverlay extends StatefulWidget {
  /// Create selection overlay.
  const _SelectionHandleOverlay({
    required this.type,
    required this.handleLayerLink,
    this.onSelectionHandleTapped,
    this.onSelectionHandleDragStart,
    this.onSelectionHandleDragUpdate,
    this.onSelectionHandleDragEnd,
    this.onSelectionHandleDragCancel,
    required this.selectionControls,
    this.visibility,
    required this.preferredLineHeight,
  });

  final LayerLink handleLayerLink;
  final VoidCallback? onSelectionHandleTapped;
  final ValueChanged<DragStartDetails>? onSelectionHandleDragStart;
  final ValueChanged<DragUpdateDetails>? onSelectionHandleDragUpdate;
  final ValueChanged<DragEndDetails>? onSelectionHandleDragEnd;
  final VoidCallback? onSelectionHandleDragCancel;
  final TextSelectionControls selectionControls;
  final ValueListenable<bool>? visibility;
  final double preferredLineHeight;
  final TextSelectionHandleType type;

  @override
  State<_SelectionHandleOverlay> createState() => _SelectionHandleOverlayState();
}

class _SelectionHandleOverlayState extends State<_SelectionHandleOverlay> with SingleTickerProviderStateMixin {

  late AnimationController _controller;
  Animation<double> get _opacity => _controller.view;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: SelectionOverlay.fadeDuration, vsync: this);

    _handleVisibilityChanged();
    widget.visibility?.addListener(_handleVisibilityChanged);
  }

  void _handleVisibilityChanged() {
    if (widget.visibility?.value ?? true) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void didUpdateWidget(_SelectionHandleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.visibility?.removeListener(_handleVisibilityChanged);
    _handleVisibilityChanged();
    widget.visibility?.addListener(_handleVisibilityChanged);
  }

  @override
  void dispose() {
    widget.visibility?.removeListener(_handleVisibilityChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Offset handleAnchor = widget.selectionControls.getHandleAnchor(
      widget.type,
      widget.preferredLineHeight,
    );
    final Size handleSize = widget.selectionControls.getHandleSize(
      widget.preferredLineHeight,
    );

    final Rect handleRect = Rect.fromLTWH(
      -handleAnchor.dx,
      -handleAnchor.dy,
      handleSize.width,
      handleSize.height,
    );

    // Make sure the GestureDetector is big enough to be easily interactive.
    final Rect interactiveRect = handleRect.expandToInclude(
      Rect.fromCircle(center: handleRect.center, radius: kMinInteractiveDimension/ 2),
    );
    final RelativeRect padding = RelativeRect.fromLTRB(
      max((interactiveRect.width - handleRect.width) / 2, 0),
      max((interactiveRect.height - handleRect.height) / 2, 0),
      max((interactiveRect.width - handleRect.width) / 2, 0),
      max((interactiveRect.height - handleRect.height) / 2, 0),
    );

    return CompositedTransformFollower(
      link: widget.handleLayerLink,
      offset: interactiveRect.topLeft,
      showWhenUnlinked: false,
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          alignment: Alignment.topLeft,
          width: interactiveRect.width,
          height: interactiveRect.height,
          child: RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: <Type, GestureRecognizerFactory>{
              PanGestureRecognizer: GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                () => PanGestureRecognizer(
                  debugOwner: this,
                  // Mouse events select the text and do not drag the cursor.
                  supportedDevices: <PointerDeviceKind>{
                    PointerDeviceKind.touch,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.unknown,
                  },
                ),
                (PanGestureRecognizer instance) {
                  instance
                    ..dragStartBehavior = DragStartBehavior.start
                    ..onStart = widget.onSelectionHandleDragStart
                    ..onUpdate = widget.onSelectionHandleDragUpdate
                    ..onCancel = widget.onSelectionHandleDragCancel
                    ..onEnd = widget.onSelectionHandleDragEnd;
                },
              ),
            },
            child: Padding(
              padding: EdgeInsets.only(
                left: padding.left,
                top: padding.top,
                right: padding.right,
                bottom: padding.bottom,
              ),
              child: widget.selectionControls.buildHandle(
                context,
                widget.type,
                widget.preferredLineHeight,
                widget.onSelectionHandleTapped,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Default mobile toolbar implementation using [OverlayEntry] and [ToolbarMenuBuilder].
///
/// Creates a floating overlay containing the toolbar widget built by [builder].
/// The toolbar is positioned relative to the editor via a [LayerLink] and
/// [CompositedTransformFollower], so it scrolls with the editor content.
///
/// Supports show/hide cycling: calling [show] while already visible first
/// removes the old entry, then creates a fresh one. The [onRefresh] callback
/// passed to the builder allows the toolbar to request a rebuild (e.g. after
/// a clipboard operation changes available actions).
class _MobileSelectionToolbarController implements MobileSelectionToolbarController {

  final ToolbarMenuBuilder builder;
  OverlayEntry? _entry;

  _MobileSelectionToolbarController({
    required this.builder
  });

  @override
  void hide(BuildContext context) {
    _entry?.remove();
    _entry = null;
  }

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    hide(context);
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    final OverlayEntry entry = OverlayEntry(
      builder: (_) => _SelectionToolbarWrapper(
        visibility: visibility,
        layerLink: layerLink,
        offset: -renderRect!.topLeft,
        child: builder(
          context: context,
          anchors: anchors,
          controller: controller,
          onDismiss: () {
            hide(context);
          },
          onRefresh: () {
            show(
              context: context,
              controller: controller,
              anchors: anchors,
              renderRect: renderRect,
              layerLink: layerLink,
              visibility: visibility
            );
          },
        )
      )
    );
    overlay.insert(entry);
    _entry = entry;
  }

}

/// Wraps the toolbar widget with fade animation and viewport-aware visibility.
///
/// Provides two key behaviors:
/// 1. Fade animation: the toolbar fades in/out using [SelectionOverlay.fadeDuration]
///    driven by the [visibility] notifier. When the selection moves off-screen
///    (e.g. during scrolling), the toolbar fades out rather than disappearing abruptly.
/// 2. Positional tracking: uses [CompositedTransformFollower] with a [LayerLink]
///    to keep the toolbar anchored to the editor's coordinate space, applying
///    an [offset] to compensate for the editor's position within the overlay.
///
/// Wrapped in [CodeEditorTapRegion] so that tapping toolbar buttons doesn't
/// trigger the editor's tap-down handler (which would dismiss the toolbar
/// before the button action executes).
// TODO(justinmc): Currently this fades in but not out on all platforms. It
// should follow the correct fading behavior for the current platform, then be
// made public and de-duplicated with widgets/selectable_region.dart.
// https://github.com/flutter/flutter/issues/107732
// Wrap the given child in the widgets common to both contextMenuBuilder and
// TextSelectionControls.buildToolbar.
class _SelectionToolbarWrapper extends StatefulWidget {
  const _SelectionToolbarWrapper({
    this.visibility,
    required this.layerLink,
    required this.offset,
    required this.child,
  });

  final Widget child;
  final Offset offset;
  final LayerLink layerLink;
  final ValueListenable<bool>? visibility;

  @override
  State<_SelectionToolbarWrapper> createState() => _SelectionToolbarWrapperState();
}

class _SelectionToolbarWrapperState extends State<_SelectionToolbarWrapper> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Animation<double> get _opacity => _controller.view;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(duration: SelectionOverlay.fadeDuration, vsync: this);

    _toolbarVisibilityChanged();
    widget.visibility?.addListener(_toolbarVisibilityChanged);
  }

  @override
  void didUpdateWidget(_SelectionToolbarWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibility == widget.visibility) {
      return;
    }
    oldWidget.visibility?.removeListener(_toolbarVisibilityChanged);
    _toolbarVisibilityChanged();
    widget.visibility?.addListener(_toolbarVisibilityChanged);
  }

  @override
  void dispose() {
    widget.visibility?.removeListener(_toolbarVisibilityChanged);
    _controller.dispose();
    super.dispose();
  }

  void _toolbarVisibilityChanged() {
    if (widget.visibility?.value ?? true) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CodeEditorTapRegion(
      child: Directionality(
        textDirection: Directionality.of(this.context),
        child: FadeTransition(
          opacity: _opacity,
          child: CompositedTransformFollower(
            link: widget.layerLink,
            showWhenUnlinked: false,
            offset: widget.offset,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}