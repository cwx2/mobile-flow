/// connection_banner.dart — Global connection status banner.
///
/// Displays a horizontal banner at the top of [HomeScreen] when the
/// connection is in [AppConnectionState.reconnecting] or
/// [AppConnectionState.failed]. Collapses to zero height when
/// connected, with smooth [AnimatedSize] transitions.
///
/// Reconnecting: amber banner with attempt counter and pulsing indicator.
/// Failed: red banner with [Retry] and [Disconnect] action buttons.
/// Reconnected: brief green flash that fades out after 2 seconds.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/connection_service.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../utils/logger.dart';

final _log = getLogger('ConnectionBanner');

/// Global connection status banner for [HomeScreen].
///
/// Watches [ConnectionService.state] and shows/hides itself with
/// animated transitions. The banner is a thin strip — not a dialog
/// or modal — so it doesn't block user interaction.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({super.key});

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  /// Whether to show the brief "reconnected" success flash.
  bool _showReconnectedFlash = false;
  Timer? _flashTimer;

  /// Track previous state to detect reconnecting → connected transition.
  AppConnectionState? _previousState;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionService>();
    final state = conn.state;
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    // Detect reconnecting → connected transition for success flash
    if (_previousState == AppConnectionState.reconnecting &&
        state == AppConnectionState.connected) {
      _triggerReconnectedFlash();
    }
    _previousState = state;

    // Determine what to show
    final Widget? content;
    final Color? backgroundColor;

    if (state == AppConnectionState.reconnecting) {
      backgroundColor = colors.warning.withValues(alpha: 0.15);
      content = _ReconnectingContent(
        attempt: conn.reconnectAttempt,
        maxAttempts: conn.reconnectMaxAttempts,
        colors: colors,
        typography: typography,
        spacing: spacing,
      );
    } else if (state == AppConnectionState.failed) {
      backgroundColor = colors.error.withValues(alpha: 0.15);
      content = _FailedContent(
        colors: colors,
        typography: typography,
        spacing: spacing,
        onRetry: () {
          _log.info('用户点击重试');
          final ws = context.read<WebSocketService>();
          // Re-trigger connection from saved parameters
          conn.markConnecting();
          ws.connectionManager.reconnect().then((_) {
            // Reconnect will be handled by the normal flow
          }).catchError((e) {
            _log.severe('❌ 重试连接失败: $e');
            conn.markFailed();
          });
        },
        onDisconnect: () {
          _log.info('用户点击断开');
          final ws = context.read<WebSocketService>();
          ws.connectionManager.disconnect();
          conn.disconnect();
        },
      );
    } else if (_showReconnectedFlash) {
      backgroundColor = colors.success.withValues(alpha: 0.15);
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: colors.success),
          SizedBox(width: spacing.xs),
          Text(
            S.of(context).connectionBannerReconnected,
            style: typography.labelMedium.copyWith(color: colors.success),
          ),
        ],
      );
    } else {
      content = null;
      backgroundColor = null;
    }

    // AnimatedSize collapses to zero when content is null
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: content != null
          ? AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Container(
                key: ValueKey(state == AppConnectionState.failed
                    ? 'failed'
                    : state == AppConnectionState.reconnecting
                        ? 'reconnecting'
                        : 'flash'),
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.md,
                  vertical: spacing.sm,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  border: Border(
                    bottom: BorderSide(
                      color: colors.borderSubtle.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: content,
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  /// Show a brief green "reconnected" flash, then fade out.
  void _triggerReconnectedFlash() {
    _flashTimer?.cancel();
    setState(() => _showReconnectedFlash = true);
    _flashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showReconnectedFlash = false);
    });
  }
}

/// Reconnecting state content: pulsing dot + attempt counter.
class _ReconnectingContent extends StatelessWidget {
  final int attempt;
  final int maxAttempts;
  final dynamic colors;
  final dynamic typography;
  final dynamic spacing;

  const _ReconnectingContent({
    required this.attempt,
    required this.maxAttempts,
    required this.colors,
    required this.typography,
    required this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Pulsing amber dot
        _PulsingDot(color: colors.warning),
        SizedBox(width: spacing.sm),
        Expanded(
          child: Text(
            S.of(context).connectionBannerReconnecting(attempt, maxAttempts),
            style: typography.labelMedium.copyWith(color: colors.warning),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Failed state content: error message + retry/disconnect buttons.
class _FailedContent extends StatelessWidget {
  final dynamic colors;
  final dynamic typography;
  final dynamic spacing;
  final VoidCallback onRetry;
  final VoidCallback onDisconnect;

  const _FailedContent({
    required this.colors,
    required this.typography,
    required this.spacing,
    required this.onRetry,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.error_outline, size: 16, color: colors.error),
        SizedBox(width: spacing.sm),
        Expanded(
          child: Text(
            S.of(context).connectionBannerFailed,
            style: typography.labelMedium.copyWith(color: colors.error),
          ),
        ),
        // Retry button — minimum 48dp touch target
        SizedBox(
          height: 32,
          child: TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: spacing.sm),
              minimumSize: const Size(48, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              S.of(context).commonRetry,
              style: typography.labelMedium.copyWith(color: colors.primary),
            ),
          ),
        ),
        SizedBox(width: spacing.xs),
        // Disconnect button
        SizedBox(
          height: 32,
          child: TextButton(
            onPressed: onDisconnect,
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: spacing.sm),
              minimumSize: const Size(48, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              S.of(context).connectionBannerDisconnect,
              style: typography.labelMedium.copyWith(color: colors.error),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small pulsing dot animation for the reconnecting state.
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
