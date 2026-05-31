/// attachment_picker.dart — Attachment picker for multimodal input.
///
/// Shows a bottom sheet with available attachment types based on CLI capabilities.
/// Handles image picking, audio file selection, and file references.
/// Attachment types map to ACP ContentBlock types (Image, Audio, Resource, ResourceLink).

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../components/app_bottom_sheet.dart';
import '../../l10n/app_localizations.dart';
import '../../services/websocket_service.dart';
import '../../components/app_toast.dart';
import '../../utils/logger.dart';
import '../../theme/theme_extensions.dart';
import '../chat_input_bar.dart' show ChatAttachment;
import '../context_picker.dart';

final _log = getLogger('AttachmentPicker');


/// Show the attachment type picker based on CLI capabilities
void showAttachmentMenu({
  required BuildContext context,
  required WebSocketService ws,
  required bool isReady,
  required void Function(ChatAttachment) onAdd,
  required String? currentFilePath,
}) {
  if (!isReady) {
    _showToast(context, S.of(context).attachmentAgentNotReady);
    return;
  }

  final caps = ws.cliCapabilities;

  AppBottomSheet.show(context, builder: (ctx) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AttachmentOption(
            icon: Icons.image,
            label: S.of(context).attachmentImage,
            enabled: caps.supportsImage,
            disabledHint: S.of(context).attachmentImageNotSupported,
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(context, onAdd);
            },
          ),
          _AttachmentOption(
            icon: Icons.audiotrack,
            label: S.of(context).attachmentAudio,
            enabled: caps.supportsAudio,
            disabledHint: S.of(context).attachmentAudioNotSupported,
            onTap: () {
              Navigator.pop(ctx);
              _showToast(context, S.of(context).attachmentAudioComingSoon);
            },
          ),
          _AttachmentOption(
            icon: Icons.insert_drive_file,
            label: S.of(context).attachmentFileRef,
            enabled: true,
            onTap: () {
              Navigator.pop(ctx);
              _pickFileReference(context, ws, onAdd, currentFilePath);
            },
          ),
        ],
      ),
    );
  });
}

/// Pick images from gallery
Future<void> _pickImage(BuildContext context, void Function(ChatAttachment) onAdd) async {
  final picker = ImagePicker();
  try {
    final images = await picker.pickMultiImage(imageQuality: 85, maxWidth: 1920);
    if (images.isEmpty) return;
    for (final img in images) {
      onAdd(ChatAttachment(
        id: '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_${img.name}',
        path: img.path,
        mimeType: img.mimeType ?? 'image/jpeg',
      ));
    }
  } catch (e) {
    _log.severe('选择图片失败: $e');
  }
}

/// Pick file as attachment (Resource or ResourceLink based on capability).
///
/// Uses [ContextPicker] which returns a structured [ContextReference].
/// Extracts the file path from the reference for the attachment payload.
Future<void> _pickFileReference(
  BuildContext context,
  WebSocketService ws,
  void Function(ChatAttachment) onAdd,
  String? currentFilePath,
) async {
  final caps = ws.cliCapabilities;
  final picker = ContextPicker(ws: ws, context: context, currentFilePath: currentFilePath);
  final ref = await picker.show();
  if (ref == null || ref.path.isEmpty) return;

  final type = caps.supportsEmbeddedContext ? 'resource' : 'resource_link';
  onAdd(ChatAttachment(
    id: '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_file',
    path: ref.path,
    mimeType: type,
  ));
}

void _showToast(BuildContext context, String message) {
  AppToast.show(context, message);
}

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final String? disabledHint;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.enabled,
    this.disabledHint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      leading: Icon(icon, color: enabled ? colors.primary : colors.onSurfaceMuted.withValues(alpha: 0.4)),
      title: Text(label, style: TextStyle(
        color: enabled ? colors.onSurface : colors.onSurfaceMuted.withValues(alpha: 0.5),
      )),
      onTap: enabled ? onTap : () {
        Navigator.pop(context);
        _showToast(context, disabledHint ?? S.of(context).attachmentNotSupported);
      },
    );
  }
}
