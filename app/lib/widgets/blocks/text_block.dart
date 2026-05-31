/// text_block.dart — Text block with Markdown rendering.
///
/// Renders AI text responses using flutter_markdown.
/// Supports: headings, bold, italic, links, lists, code blocks, images.
/// Code fences (```lang) are rendered with syntax highlighting via
/// [CodeBlock] instead of the default plain-text markdown code style.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/theme_extensions.dart';
import '../../utils/logger.dart';
import '../image_viewer.dart';
import 'code_block.dart';

final _log = getLogger('TextBlock');

/// Renders Markdown text content from AI responses.
class TextBlock extends StatelessWidget {
  final String text;
  const TextBlock({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MarkdownBody(
        data: text,
        selectable: true,
        builders: {
          'code': _SyntaxHighlightCodeBuilder(),
        },
        sizedImageBuilder: (config, {width, height}) => _buildImage(context, config.uri),
        styleSheet: MarkdownStyleSheet(
          // Body text
          p: TextStyle(fontSize: 14, height: 1.6, color: colors.onSurface),
          // Headings
          h1: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colors.onSurface),
          h2: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.onSurface),
          h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.onSurface),
          // Inline code
          code: TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            color: colors.secondary,
            backgroundColor: colors.surfaceVariant,
          ),
          // Code blocks
          codeblockDecoration: BoxDecoration(
            color: colors.surfaceDim,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.borderSubtle, width: 1),
          ),
          codeblockPadding: const EdgeInsets.all(12),
          // Blockquote
          blockquoteDecoration: BoxDecoration(
            border: Border(left: BorderSide(color: colors.primary, width: 3)),
          ),
          blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
          // Links
          a: TextStyle(color: colors.primary, decoration: TextDecoration.underline),
          // Lists
          listBullet: TextStyle(fontSize: 14, color: colors.onSurface),
          // Horizontal rule
          horizontalRuleDecoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.borderSubtle, width: 1)),
          ),
          // Table
          tableBorder: TableBorder.all(color: colors.borderSubtle, width: 1),
          tableHead: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colors.onSurface),
          tableBody: TextStyle(fontSize: 13, color: colors.onSurface),
          tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // Emphasis
          strong: TextStyle(fontWeight: FontWeight.bold, color: colors.onSurface),
          em: TextStyle(fontStyle: FontStyle.italic, color: colors.onSurface),
        ),
      ),
    );
  }

  /// Render markdown images, including data: URI (base64 inline images)
  Widget _buildImage(BuildContext context, Uri uri) {
    // Handle data: URI (base64 encoded images)
    if (uri.scheme == 'data') {
      try {
        final uriStr = uri.toString();
        final commaIdx = uriStr.indexOf(',');
        if (commaIdx > 0) {
          final base64Data = uriStr.substring(commaIdx + 1);
          final bytes = Uint8List.fromList(base64Decode(base64Data));
          return GestureDetector(
            onTap: () => showImageViewer(context, bytes),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          );
        }
      } catch (e) {
        _log.fine('图片数据解析失败: $e');
      }
    }
    // Regular URL images
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(uri.toString(), fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Text('[Image load failed]'),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Custom markdown code block builder that replaces the default
/// plain-text rendering with syntax-highlighted [CodeBlock].
///
/// Extracts the language hint from the markdown fence (```dart)
/// and delegates to [CodeBlock] for consistent rendering across
/// standalone code blocks and markdown-embedded code fences.
class _SyntaxHighlightCodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // Only intercept fenced code blocks (pre > code), not inline `code`
    if (element.tag != 'code') return null;

    // Check if this is inside a <pre> (fenced code block)
    // flutter_markdown wraps fenced code in <pre><code>
    // Inline code has no class attribute
    final className = element.attributes['class'] ?? '';
    final isBlock = className.startsWith('language-') ||
        element.textContent.contains('\n');

    if (!isBlock) return null; // Let inline code use default rendering

    final language = className.startsWith('language-')
        ? className.substring('language-'.length)
        : null;

    return CodeBlock(
      text: element.textContent,
      language: language,
      showSendToAi: false, // Avoid nested context menus in markdown
    );
  }
}
