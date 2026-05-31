/// chat_attachment_preview.dart — Chat attachment preview component.
///
/// Module: widgets/
/// Responsibility:
///   Horizontally scrollable thumbnail strip above the input field.
///   Each thumbnail is a rounded square with an X button overlay
///   for removal. Supports image files and shows a placeholder
///   for non-image attachments.
///
/// Used by:
///   - ChatInputBar when attachments are present
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import '../theme/tokens/color_tokens.dart';
import '../utils/app_config.dart';
import 'chat_input_bar.dart' show ChatAttachment;

/// Attachment preview strip.
///
/// Horizontally scrollable row of rounded thumbnails with remove buttons.
/// Shown above the input field when the user has added photos or files.
class ChatAttachmentPreview extends StatelessWidget {
  final List<ChatAttachment> attachments;
  final void Function(String id) onRemove;

  const ChatAttachmentPreview({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: AttachmentDisplayConfig.previewThumbSize + 12,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) => _buildThumb(context, attachments[index]),
      ),
    );
  }

  /// Single thumbnail with rounded corners and X remove button.
  Widget _buildThumb(BuildContext context, ChatAttachment att) {
    final colors = context.colors;
    final isImage = att.mimeType.startsWith('image/');

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(AttachmentDisplayConfig.thumbRadius),
          child: isImage
              ? Image.file(
                  File(att.path),
                  width: AttachmentDisplayConfig.previewThumbSize,
                  height: AttachmentDisplayConfig.previewThumbSize,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(colors),
                )
              : _placeholder(colors),
        ),

        // X remove button (top-right corner)
        Positioned(
          right: -4,
          top: -4,
          child: GestureDetector(
            onTap: () => onRemove(att.id),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.onSurface.withValues(alpha: 0.7),
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  /// Placeholder for non-image or broken-image attachments.
  Widget _placeholder(AppColorTokens colors) {
    return Container(
      width: AttachmentDisplayConfig.previewThumbSize,
      height: AttachmentDisplayConfig.previewThumbSize,
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AttachmentDisplayConfig.thumbRadius),
      ),
      child: Icon(Icons.insert_drive_file_outlined,
          size: 28, color: colors.onSurfaceMuted),
    );
  }
}
