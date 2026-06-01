/// chat_bubble.dart — Chat message bubble (main entry point).
///
/// Distinguishes user vs. AI messages and dispatches to the
/// appropriate content block widget in the blocks/ directory:
///   - text_block.dart      → plain text
///   - thought_block.dart   → AI thinking process
///   - tool_call_card.dart  → tool call card
///   - file_edit_card.dart  → file edit diff
///   - plan_card.dart       → multi-step plan
///   - code_block.dart      → code block
///   - error_block.dart     → error message
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../animation/message_entrance.dart';
import '../models/chat_message.dart';
import '../theme/theme_extensions.dart';
import '../utils/app_config.dart';
import 'blocks/text_block.dart';
import 'blocks/thought_block.dart';
import 'blocks/tool_call_card.dart';
import 'blocks/file_edit_card.dart';
import 'blocks/plan_card.dart';
import 'blocks/code_block.dart';
import 'blocks/error_block.dart';
import 'blocks/interruption_block.dart';

/// Renders a single chat message as a bubble.
///
/// User messages are right-aligned with a slide-from-right entrance;
/// assistant messages are left-aligned with a slide-from-left entrance.
/// Each message plays its entrance animation once on first build.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return MessageEntrance(
      direction: isUser ? EntranceDirection.right : EntranceDirection.left,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: isUser
            ? _buildUserMessage(context)
            : _buildAssistantMessage(context),
      ),
    );
  }

  /// User message: right-aligned bubble with optional image attachments.
  Widget _buildUserMessage(BuildContext context) {
    final colors = context.colors;
    final hasImages = message.attachmentPaths.isNotEmpty;
    final hasText = message.plainText.isNotEmpty;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attachment image thumbnails (horizontally scrollable)
                if (hasImages) ...[
                  SizedBox(
                    height: AttachmentDisplayConfig.bubbleThumbSize,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      itemCount: message.attachmentPaths.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final path = message.attachmentPaths[i];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(
                              AttachmentDisplayConfig.bubbleThumbRadius),
                          child: Image.file(
                            File(path),
                            width: AttachmentDisplayConfig.bubbleThumbSize,
                            height: AttachmentDisplayConfig.bubbleThumbSize,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: AttachmentDisplayConfig.bubbleThumbSize,
                              height: AttachmentDisplayConfig.bubbleThumbSize,
                              color: colors.surfaceVariant,
                              child: Icon(Icons.broken_image,
                                  size: 32, color: colors.onSurfaceMuted),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (hasText) const SizedBox(height: 8),
                ],
                // Text content
                if (hasText)
                  Text(
                    message.plainText,
                    style: TextStyle(fontSize: 14, color: colors.onSurface),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Assistant message: IDE-style flat layout, each block rendered independently.
  /// No avatar — left-aligned content fills the full width to maximise
  /// screen real estate on mobile. Role is distinguished by alignment
  /// (left) and absence of bubble background.
  Widget _buildAssistantMessage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AI is loading, no content yet
        if (message.blocks.isEmpty && message.isStreaming)
          const _LoadingDots(),
        // Dispatch each block to its corresponding widget
        ...message.blocks.map((block) => _buildBlock(block)),
      ],
    );
  }

  /// Dispatch a content block to the appropriate widget by type.
  Widget _buildBlock(ContentBlock block) {
    switch (block.type) {
      case BlockType.text:
        return TextBlock(text: block.text);
      case BlockType.thought:
        return ThoughtBlock(
          text: block.text,
          isStreaming: !block.isThinkingDone && message.isStreaming,
        );
      case BlockType.toolCall:
        return ToolCallCard(block: block);
      case BlockType.fileEdit:
        return FileEditCard(block: block);
      case BlockType.plan:
        return PlanCard(entries: block.planEntries ?? []);
      case BlockType.code:
        return CodeBlock(text: block.text, language: block.language);
      case BlockType.error:
        return ErrorBlock(text: block.text);
      case BlockType.interruption:
        return const InterruptionBlock();
      case BlockType.commandList:
      case BlockType.sessionInfo:
        return const SizedBox.shrink();
    }
  }
}

/// Loading animation (AI is thinking, no output yet).
class _LoadingDots extends StatelessWidget {
  const _LoadingDots();
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.onSurfaceMuted,
        ),
      ),
    );
  }
}
