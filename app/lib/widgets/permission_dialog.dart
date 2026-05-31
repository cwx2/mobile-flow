/// permission_dialog.dart — Tool permission request dialog with queue.
///
/// Manages the permission request queue for parallel tool calls and
/// shows a dialog for each request sequentially. Supports auto-approve
/// mode (Autopilot) and three permission levels: allow once, always, deny.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/payloads/permission_payloads.g.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/permission_operations.dart';
import '../theme/theme_extensions.dart';
import '../utils/logger.dart';

final _log = getLogger('PermissionDialog');

/// Manages permission request queue and dialog display.
///
/// Listens to [WebSocketService.permissionStream] and shows dialogs
/// sequentially. If a dialog is already showing, new requests are
/// queued and processed in order after the current one is dismissed.
class PermissionDialogManager {
  final BuildContext _context;
  bool _dialogShowing = false;
  final List<Map<String, dynamic>> _queue = [];
  StreamSubscription? _sub;

  PermissionDialogManager(this._context);

  /// Start listening to permission requests.
  ///
  /// Call this in [State.initState]. The subscription is automatically
  /// cancelled when [dispose] is called.
  void listen(WebSocketService ws) {
    _sub = ws.permissionStream.listen((data) {
      final payload = PermissionRequestPayload.fromJson(data);
      _log.fine(
          '🔔 permissionStream 收到: ${payload.toolName} (request_id=${payload.requestId})');
      if (!_context.mounted) return;

      // Auto-approve mode: approve automatically, don't queue
      if (ws.autoApprovePermissions) {
        final optionId = payload.options.isNotEmpty
            ? (payload.options[0]['id'] as String? ?? 'allow_once')
            : 'allow_once';
        ws.permissionOps.respondPermission(payload.requestId, true, optionId: optionId);
        _log.info('🤖 Autopilot 自动批准: ${payload.requestId}');
        return;
      }

      // Already showing a dialog → queue the request
      if (_dialogShowing) {
        _queue.add(data);
        _log.fine(
            '📋 权限请求排队: ${payload.requestId} (队列长度=${_queue.length})');
        return;
      }

      _dialogShowing = true;
      _showDialog(data);
    });
  }

  /// Clean up the subscription.
  void dispose() {
    _sub?.cancel();
  }

  /// Show the permission dialog for a single request.
  void _showDialog(Map<String, dynamic> data) {
    if (!_context.mounted) return;
    final colors = _context.colors;
    final payload = PermissionRequestPayload.fromJson(data);
    final toolName = payload.toolName.isNotEmpty
        ? payload.toolName
        : S.of(_context).chatPermissionToolCall;
    final toolKind = payload.toolKind ?? '';
    final description = payload.description ?? '';
    final options = payload.options;

    showDialog(
      context: _context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_context.radii.lg),
        ),
        title: Row(
          children: [
            Icon(
              toolKind == 'edit'
                  ? Icons.edit_note
                  : toolKind == 'execute'
                      ? Icons.terminal
                      : Icons.security,
              color: colors.warning,
              size: 20,
            ),
            SizedBox(width: _context.spacing.sm),
            Expanded(
                child:
                    Text(toolName, style: _context.typography.titleSmall)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (toolKind.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: _context.spacing.sm,
                  vertical: _context.spacing.xxs,
                ),
                margin: EdgeInsets.only(bottom: _context.spacing.sm),
                decoration: BoxDecoration(
                  color: colors.warningContainer,
                  borderRadius:
                      BorderRadius.circular(_context.radii.xs),
                ),
                child: Text(toolKind,
                    style: _context.typography.labelSmall
                        .copyWith(color: colors.warning)),
              ),
            if (description.isNotEmpty)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(_context.spacing.md),
                decoration: BoxDecoration(
                  color: colors.surfaceDim,
                  borderRadius:
                      BorderRadius.circular(_context.radii.sm),
                ),
                child: SelectableText(
                  description,
                  style: _context.typography.codeMedium,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _context
                  .read<PermissionOperations>()
                  .respondPermission(payload.requestId, false);
              _processNext();
            },
            child: Text(S.of(_context).chatPermissionDeny,
                style: TextStyle(color: colors.error)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final optionId = options.isNotEmpty
                  ? (options[0]['id'] as String? ?? 'allow_once')
                  : 'allow_once';
              _context
                  .read<PermissionOperations>()
                  .respondPermission(payload.requestId, true, optionId: optionId);
              _processNext();
            },
            child: Text(S.of(_context).chatPermissionAllow,
                style: TextStyle(color: colors.secondary)),
          ),
          if (options.any((o) => o['kind'] == 'allow_always'))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _context.read<PermissionOperations>().respondPermission(
                    payload.requestId, true,
                    optionId: 'allow_always');
                _processNext();
              },
              child: Text(S.of(_context).chatPermissionAlwaysAllow,
                  style: TextStyle(color: colors.primary)),
            ),
        ],
      ),
    );
  }

  /// Process the next queued permission request.
  void _processNext() {
    _dialogShowing = false;
    if (_queue.isNotEmpty && _context.mounted) {
      final next = _queue.removeAt(0);
      _log.fine(
          '📋 处理排队的权限请求: ${next['request_id']} (剩余=${_queue.length})');
      _dialogShowing = true;
      Future.microtask(() {
        if (_context.mounted) _showDialog(next);
      });
    }
  }
}
