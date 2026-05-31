/// terminal_renderer.dart — Monospace text renderer with ANSI color support.
///
/// Module: widgets/renderers/
/// Responsibility:
///   Displays monospace text with basic ANSI color code parsing and
///   rendering. Used by the Script Runner Panel for command output.
///
/// Called by:
///   - screens/test_panel/script_runner_panel.dart
///   - Any screen needing terminal-style text display
library;

import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';
import '../../theme/tokens/color_tokens.dart';

/// A widget that displays monospace text with basic ANSI color code support.
///
/// Parses common ANSI escape sequences (SGR codes) and renders text
/// with appropriate foreground colors. Supports the standard 8 colors
/// and their bright variants.
class TerminalRenderer extends StatelessWidget {
  /// The text content to display (may contain ANSI escape codes).
  final String text;

  /// Base text style (monospace font applied automatically).
  final TextStyle? baseStyle;

  /// Whether to enable text selection.
  final bool selectable;

  const TerminalRenderer({
    super.key,
    required this.text,
    this.baseStyle,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final defaultStyle = baseStyle ??
        TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: colors.onSurface,
        );

    final spans = _parseAnsi(text, defaultStyle, colors);

    final richText = Text.rich(
      TextSpan(children: spans),
      softWrap: true,
    );

    if (selectable) {
      return SelectionArea(child: richText);
    }
    return richText;
  }

  /// Parse ANSI escape sequences and produce styled TextSpans.
  List<TextSpan> _parseAnsi(
    String input,
    TextStyle defaultStyle,
    AppColorTokens colors,
  ) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\x1B\[([0-9;]*)m');
    var currentStyle = defaultStyle;
    var lastEnd = 0;

    for (final match in regex.allMatches(input)) {
      // Add text before this escape sequence
      if (match.start > lastEnd) {
        final segment = input.substring(lastEnd, match.start);
        if (segment.isNotEmpty) {
          spans.add(TextSpan(text: segment, style: currentStyle));
        }
      }

      // Parse SGR parameters
      final params = match.group(1) ?? '0';
      currentStyle = _applySgr(params, defaultStyle, colors);
      lastEnd = match.end;
    }

    // Add remaining text after last escape sequence
    if (lastEnd < input.length) {
      spans.add(TextSpan(text: input.substring(lastEnd), style: currentStyle));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: input, style: defaultStyle));
    }

    return spans;
  }

  /// Apply SGR (Select Graphic Rendition) parameters to produce a new style.
  TextStyle _applySgr(
    String params,
    TextStyle defaultStyle,
    AppColorTokens colors,
  ) {
    final codes = params.split(';').map((s) => int.tryParse(s) ?? 0).toList();
    var style = defaultStyle;

    for (final code in codes) {
      switch (code) {
        case 0: // Reset
          style = defaultStyle;
        case 1: // Bold
          style = style.copyWith(fontWeight: FontWeight.bold);
        case 2: // Dim
          style = style.copyWith(color: style.color?.withValues(alpha: 0.6));
        case 3: // Italic
          style = style.copyWith(fontStyle: FontStyle.italic);
        case 4: // Underline
          style = style.copyWith(decoration: TextDecoration.underline);
        // Standard foreground colors (30-37)
        case 30:
          style = style.copyWith(color: const Color(0xFF000000));
        case 31:
          style = style.copyWith(color: const Color(0xFFCC0000));
        case 32:
          style = style.copyWith(color: const Color(0xFF00CC00));
        case 33:
          style = style.copyWith(color: const Color(0xFFCCCC00));
        case 34:
          style = style.copyWith(color: const Color(0xFF0000CC));
        case 35:
          style = style.copyWith(color: const Color(0xFFCC00CC));
        case 36:
          style = style.copyWith(color: const Color(0xFF00CCCC));
        case 37:
          style = style.copyWith(color: const Color(0xFFCCCCCC));
        // Bright foreground colors (90-97)
        case 90:
          style = style.copyWith(color: const Color(0xFF666666));
        case 91:
          style = style.copyWith(color: const Color(0xFFFF5555));
        case 92:
          style = style.copyWith(color: const Color(0xFF55FF55));
        case 93:
          style = style.copyWith(color: const Color(0xFFFFFF55));
        case 94:
          style = style.copyWith(color: const Color(0xFF5555FF));
        case 95:
          style = style.copyWith(color: const Color(0xFFFF55FF));
        case 96:
          style = style.copyWith(color: const Color(0xFF55FFFF));
        case 97:
          style = style.copyWith(color: const Color(0xFFFFFFFF));
        case 39: // Default foreground
          style = style.copyWith(color: defaultStyle.color);
      }
    }

    return style;
  }
}
