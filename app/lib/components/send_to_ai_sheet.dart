/// send_to_ai_sheet.dart — Bottom sheet for "Send to AI" pipeline.
///
/// Shows a content preview + description input field + send button.
/// Used by [SendToAiService] as the unified confirmation UI before
/// sending any content to the AI chat.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/send_to_ai_payload.dart';
import '../theme/theme_extensions.dart';
import 'app_bottom_sheet.dart';

/// Show the "Send to AI" confirmation sheet.
///
/// Returns the user's description text if they tap Send, or null if
/// they dismiss the sheet without sending.
Future<String?> showSendToAiSheet(
  BuildContext context, {
  required SendToAiPayload payload,
}) {
  return AppBottomSheet.show<String>(
    context,
    builder: (ctx) => _SendToAiSheetContent(payload: payload),
  );
}

class _SendToAiSheetContent extends StatefulWidget {
  final SendToAiPayload payload;
  const _SendToAiSheetContent({required this.payload});

  @override
  State<_SendToAiSheetContent> createState() => _SendToAiSheetContentState();
}

class _SendToAiSheetContentState extends State<_SendToAiSheetContent> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus the description input after sheet animation
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;
    final radii = context.radii;
    final payload = widget.payload;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.lg, 0, spacing.lg, spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: type label + source
          Row(
            children: [
              Icon(_typeIcon(payload.type), size: 18, color: colors.primary),
              SizedBox(width: spacing.sm),
              Text(payload.typeLabel, style: typography.titleSmall),
              if (payload.sourceLabel.isNotEmpty) ...[
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Text(
                    payload.sourceLabel,
                    style: typography.codeSmall.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: spacing.md),

          // Content preview (scrollable, max 200px)
          // Skip for 'run' type which has no content to preview
          if (payload.content.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              width: double.infinity,
              padding: EdgeInsets.all(spacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceDim,
                borderRadius: BorderRadius.circular(radii.sm),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _truncateContent(payload.content),
                  style: typography.codeSmall,
                ),
              ),
            ),
          SizedBox(height: spacing.md),

          // Description input
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: 3,
            minLines: 1,
            style: typography.bodyMedium,
            cursorColor: colors.primary,
            decoration: InputDecoration(
              hintText: S.of(context).componentSendToAiHint,
              hintStyle: typography.bodyMedium.copyWith(
                color: colors.onSurfaceMuted,
              ),
              filled: true,
              fillColor: colors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radii.md),
                borderSide: BorderSide(color: colors.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radii.md),
                borderSide: BorderSide(color: colors.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radii.md),
                borderSide: BorderSide(color: colors.primary, width: 1.5),
              ),
              contentPadding: EdgeInsets.all(spacing.md),
            ),
          ),
          SizedBox(height: spacing.md),

          // Send button (full width)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context, _controller.text);
              },
              icon: const Icon(Icons.send, size: 18),
              label: Text(S.of(context).componentSendToAiButton),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding: EdgeInsets.symmetric(vertical: spacing.md),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radii.md),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Truncate long content for preview (keep first 1000 chars).
  String _truncateContent(String content) {
    if (content.length <= 1000) return content;
    return '${content.substring(0, 1000)}\n... (${content.length} chars)';
  }

  /// Icon for each content type.
  IconData _typeIcon(SendToAiType type) => switch (type) {
        SendToAiType.code => Icons.code,
        SendToAiType.diff => Icons.difference_outlined,
        SendToAiType.terminal => Icons.terminal,
        SendToAiType.file => Icons.insert_drive_file_outlined,
        SendToAiType.run => Icons.play_arrow,
        SendToAiType.error => Icons.error_outline,
        SendToAiType.text => Icons.text_snippet_outlined,
      };

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
