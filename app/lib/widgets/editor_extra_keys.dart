/// editor_extra_keys.dart — Editor shortcut key bar.
///
/// Two-row layout: row 1 has bracket pairs + special keys,
/// row 2 has common symbols. Left toggle button controls display mode.
/// Bracket pairs auto-complete with cursor placed in the middle.
///
/// Used by:
///   - EditorScreen
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../editor/editor.dart';

import '../components/extra_key_bar.dart';
import '../theme/theme_extensions.dart';

/// Editor shortcut symbols (row 2).
const _editorSymbols = [
  ';', ':', '=', '.', ',', '/', '\\',
  '!', '?', '&', '|', '+', '-', '_', '*', '#',
  '@', '\$', '%', '^', '~', '`', '0', '1', '2',
];

/// Display mode: two rows / one row / hidden.
enum _QuickToolsMode { both, single, hidden }

/// Shortcut key bar for the code editor with bracket pairs and common symbols.
class EditorExtraKeys extends StatefulWidget {
  final CodeLineEditingController controller;

  /// Callback to toggle the find/replace bar.
  final VoidCallback? onToggleFind;

  /// Comment formatter for the current language.
  /// When provided, a "//" button appears to toggle comments.
  final CodeCommentFormatter? commentFormatter;

  const EditorExtraKeys({
    super.key,
    required this.controller,
    this.onToggleFind,
    this.commentFormatter,
  });

  @override
  State<EditorExtraKeys> createState() => _EditorExtraKeysState();
}

class _EditorExtraKeysState extends State<EditorExtraKeys> {
  _QuickToolsMode _mode = _QuickToolsMode.both;

  void _insert(String text) {
    HapticFeedback.selectionClick();
    widget.controller.replaceSelection(text);
  }

  void _insertPair(String open, String close) {
    HapticFeedback.selectionClick();
    final sel = widget.controller.selection;
    widget.controller.replaceSelection('$open$close');
    widget.controller.selection = CodeLineSelection.collapsed(
      index: sel.baseIndex,
      offset: sel.baseOffset + open.length,
    );
  }

  void _cycleMode() {
    setState(() {
      _mode = switch (_mode) {
        _QuickToolsMode.both => _QuickToolsMode.single,
        _QuickToolsMode.single => _QuickToolsMode.hidden,
        _QuickToolsMode.hidden => _QuickToolsMode.both,
      };
    });
  }

  void _moveCursor(int delta) {
    HapticFeedback.selectionClick();
    final sel = widget.controller.selection;
    final newOffset = (sel.baseOffset + delta).clamp(0, 99999);
    widget.controller.selection = CodeLineSelection.collapsed(
      index: sel.baseIndex,
      offset: newOffset,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == _QuickToolsMode.hidden) {
      return _buildToggleOnly(context);
    }

    return ExtraKeyBar(
      children: [
        // Row 1: toggle + special keys + bracket pairs + arrows
        ExtraKeyRow(
          children: [
            ExtraKeyToggle(
              icon: _mode == _QuickToolsMode.both
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_down,
              onTap: _cycleMode,
            ),
            ExtraKey(label: 'Tab', onTap: () => _insert('  ')),
            const ExtraKeyDivider(),
            // Comment toggle + search
            if (widget.commentFormatter != null)
              ExtraKey(label: '//', onTap: () {
                HapticFeedback.selectionClick();
                final fmt = widget.commentFormatter!;
                final value = fmt.format(
                  widget.controller.value,
                  widget.controller.options.indent,
                  true,
                );
                widget.controller.runRevocableOp(() {
                  widget.controller.value = value;
                });
              }),
            if (widget.onToggleFind != null)
              ExtraKey(label: '🔍', onTap: () {
                HapticFeedback.selectionClick();
                widget.onToggleFind!();
              }),
            const ExtraKeyDivider(),
            ExtraKey(label: '()', onTap: () => _insertPair('(', ')')),
            ExtraKey(label: '{}', onTap: () => _insertPair('{', '}')),
            ExtraKey(label: '[]', onTap: () => _insertPair('[', ']')),
            ExtraKey(label: '<>', onTap: () => _insertPair('<', '>')),
            ExtraKey(label: '""', onTap: () => _insertPair('"', '"')),
            ExtraKey(label: "''", onTap: () => _insertPair("'", "'")),
            const ExtraKeyDivider(),
            ExtraKey(label: '←', onTap: () => _moveCursor(-1)),
            ExtraKey(label: '→', onTap: () => _moveCursor(1)),
          ],
        ),
        // Row 2: common symbols (only in "both" mode)
        if (_mode == _QuickToolsMode.both)
          ExtraKeyRow(
            children: [
              for (final ch in _editorSymbols)
                ExtraKey(label: ch, onTap: () => _insert(ch), small: true),
            ],
          ),
      ],
    );
  }

  /// Hidden mode: only show a small button to restore.
  Widget _buildToggleOnly(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 28,
      color: colors.surfaceElevated,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 4),
      child: ExtraKeyToggle(
        icon: Icons.keyboard_arrow_up,
        onTap: _cycleMode,
      ),
    );
  }

}
