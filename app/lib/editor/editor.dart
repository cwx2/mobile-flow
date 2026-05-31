/// editor.dart — Code editor engine.
///
/// A self-contained code editor widget with syntax highlighting, code folding,
/// search/replace, autocomplete, and mobile-optimized input handling.
///
/// ## Architecture
///
/// This is a single Dart library using `part/part of` to share private types
/// across files. All 33 files live in the same directory because Dart's part
/// system requires a flat namespace — private classes like _CodeFieldRender
/// and _CodeInputController are referenced across multiple files.
///
/// ## File organization
///
/// Files are grouped by responsibility:
///
/// ### Public API (what app code imports and uses)
///   - code_editor.dart      — CodeEditor widget, CodeEditorStyle, CodeEditorTapRegion
///   - code_line.dart         — CodeLineEditingController, CodeLineEditingValue, CodeLineSelection
///   - code_lines.dart        — CodeLines collection, CodeLineSegment
///   - code_find.dart         — CodeFindController, CodeFindValue, CodeFindOption
///   - code_scroll.dart       — CodeScrollController
///   - code_autocomplete.dart — CodeAutocomplete widget, CodePrompt, CodeKeywordPrompt
///   - code_chunk.dart        — CodeChunkController, CodeChunkAnalyzer (code folding)
///   - code_shortcuts.dart    — CodeShortcutType, shortcut key bindings
///   - code_indicator.dart    — DefaultCodeLineNumber, DefaultCodeChunkIndicator
///   - code_toolbar.dart      — SelectionToolbarController (copy/paste menu)
///   - code_formatter.dart    — CodeCommentFormatter (comment toggle)
///   - code_theme.dart        — CodeHighlightTheme (syntax highlighting theme)
///   - code_paragraph.dart    — IParagraph interface (text layout abstraction)
///   - code_span.dart         — MouseTrackerAnnotationTextSpan (hover events)
///
/// ### Internal implementation (private, not imported directly)
///   - _code_field.dart       — _CodeFieldRender: custom RenderObject for painting,
///                              layout, cursor, selection, and hit testing
///   - _code_editable.dart    — _CodeEditable: StatefulWidget connecting controller
///                              to the render layer
///   - _code_input.dart       — _CodeInputController: IME/soft keyboard integration,
///                              DeltaTextInputClient implementation
///   - _code_highlight.dart   — _CodeHighlighter: background syntax highlighting
///                              via isolate, manages highlight result cache
///   - _code_selection.dart   — _CodeSelectionGestureDetector: touch/mouse gesture
///                              handling, long-press word select, drag selection
///   - _code_scroll.dart      — _CodeScrollable: virtual scrolling, viewport management
///   - _code_floating_cursor.dart — _CodeFloatingCursorController: iOS floating cursor
///   - _code_autocomplete.dart — _DefaultCodeAutocompletePromptsBuilder: prompt matching
///   - _code_find.dart        — _CodeFindControllerImpl: search engine with isolate
///   - _code_formatter.dart   — _DefaultCodeCommentFormatter: comment/uncomment logic
///   - _code_shortcuts.dart   — _CodeShortcuts, _CodeShortcutActions: shortcut dispatch
///   - _code_indicator.dart   — CodeLineNumberRenderObject, CodeChunkIndicatorRenderObject
///   - _code_paragraph.dart   — _ParagraphImpl: TextPainter wrapper
///   - _code_line.dart        — _CodeLineEditingControllerImpl: controller internals
///   - _code_lines.dart       — _CodeLineSegmentImpl: segmented line storage
///   - _code_span.dart        — (no private types, only the public MouseTrackerAnnotationTextSpan)
///   - _code_extensions.dart  — Extension methods on InlineSpan, TextSpan, Offset
///   - _consts.dart           — Platform detection constants (kIsAndroid, kIsIOS, kIsMacOS)
///   - _isolate.dart          — _IsolateTasker: generic isolate task runner
library editor;

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:collection';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:re_highlight/re_highlight.dart';
import 'package:isolate_manager/isolate_manager.dart';

// ── Public API: widgets and controllers ──

part 'code_editor.dart';
part 'code_line.dart';
part 'code_lines.dart';
part 'code_find.dart';
part 'code_scroll.dart';
part 'code_autocomplete.dart';
part 'code_chunk.dart';
part 'code_shortcuts.dart';
part 'code_indicator.dart';
part 'code_toolbar.dart';
part 'code_formatter.dart';
part 'code_theme.dart';
part 'code_paragraph.dart';
part 'code_span.dart';

// ── Internal: rendering and layout ──

part '_code_field.dart';
part '_code_editable.dart';
part '_code_paragraph.dart';
part '_code_indicator.dart';

// ── Internal: input and interaction ──

part '_code_input.dart';
part '_code_selection.dart';
part '_code_floating_cursor.dart';
part '_code_shortcuts.dart';

// ── Internal: features ──

part '_code_highlight.dart';
part '_code_find.dart';
part '_code_autocomplete.dart';
part '_code_formatter.dart';
part '_code_scroll.dart';

// ── Internal: data and utilities ──

part '_code_line.dart';
part '_code_lines.dart';
part '_code_span.dart';
part '_code_extensions.dart';
part '_consts.dart';
part '_isolate.dart';
