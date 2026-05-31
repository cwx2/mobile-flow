/// Terminal extra key bar.
///
/// Displays common terminal keys (Esc, Tab, Ctrl, Alt, arrows, symbols)
/// above the system keyboard. Includes one-tap combo keys (^C, ^D, ^Z, ^L)
/// and a paste button. Ctrl/Alt are toggle buttons that auto-cancel
/// after combining with the next key. Collapse button cycles:
/// both rows → function keys only → hidden → both rows.
///
/// Used by:
///   - TerminalScreen
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/extra_key_bar.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';

/// Terminal shortcut symbols (row 2).
const _terminalSymbols = [
  '|', '/', '-', '~', '_', ':', ';', '\\',
  '{', '}', '[', ']', '(', ')', '<', '>',
  '&', '*', '=', '+', '@', '#', '\$', '%',
  '^', '!', '?', '"', "'",
];

/// Display mode: two rows / one row / hidden.
enum _KeyBarMode { both, single, hidden }

/// Terminal extra key bar widget.
class TerminalExtraKeys extends StatefulWidget {
  /// Key output callback — sends escape sequences or characters.
  final void Function(String data) onKey;

  /// Paste callback — sends clipboard text through terminal.paste()
  /// to support bracketed paste mode. If null, paste is disabled.
  final void Function(String text)? onPaste;

  const TerminalExtraKeys({
    super.key,
    required this.onKey,
    this.onPaste,
  });

  @override
  State<TerminalExtraKeys> createState() => _TerminalExtraKeysState();
}

class _TerminalExtraKeysState extends State<TerminalExtraKeys> {
  bool _ctrlActive = false;
  bool _altActive = false;
  _KeyBarMode _mode = _KeyBarMode.both;

  void _sendKey(String data) {
    if (_ctrlActive && data.length == 1) {
      // Ctrl+letter: ASCII 1-26
      final code = data.toUpperCase().codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        widget.onKey(String.fromCharCode(code - 64));
        setState(() => _ctrlActive = false);
        return;
      }
    }
    if (_altActive && data.length == 1) {
      // Alt+char: ESC + char
      widget.onKey('\x1b$data');
      setState(() => _altActive = false);
      return;
    }
    widget.onKey(data);
  }

  /// Read clipboard and send through the paste callback.
  ///
  /// Uses [onPaste] (which calls terminal.paste()) instead of [onKey]
  /// so that bracketed paste mode is respected — multi-line text won't
  /// be executed line-by-line by the shell.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      if (widget.onPaste != null) {
        widget.onPaste!(text);
      } else {
        widget.onKey(text);
      }
    }
  }

  void _cycleMode() {
    setState(() {
      _mode = switch (_mode) {
        _KeyBarMode.both => _KeyBarMode.single,
        _KeyBarMode.single => _KeyBarMode.hidden,
        _KeyBarMode.hidden => _KeyBarMode.both,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == _KeyBarMode.hidden) {
      return _buildToggleOnly(context);
    }

    return ExtraKeyBar(
      children: [
        // Row 1: collapse + modifier keys + combo keys + paste + arrows
        ExtraKeyRow(
          height: 38,
          children: [
            ExtraKeyToggle(
              icon: Icons.keyboard_arrow_down,
              onTap: _cycleMode,
            ),
            ExtraKey(label: 'Esc', onTap: () => _sendKey('\x1b')),
            ExtraKey(label: 'Tab', onTap: () => _sendKey('\t')),
            ExtraKey(label: 'Enter', onTap: () => _sendKey('\r')),
            ExtraKey.toggle(
              label: 'Ctrl',
              isActive: _ctrlActive,
              onTap: () => setState(() {
                _ctrlActive = !_ctrlActive;
                if (_ctrlActive) _altActive = false;
              }),
            ),
            ExtraKey.toggle(
              label: 'Alt',
              isActive: _altActive,
              onTap: () => setState(() {
                _altActive = !_altActive;
                if (_altActive) _ctrlActive = false;
              }),
            ),
            const SizedBox(width: 4),
            // One-tap combo keys for high-frequency terminal operations
            ExtraKey(label: '^C', onTap: () => widget.onKey('\x03')),
            ExtraKey(label: '^D', onTap: () => widget.onKey('\x04')),
            ExtraKey(label: '^Z', onTap: () => widget.onKey('\x1a')),
            ExtraKey(label: '^L', onTap: () => widget.onKey('\x0c')),
            const SizedBox(width: 4),
            // Paste from clipboard
            ExtraKey(
              label: S.of(context).terminalExtraKeyPaste,
              onTap: _pasteFromClipboard,
              small: true,
            ),
            const SizedBox(width: 4),
            ExtraKey(label: '←', onTap: () => _sendKey('\x1b[D')),
            ExtraKey(label: '↑', onTap: () => _sendKey('\x1b[A')),
            ExtraKey(label: '↓', onTap: () => _sendKey('\x1b[B')),
            ExtraKey(label: '→', onTap: () => _sendKey('\x1b[C')),
            const SizedBox(width: 4),
            ExtraKey(label: 'Home', onTap: () => _sendKey('\x1b[H'), small: true),
            ExtraKey(label: 'End', onTap: () => _sendKey('\x1b[F'), small: true),
            ExtraKey(label: 'PgUp', onTap: () => _sendKey('\x1b[5~'), small: true),
            ExtraKey(label: 'PgDn', onTap: () => _sendKey('\x1b[6~'), small: true),
            ExtraKey(label: 'Del', onTap: () => _sendKey('\x1b[3~'), small: true),
          ],
        ),
        // Row 2: common symbols (only in "both" mode)
        if (_mode == _KeyBarMode.both)
          ExtraKeyRow(
            height: 34,
            children: [
              for (final ch in _terminalSymbols)
                ExtraKey(label: ch, onTap: () => _sendKey(ch), small: true),
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
