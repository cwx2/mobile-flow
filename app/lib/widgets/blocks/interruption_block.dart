/// interruption_block.dart — Tappable stream interruption indicator.
///
/// Displayed when an AI response was cut short due to connection loss,
/// watchdog timeout, or manual disconnect. Tapping it triggers a
/// reconnection attempt and requests chat.replay to resume the
/// interrupted response from the Agent.
///
/// Visually distinct from error blocks — uses a muted warning style
/// with a tap affordance (underline + arrow icon) to indicate it's
/// actionable.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/connection_service.dart';
import '../../services/websocket_service.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/logger.dart';

final _log = getLogger('InterruptionBlock');

/// Tappable indicator that the AI response was interrupted.
///
/// When the connection is active, tapping requests a chat.replay
/// to fetch the content generated while disconnected. When the
/// connection is dead, tapping triggers a reconnect first, then
/// replays automatically on success.
class InterruptionBlock extends StatefulWidget {
  const InterruptionBlock({super.key});

  @override
  State<InterruptionBlock> createState() => _InterruptionBlockState();
}

class _InterruptionBlockState extends State<InterruptionBlock> {
  bool _loading = false;

  Future<void> _onTap() async {
    if (_loading) return;
    setState(() => _loading = true);

    final ws = context.read<WebSocketService>();
    final conn = context.read<ConnectionService>();

    if (conn.state == AppConnectionState.connected) {
      // Already connected — just request replay
      _log.info('连接正常，请求 chat.replay');
      ws.chatOps.requestChatReplay();
    } else {
      // Not connected — trigger reconnect, replay will happen
      // automatically via _handleAuthSuccess → chat.replay
      _log.info('连接断开，触发重连...');
      conn.markConnecting();
      try {
        await ws.connectionManager.reconnect();
        ws.listenMessages();
        // Auth + replay handled by WsAuth._performReconnect flow
      } catch (e) {
        _log.warning('重连失败: $e');
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final conn = context.watch<ConnectionService>();
    final isConnected = conn.state == AppConnectionState.connected;

    return GestureDetector(
      onTap: _onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: colors.warning.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.warning,
                ),
              )
            else
              Icon(
                Icons.wifi_off_rounded,
                size: 14,
                color: colors.warning,
              ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _loading
                    ? S.of(context).chatStreamReconnecting
                    : isConnected
                        ? S.of(context).chatStreamTapToResume
                        : S.of(context).chatStreamTapToReconnect,
                style: typography.labelSmall.copyWith(
                  color: colors.warning,
                  decoration: _loading ? null : TextDecoration.underline,
                  decorationColor: colors.warning.withValues(alpha: 0.5),
                ),
              ),
            ),
            if (!_loading) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.refresh_rounded,
                size: 14,
                color: colors.warning.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
