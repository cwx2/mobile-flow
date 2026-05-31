/// session_picker.dart — Session history picker bottom sheet.
///
/// Shows a list of existing chat sessions from the Agent, allowing
/// the user to switch between conversations. Supports swipe-to-delete
/// and displays session preview, project path, and last activity time.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_bottom_sheet.dart';
import '../l10n/app_localizations.dart';
import '../models/payloads/session_payloads.g.dart';
import '../models/protocol.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../utils/logger.dart';

final _log = getLogger('SessionPicker');

/// Show the session picker bottom sheet.
///
/// Sends a session.list request to the Agent and waits for the response.
/// Displays sessions in a bottom sheet with swipe-to-delete support.
///
/// [guardSessionSwitch] is called before switching to confirm with the
/// user if AI is actively responding (prevents accidental interruption).
void showSessionPicker({
  required BuildContext context,
  required ValueNotifier<bool> openGuard,
  required void Function(VoidCallback onConfirmed) guardSessionSwitch,
}) {
  if (openGuard.value) return;
  openGuard.value = true;

  final ws = context.read<WebSocketService>();
  final colors = context.colors;
  _log.fine('[SessionPicker] 发送 session.list 请求');
  ws.chatOps.requestSessionList();

  late StreamSubscription sub;
  sub = ws.messageStream.listen((msg) {
    if (msg.type == MessageType.sessionListResult) {
      sub.cancel();
      final result = SessionListResultPayload.fromJson(msg.payload);
      final sessions = result.sessions;
      _log.fine(
          '[SessionPicker] 收到 session.list.result: ${sessions.length} 个会话');
      if (!context.mounted) {
        openGuard.value = false;
        return;
      }

      AppBottomSheet.show(
        context,
        builder: (_) => ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  context.spacing.lg, context.spacing.sm,
                  context.spacing.lg, context.spacing.xs),
              child: Text(S.of(context).chatSessionHistory,
                  style: context.typography.titleMedium),
            ),
            if (sessions.isEmpty)
              Padding(
                padding: EdgeInsets.all(context.spacing.lg),
                child: Text(S.of(context).chatNoSessions,
                    style: context.typography.bodySmall.copyWith(
                      color: colors.onSurfaceMuted,
                    )),
              ),
            ...sessions.map((s) {
              final id =
                  s['id'] as String? ?? s['session_id'] as String? ?? '';
              final project =
                  s['project'] as String? ?? s['cwd'] as String? ?? '';
              final preview =
                  s['preview'] as String? ?? s['title'] as String? ?? '';
              final rawUpdatedAt = s['updated_at'];
              final updatedAt = rawUpdatedAt is int ? rawUpdatedAt : 0;

              final time = updatedAt > 0
                  ? DateTime.fromMillisecondsSinceEpoch(updatedAt)
                  : null;
              final timeStr = time != null
                  ? '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}'
                  : '';

              return Dismissible(
                key: ValueKey(id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: EdgeInsets.only(right: context.spacing.lg),
                  color: colors.error.withValues(alpha: 0.15),
                  child: Icon(Icons.delete_outline, color: colors.error),
                ),
                onDismissed: (_) {
                  ws.chatOps.closeSession(id);
                },
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(Icons.chat_outlined,
                      color: colors.onSurfaceVariant, size: 20),
                  title: Text(
                    preview.isNotEmpty
                        ? preview
                        : S.of(context).chatEmptySession,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typography.bodyMedium,
                  ),
                  subtitle: Text(
                    '$project · $timeStr',
                    style: context.typography.labelSmall.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    guardSessionSwitch(() => ws.chatOps.switchSession(id));
                  },
                ),
              );
            }),
          ],
        ),
      ).whenComplete(() => openGuard.value = false);
    }
  });
}
