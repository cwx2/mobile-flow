/// code_editor_view.dart — Code editor component.
///
/// Wraps the internal CodeEditor with unified syntax highlighting,
/// line numbers, code folding, search/replace, comment formatting,
/// and word wrap configuration.
/// Shared by files_screen and file_viewer_screen.
///
/// Includes a custom selection toolbar with "Send to AI" action
/// that integrates with the SendToAI pipeline.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../editor/editor.dart';
import 'package:re_highlight/languages/all.dart';

import '../l10n/app_localizations.dart';
import '../models/send_to_ai_payload.dart';
import '../services/send_to_ai_service.dart';
import '../theme/code_theme.dart';
import '../utils/comment_styles.dart';
import '../utils/language_detect.dart';
import '../utils/logger.dart';

final _log = getLogger('CodeEditor');

/// Unified code editor widget with syntax highlighting, line numbers,
/// code folding, search/replace, and "Send to AI" selection action.
class CodeEditorView extends StatelessWidget {
  final CodeLineEditingController controller;
  final String filePath;
  final bool readOnly;
  final ValueChanged<CodeLineEditingValue>? onChanged;

  /// External scroll controller for jump-to-line support.
  final CodeScrollController? scrollController;

  /// External find controller for search/replace.
  final CodeFindController? findController;

  /// Whether to show the built-in find/replace bar.
  final bool showFind;

  /// Called when the user closes the find bar via the × button.
  final VoidCallback? onFindClose;

  const CodeEditorView({
    super.key,
    required this.controller,
    required this.filePath,
    this.readOnly = true,
    this.onChanged,
    this.scrollController,
    this.findController,
    this.showFind = false,
    this.onFindClose,
  });

  @override
  Widget build(BuildContext context) {
    final codeTheme = context.watch<CodeThemeNotifier>();
    final lang = detectLanguage(filePath);
    final langMode = builtinAllLanguages[lang];
    final highlightTheme = langMode != null
        ? CodeHighlightTheme(
            languages: {lang: CodeHighlightThemeMode(mode: langMode)},
            theme: codeTheme.reTheme,
          )
        : null;

    return CodeEditor(
      controller: controller,
      scrollController: scrollController,
      findController: findController,
      readOnly: readOnly,
      wordWrap: codeTheme.wordWrap,
      commentFormatter: buildCommentFormatter(lang),
      toolbarController: _SendToAiToolbarController(filePath: filePath),
      findBuilder: showFind
          ? (context, controller, readOnly) =>
              _EditorFindBar(controller: controller, readOnly: readOnly, onClose: onFindClose)
          : null,
      style: CodeEditorStyle(
        fontSize: codeTheme.fontSize,
        fontFamily: 'monospace',
        fontHeight: 1.5,
        backgroundColor: codeTheme.backgroundColor,
        textColor: codeTheme.foregroundColor,
        codeTheme: highlightTheme,
      ),
      indicatorBuilder: codeTheme.showLineNumbers
          ? (context, editingController, chunkController, notifier) {
              return Row(
                children: [
                  DefaultCodeLineNumber(
                    controller: editingController,
                    notifier: notifier,
                  ),
                  DefaultCodeChunkIndicator(
                    width: 20,
                    controller: chunkController,
                    notifier: notifier,
                  ),
                ],
              );
            }
          : null,
      onChanged: onChanged,
    );
  }
}

/// Built-in find/replace bar for the code editor.
///
/// Compact mobile-friendly design with a collapsible expand toggle:
/// collapsed = search only, expanded = search + replace.
/// Wraps content in ValueListenableBuilder to react to search result changes.
class _EditorFindBar extends StatefulWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;

  /// Called when the user taps the close button to dismiss the find bar.
  final VoidCallback? onClose;

  const _EditorFindBar({required this.controller, required this.readOnly, this.onClose});

  @override
  // Replace row adds ~34px when expanded
  Size get preferredSize => Size.fromHeight(readOnly ? 40 : 76);

  @override
  State<_EditorFindBar> createState() => _EditorFindBarState();
}

class _EditorFindBarState extends State<_EditorFindBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final controller = widget.controller;
    final readOnly = widget.readOnly;

    return ValueListenableBuilder<CodeFindValue?>(
      valueListenable: controller,
      builder: (context, findValue, _) {
        final result = findValue?.result;
        final matchCount = result?.matches.length ?? 0;
        final matchIndex = result != null && result.index >= 0 ? result.index + 1 : 0;

        return Container(
          color: colors.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search row
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    if (!readOnly)
                      _FindIconBtn(
                        icon: _expanded ? Icons.expand_less : Icons.expand_more,
                        onTap: () => setState(() => _expanded = !_expanded),
                      ),
                    Expanded(
                      child: TextField(
                        controller: controller.findInputController,
                        focusNode: controller.findInputFocusNode,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: S.of(context).codeEditorSearchHint,
                          hintStyle: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: colors.outline),
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Match count inside the input field
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  matchCount > 0 ? '$matchIndex/$matchCount' : '0/0',
                                  style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
                                ),
                              ),
                              _FindOptionBtn(
                                label: '.*',
                                active: findValue?.option.regex ?? false,
                                onTap: controller.toggleRegex,
                              ),
                              _FindOptionBtn(
                                label: 'Aa',
                                active: findValue?.option.caseSensitive ?? false,
                                onTap: controller.toggleCaseSensitive,
                                isLast: true,
                              ),
                            ],
                          ),
                          suffixIconConstraints: const BoxConstraints(maxHeight: 26),
                        ),
                      ),
                    ),
                    _FindIconBtn(icon: Icons.keyboard_arrow_up, onTap: controller.previousMatch),
                    _FindIconBtn(icon: Icons.keyboard_arrow_down, onTap: controller.nextMatch),
                    _FindIconBtn(icon: Icons.close, onTap: () {
                      controller.close();
                      widget.onClose?.call();
                    }),
                  ],
                ),
              ),
              // Replace row — animated slide in/out
              AnimatedSize(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !readOnly && _expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SizedBox(
                          height: 32,
                          child: Row(
                            children: [
                              // Align with search input (same width as toggle button)
                              const SizedBox(width: 32),
                              Expanded(
                                child: TextField(
                                  controller: controller.replaceInputController,
                                  focusNode: controller.replaceInputFocusNode,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: S.of(context).codeEditorReplaceHint,
                                    hintStyle: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: colors.outline),
                                    ),
                                  ),
                                ),
                              ),
                              _FindIconBtn(icon: Icons.find_replace, onTap: controller.replaceMatch, tooltip: S.of(context).codeEditorReplace),
                              _FindIconBtn(icon: Icons.done_all, onTap: controller.replaceAllMatches, tooltip: S.of(context).codeEditorReplaceAll),
                              // Spacer to match the close button width in search row
                              const SizedBox(width: 32),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Small icon button for the find bar.
class _FindIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const _FindIconBtn({required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onTap,
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Tiny toggle button for regex/case-sensitive options in the find bar.
class _FindOptionBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool isLast;
  const _FindOptionBtn({required this.label, required this.active, required this.onTap, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        margin: EdgeInsets.only(right: isLast ? 0 : 2),
        decoration: BoxDecoration(
          color: active ? colors.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: isLast
              ? const BorderRadius.horizontal(right: Radius.circular(13))
              : BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: active ? colors.primary : colors.onSurfaceVariant,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

/// Selection toolbar that shows a native-style context menu with
/// Copy, Select All, and "Send to AI" actions.
///
/// Uses [AdaptiveTextSelectionToolbar.buttonItems] to render the platform's
/// native selection menu (Material on Android, Cupertino on iOS) with
/// custom actions appended.
class _SendToAiToolbarController implements SelectionToolbarController {
  final String filePath;
  _SendToAiToolbarController({required this.filePath});

  OverlayEntry? _entry;

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

    final sel = controller.selection;
    final lines = controller.codeLines;
    String selectedText = '';
    if (sel.baseIndex != sel.extentIndex || sel.baseOffset != sel.extentOffset) {
      selectedText = _extractSelection(lines, sel);
    }

    if (selectedText.isEmpty) return;

    // Pre-capture Navigator context before inserting overlay — the editor's
    // context may become invalid after the overlay is removed.
    final navContext = Navigator.of(context).context;
    final payload = SendToAiPayload(
      type: SendToAiType.code,
      content: selectedText,
      filePath: filePath,
      language: detectLanguage(filePath),
    );

    _log.fine('🎯 选中 ${selectedText.length} chars, 弹出选区菜单');

    _entry = OverlayEntry(builder: (_) {
      // Build button items for the native adaptive toolbar
      final buttonItems = <ContextMenuButtonItem>[
        ContextMenuButtonItem(
          label: 'Copy',
          onPressed: () {
            controller.copy();
            hide(context);
          },
        ),
        ContextMenuButtonItem(
          label: 'Select All',
          onPressed: () {
            controller.selectAll();
            hide(context);
          },
        ),
        ContextMenuButtonItem(
          label: 'Send to AI',
          onPressed: () {
            _log.info('🎯 Send to AI: ${selectedText.length} chars');
            hide(context);
            SendToAiService.send(navContext, payload);
          },
        ),
      ];

      // Wrap in CodeEditorTapRegion so taps on the toolbar are treated as
      // "inside the editor" — without this, CodeEditorTapRegion.onTapOutside
      // fires, unfocusing the editor and triggering hideToolbar() before
      // the button's onPressed can execute.
      return CodeEditorTapRegion(
        child: AdaptiveTextSelectionToolbar.buttonItems(
          anchors: anchors,
          buttonItems: buttonItems,
        ),
      );
    });

    Overlay.of(context).insert(_entry!);
  }

  /// Extract selected text from CodeLines using selection range.
  String _extractSelection(CodeLines lines, CodeLineSelection sel) {
    int startLine, startOffset, endLine, endOffset;
    if (sel.baseIndex < sel.extentIndex ||
        (sel.baseIndex == sel.extentIndex && sel.baseOffset < sel.extentOffset)) {
      startLine = sel.baseIndex;
      startOffset = sel.baseOffset;
      endLine = sel.extentIndex;
      endOffset = sel.extentOffset;
    } else {
      startLine = sel.extentIndex;
      startOffset = sel.extentOffset;
      endLine = sel.baseIndex;
      endOffset = sel.baseOffset;
    }

    if (startLine >= lines.length) return '';
    endLine = endLine.clamp(0, lines.length - 1);

    if (startLine == endLine) {
      final text = lines[startLine].text;
      return text.substring(
        startOffset.clamp(0, text.length),
        endOffset.clamp(0, text.length),
      );
    }

    final buf = StringBuffer();
    final firstText = lines[startLine].text;
    buf.writeln(firstText.substring(startOffset.clamp(0, firstText.length)));
    for (int i = startLine + 1; i < endLine; i++) {
      buf.writeln(lines[i].text);
    }
    final lastText = lines[endLine].text;
    buf.write(lastText.substring(0, endOffset.clamp(0, lastText.length)));
    return buf.toString();
  }
}
