/// file_actions_sheet.dart — File action menu (bottom sheet).
///
/// Long-press action menu for files and folders.
/// Actions: create, rename, delete, copy path, send to AI, run file.
///
/// Called by: FilesScreen

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../components/app_dialog.dart';
import '../core/event_bus.dart';
import '../l10n/app_localizations.dart';
import '../models/context_reference.dart';
import '../models/send_to_ai_payload.dart';
import '../services/send_to_ai_service.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/file_operations.dart';
import '../theme/theme_extensions.dart';
import '../components/app_toast.dart';

/// Show the file actions bottom sheet menu.
void showFileActionsSheet(
  BuildContext context, {
  required String path,
  required bool isDir,
}) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    builder: (_) => _FileActionsSheet(
      path: path,
      isDir: isDir,
    ),
  );
}

class _FileActionsSheet extends StatelessWidget {
  final String path;
  final bool isDir;

  const _FileActionsSheet({
    required this.path,
    required this.isDir,
  });

  @override
  Widget build(BuildContext context) {
    final name = path.split('/').last;
    final colors = context.colors;
    final typography = context.typography;

    final items = <Widget>[
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(name, style: typography.titleMedium, overflow: TextOverflow.ellipsis),
      ),
      const Divider(height: 1),
    ];

    if (isDir) {
      items.addAll([
        ListTile(
          leading: Icon(Icons.add_link, color: colors.onSurface),
          title: Text(S.of(context).fileActionsAddToContext),
          onTap: () {
            Navigator.pop(context);
            final ref = ContextReference(type: ContextRefType.folder, path: path);
            context.read<WebSocketService>().addContextReference(ref);
            AppToast.show(context, S.of(context).fileActionsAddedToContext);
          },
        ),
        ListTile(
          leading: Icon(Icons.note_add, color: colors.onSurface),
          title: Text(S.of(context).fileActionsNewFile),
          onTap: () { Navigator.pop(context); _showCreateDialog(context, path, 'file'); },
        ),
        ListTile(
          leading: Icon(Icons.create_new_folder, color: colors.onSurface),
          title: Text(S.of(context).fileActionsNewFolder),
          onTap: () { Navigator.pop(context); _showCreateDialog(context, path, 'dir'); },
        ),
        ListTile(
          leading: Icon(Icons.copy, color: colors.onSurface),
          title: Text(S.of(context).fileActionsCopyPath),
          onTap: () { Navigator.pop(context); _copyPath(context, path); },
        ),
        ListTile(
          leading: Icon(Icons.delete, color: colors.error),
          title: Text(S.of(context).commonDelete, style: TextStyle(color: colors.error)),
          onTap: () { Navigator.pop(context); _showDeleteConfirm(context, path, name); },
        ),
      ]);
    } else {
      items.add(ListTile(
        leading: Icon(Icons.add_link, color: colors.onSurface),
        title: Text(S.of(context).fileActionsAddToContext),
        onTap: () {
          Navigator.pop(context);
          final ref = ContextReference(type: ContextRefType.files, path: path);
          context.read<WebSocketService>().addContextReference(ref);
          AppToast.show(context, S.of(context).fileActionsAddedToContext);
        },
      ));
      items.add(ListTile(
        leading: Icon(Icons.smart_toy, color: colors.onSurface),
        title: Text(S.of(context).fileActionsSendToAi),
        onTap: () {
          Navigator.pop(context);
          SendToAiService.send(
            context,
            SendToAiPayload(
              type: SendToAiType.file,
              content: '',
              filePath: path,
            ),
          );
        },
      ));
      items.add(ListTile(
        leading: Icon(Icons.play_arrow, color: colors.onSurface),
        title: Text(S.of(context).fileActionsRunFile),
        onTap: () {
          Navigator.pop(context);
          // Navigate to Test Panel Script Runner with pre-filled command
          context.read<AppEventBus>().emit(
            AppEvents.navigateToTestPanel,
            {'action': 'run', 'path': path},
          );
        },
      ));
      items.addAll([
        ListTile(
          leading: Icon(Icons.copy, color: colors.onSurface),
          title: Text(S.of(context).fileActionsCopyPath),
          onTap: () { Navigator.pop(context); _copyPath(context, path); },
        ),
        ListTile(
          leading: Icon(Icons.edit, color: colors.onSurface),
          title: Text(S.of(context).fileActionsRename),
          onTap: () { Navigator.pop(context); _showRenameDialog(context, path, name); },
        ),
        ListTile(
          leading: Icon(Icons.delete, color: colors.error),
          title: Text(S.of(context).commonDelete, style: TextStyle(color: colors.error)),
          onTap: () { Navigator.pop(context); _showDeleteConfirm(context, path, name); },
        ),
      ]);
    }

    return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: items));
  }
}

void _copyPath(BuildContext context, String path) {
  Clipboard.setData(ClipboardData(text: path));
  AppToast.show(context, S.of(context).fileActionsPathCopied);
}

void _showRenameDialog(BuildContext context, String path, String currentName) async {
  final newName = await showAppInputDialog(
    context,
    title: S.of(context).fileActionsRename,
    hintText: S.of(context).fileActionsEnterNewName,
    initialValue: currentName,
  );
  if (newName != null && newName.isNotEmpty && newName != currentName) {
    if (context.mounted) {
      context.read<FileOperations>().renameFile(path, newName);
    }
  }
}

void _showDeleteConfirm(BuildContext context, String path, String name) async {
  final confirmed = await showAppConfirmDialog(
    context,
    title: S.of(context).fileActionsConfirmDelete,
    message: S.of(context).fileActionsDeleteMessage(name),
    confirmLabel: S.of(context).commonDelete,
    isDanger: true,
  );
  if (confirmed == true && context.mounted) {
    context.read<FileOperations>().deleteFile(path);
  }
}

void _showCreateDialog(BuildContext context, String folderPath, String type) async {
  final title = type == 'file' ? S.of(context).fileActionsNewFile : S.of(context).fileActionsNewFolder;
  final hint = type == 'file' ? S.of(context).fileActionsEnterFileName : S.of(context).fileActionsEnterFolderName;
  final name = await showAppInputDialog(
    context,
    title: title,
    hintText: hint,
  );
  if (name != null && name.isNotEmpty && context.mounted) {
    context.read<FileOperations>().createFile(folderPath, name, type);
  }
}
