/// code_block.dart — Syntax-highlighted code block with copy button.
///
/// Renders code snippets with language-aware syntax highlighting
/// (powered by highlight.js via flutter_highlight), a language label,
/// and a one-tap copy button. Also supports "Send to AI" via
/// long-press context menu on selected text.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:provider/provider.dart';

import '../../components/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/code_theme.dart';
import '../../theme/theme_extensions.dart';

/// Renders a code snippet with syntax highlighting, language label,
/// and copy button.
///
/// Used by both [ChatBubble] for standalone code blocks and by
/// [TextBlock] as a custom code block builder for markdown fences.
class CodeBlock extends StatelessWidget {
  final String text;
  final String? language;

  /// Whether to show the "Send to AI" context menu item.
  /// Disabled when used inside markdown (text is already selectable).
  final bool showSendToAi;

  const CodeBlock({
    super.key,
    required this.text,
    this.language,
    this.showSendToAi = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radii = context.radii;
    final codeTheme = context.watch<CodeThemeNotifier>();

    // Normalize language label for display
    final lang = (language ?? '').toLowerCase().trim();
    final displayLang = lang.isNotEmpty ? lang : null;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: spacing.sm),
      decoration: BoxDecoration(
        // Use app theme surface color instead of code theme background
        // so code blocks blend with the surrounding chat UI.
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(radii.sm),
        border: Border.all(color: colors.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar: language label + copy button
          _buildHeader(context, displayLang),
          // Syntax-highlighted code body
          _buildCodeBody(context, codeTheme),
        ],
      ),
    );
  }

  /// Header row with language label (left) and copy button (right).
  Widget _buildHeader(BuildContext context, String? displayLang) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.borderSubtle.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          // Language label
          if (displayLang != null)
            Text(
              displayLang,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: colors.onSurfaceMuted,
              ),
            ),
          const Spacer(),
          // Copy button
          GestureDetector(
            onTap: () => _copyToClipboard(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: colors.onSurfaceMuted,
                ),
                SizedBox(width: spacing.xxs),
                Text(
                  S.of(context).codeBlockCopy,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Syntax-highlighted code body using flutter_highlight.
  ///
  /// When language is known, renders with full syntax coloring.
  /// When language is unknown (no fence hint), falls back to plain
  /// monospace text with the code theme's colors — still looks good,
  /// just no token-level coloring.
  Widget _buildCodeBody(BuildContext context, CodeThemeNotifier codeTheme) {
    final colors = context.colors;
    final lang = (language ?? '').toLowerCase().trim();
    final code = text.trimRight();

    // Override the highlight theme's background to transparent so the
    // outer Container's surfaceDim color shows through consistently.
    // Also override foreground to use app theme color for readability
    // across both light and dark modes.
    final transparentTheme = Map<String, TextStyle>.from(codeTheme.theme);
    final rootStyle = transparentTheme['root'] ?? const TextStyle();
    transparentTheme['root'] = rootStyle.copyWith(
      backgroundColor: Colors.transparent,
      color: colors.onSurface,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: lang.isNotEmpty
          ? HighlightView(
              code,
              language: lang,
              theme: transparentTheme,
              padding: EdgeInsets.zero,
              textStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
                color: colors.onSurface,
              ),
            )
          : SelectableText(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
                color: colors.onSurface,
              ),
            ),
    );
  }

  /// Copy the full code text to clipboard with toast feedback.
  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    AppToast.show(context, S.of(context).codeBlockCopied);
  }
}
