/// connection_status_indicator.dart — Compact connection status for AppBar.
///
/// Shows the active connection mode icon (WiFi/Cloud/Link) with the icon
/// colour reflecting connection health: green (good), yellow (medium latency),
/// red (high latency or timed out). Tapping opens a live detail bottom sheet.
///
/// The detail sheet features:
///   - Live uptime counter that ticks every second
///   - Heartbeat pulse animation triggered by each pong response
///   - Latency display with colour-coded health indicator
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../components/app_bottom_sheet.dart';
import '../l10n/app_localizations.dart';
import '../screens/connect_screen.dart';
import '../services/connection_manager.dart';
import '../services/connection_service.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../theme/tokens/color_tokens.dart';
import '../utils/format_utils.dart';
import '../utils/logger.dart';

final _log = getLogger('StatusIndicator');

/// Default latency thresholds (milliseconds).
const kDefaultGreenThresholdMs = 100;
const kDefaultRedThresholdMs = 500;

/// Compact connection status indicator for the AppBar.
///
/// Reads [WebSocketService] and [ConnectionService] from Provider.
/// The icon colour directly reflects connection health — no dot overlay.
/// When reconnecting, plays a pulsing opacity animation.
/// When connected, plays a subtle signal ripple animation.
class ConnectionStatusIndicator extends StatelessWidget {
  final int greenThresholdMs;
  final int redThresholdMs;

  const ConnectionStatusIndicator({
    super.key,
    this.greenThresholdMs = kDefaultGreenThresholdMs,
    this.redThresholdMs = kDefaultRedThresholdMs,
  });

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final conn = context.watch<ConnectionService>();
    final colors = context.colors;

    if (!conn.isConnected && !ws.isPingTimedOut) {
      return const SizedBox.shrink();
    }

    final icon = _modeIcon(ws.connectionMode);
    final iconColor = _latencyColor(ws.latencyMs, colors, ws.isPingTimedOut);

    Widget indicator = GestureDetector(
      onTap: () => _showDetailSheet(context, ws, conn),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );

    // Reconnecting: pulsing opacity
    if (ws.isPingTimedOut) {
      indicator = _ReconnectingPulse(child: indicator);
    }
    // Connected with good latency: subtle signal ripple
    else if (ws.latencyMs >= 0 && ws.latencyMs < greenThresholdMs) {
      indicator = _SignalRipple(color: iconColor, child: indicator);
    }

    return indicator;
  }

  IconData _modeIcon(ConnectionMode mode) {
    switch (mode) {
      case ConnectionMode.lan:
        return Icons.wifi;
      case ConnectionMode.relay:
        return Icons.cloud_outlined;
      case ConnectionMode.tunnel:
        return Icons.link;
    }
  }

  Color _latencyColor(int latencyMs, AppColorTokens colors, bool timedOut) {
    if (timedOut || latencyMs < 0) return colors.error;
    if (latencyMs < greenThresholdMs) return colors.success;
    if (latencyMs < redThresholdMs) return colors.warning;
    return colors.error;
  }

  String _modeLabel(BuildContext context, ConnectionMode mode) {
    switch (mode) {
      case ConnectionMode.lan:
        return S.of(context).connectionStatusLan;
      case ConnectionMode.relay:
        return S.of(context).connectionStatusRelay;
      case ConnectionMode.tunnel:
        return S.of(context).connectionStatusTunnel;
    }
  }

  void _showDetailSheet(
    BuildContext context,
    WebSocketService ws,
    ConnectionService conn,
  ) {
    AppBottomSheet.show(context, builder: (ctx) {
      return _LiveConnectionSheet(
        ws: ws,
        conn: conn,
        greenThresholdMs: greenThresholdMs,
        redThresholdMs: redThresholdMs,
        modeLabel: _modeLabel(context, ws.connectionMode),
        modeIcon: _modeIcon(ws.connectionMode),
      );
    });
  }
}

/// Live connection detail sheet with real-time uptime and heartbeat pulse.
///
/// Uses a 1-second [Timer.periodic] to update the uptime display.
/// Listens to [WebSocketService.pongNotifier] to trigger a heartbeat
/// scale + colour animation on the heart icon each time a pong arrives.
class _LiveConnectionSheet extends StatefulWidget {
  final WebSocketService ws;
  final ConnectionService conn;
  final int greenThresholdMs;
  final int redThresholdMs;
  final String modeLabel;
  final IconData modeIcon;

  const _LiveConnectionSheet({
    required this.ws,
    required this.conn,
    required this.greenThresholdMs,
    required this.redThresholdMs,
    required this.modeLabel,
    required this.modeIcon,
  });

  @override
  State<_LiveConnectionSheet> createState() => _LiveConnectionSheetState();
}

class _LiveConnectionSheetState extends State<_LiveConnectionSheet>
    with TickerProviderStateMixin {
  Timer? _uptimeTimer;

  // Heart pulse animation — triggered by each pong
  late AnimationController _heartController;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Heart pulse: quick scale up then bounce back
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.5), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 0.85), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.1), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 25),
    ]).animate(CurvedAnimation(
      parent: _heartController,
      curve: Curves.easeOutCubic,
    ));

    // Listen for pong to trigger heart pulse
    widget.ws.pongNotifier.addListener(_onPong);

    // Trigger one pulse immediately
    Future.microtask(() {
      if (mounted && widget.ws.latencyMs >= 0) {
        _heartController.forward(from: 0);
      }
    });
  }

  void _onPong() {
    if (mounted) _heartController.forward(from: 0);
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    widget.ws.pongNotifier.removeListener(_onPong);
    _heartController.dispose();
    super.dispose();
  }

  Color _latencyColor(int latencyMs, AppColorTokens colors, bool timedOut) {
    if (timedOut || latencyMs < 0) return colors.error;
    if (latencyMs < widget.greenThresholdMs) return colors.success;
    if (latencyMs < widget.redThresholdMs) return colors.warning;
    return colors.error;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;
    final ws = widget.ws;
    final conn = widget.conn;

    final isAlive = ws.latencyMs >= 0 && !ws.isPingTimedOut;
    final latencyColor = _latencyColor(ws.latencyMs, colors, ws.isPingTimedOut);

    final latencyText = ws.isPingTimedOut
        ? S.of(context).connectionStatusTimeout
        : ws.latencyMs >= 0
            ? '${ws.latencyMs}ms'
            : '--';

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.lg, 0, spacing.lg, spacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.of(context).connectionStatusDetails, style: typography.titleMedium),
          SizedBox(height: spacing.md),

          _DetailRow(
            label: S.of(context).connectionStatusMode,
            value: widget.modeLabel,
            icon: widget.modeIcon,
          ),

          _DetailRow(
            label: S.of(context).connectionStatusAddress,
            value: conn.host ?? '--',
            icon: Icons.dns_outlined,
          ),

          // Latency row: ECG trace + pulsing heart + value
          Padding(
            padding: EdgeInsets.symmetric(vertical: spacing.xs),
            child: Row(
              children: [
                Icon(Icons.speed_outlined, size: 18,
                    color: colors.onSurfaceMuted),
                SizedBox(width: spacing.sm),
                Text(S.of(context).connectionStatusLatency, style: typography.bodyMedium.copyWith(
                  color: colors.onSurfaceMuted,
                )),
                SizedBox(width: spacing.sm),
                // ECG trace fills the middle space
                Expanded(
                  child: _EcgTrace(
                    pongNotifier: ws.pongNotifier,
                    color: isAlive ? latencyColor : colors.onSurfaceMuted,
                    isAlive: isAlive,
                  ),
                ),
                SizedBox(width: spacing.xs),
                // Pulsing heart icon — beats on each pong
                isAlive
                    ? ScaleTransition(
                        scale: _heartScale,
                        child: Icon(
                          Icons.favorite,
                          size: 16,
                          color: latencyColor,
                        ),
                      )
                    : Icon(
                        Icons.favorite_border,
                        size: 16,
                        color: colors.onSurfaceMuted,
                      ),
                SizedBox(width: spacing.xs),
                Text(latencyText, style: typography.bodyMedium.copyWith(
                  color: latencyColor,
                )),
              ],
            ),
          ),

          _DetailRow(
            label: S.of(context).connectionStatusUptime,
            value: formatUptime(ws.uptime),
            icon: Icons.timer_outlined,
          ),

          SizedBox(height: spacing.lg),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _log.info('用户手动断开连接');
                Navigator.of(context).pop();
                // Mark state as disconnected FIRST to prevent auto-reconnect
                conn.disconnect();
                ws.connectionManager.disconnect();
                // Prevent ConnectScreen from auto-connecting on next mount
                ConnectScreen.suppressAutoConnect();
              },
              icon: Icon(Icons.link_off, color: colors.error),
              label: Text(S.of(context).connectionStatusDisconnect,
                  style: typography.bodyMedium.copyWith(color: colors.error)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.error),
                padding: EdgeInsets.symmetric(vertical: spacing.sm),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// A single row in the connection detail bottom sheet.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceMuted),
          SizedBox(width: spacing.sm),
          Text(label, style: typography.bodyMedium.copyWith(
            color: colors.onSurfaceMuted,
          )),
          const Spacer(),
          Text(value, style: typography.bodyMedium.copyWith(
            color: colors.onSurface,
          )),
        ],
      ),
    );
  }
}

/// Pulsing opacity animation for the reconnecting state.
class _ReconnectingPulse extends StatefulWidget {
  final Widget child;
  const _ReconnectingPulse({required this.child});

  @override
  State<_ReconnectingPulse> createState() => _ReconnectingPulseState();
}

class _ReconnectingPulseState extends State<_ReconnectingPulse>
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
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Subtle signal ripple animation for the connected state.
class _SignalRipple extends StatefulWidget {
  final Color color;
  final Widget child;
  const _SignalRipple({required this.color, required this.child});

  @override
  State<_SignalRipple> createState() => _SignalRippleState();
}

class _SignalRippleState extends State<_SignalRipple>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: [
            if (_controller.value < 0.5)
              Opacity(
                opacity: (1.0 - _controller.value * 2).clamp(0.0, 0.3),
                child: Container(
                  width: 20 + (_controller.value * 2 * 16),
                  height: 20 + (_controller.value * 2 * 16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            widget.child,
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// ECG-style heartbeat trace that scrolls left continuously.
///
/// Draws a flat baseline that scrolls from right to left. Each time
/// [pongNotifier] fires, injects a sharp spike waveform (like a real
/// ECG QRS complex). When [isAlive] is false, the trace flatlines.
///
/// Uses [LayoutBuilder] to dynamically size the ring buffer to match
/// the actual widget width, so the trace always spans the full
/// available space regardless of screen size or orientation.
///
/// Uses a [Ticker] for frame-driven updates (auto-pauses when the
/// widget is not visible). Advances at ~30fps equivalent speed.
class _EcgTrace extends StatefulWidget {
  final ValueNotifier<int> pongNotifier;
  final Color color;
  final bool isAlive;

  const _EcgTrace({
    required this.pongNotifier,
    required this.color,
    required this.isAlive,
  });

  @override
  State<_EcgTrace> createState() => _EcgTraceState();
}

class _EcgTraceState extends State<_EcgTrace>
    with SingleTickerProviderStateMixin {
  // Ring buffer — dynamically sized to match widget width
  List<double> _points = [];
  int _writeHead = 0;
  int _bufferSize = 0;

  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  static const _tickInterval = Duration(milliseconds: 33);

  // QRS spike waveform — each sample repeated twice for wider visual pulse.
  // Negative = up, positive = down (relative to baseline center).
  static const _qrsWaveform = [
    0.0, 0.0,
    -0.08, -0.08, -0.12, -0.12,   // P wave (gentle bump up)
    0.08, 0.08, 0.12, 0.12,       // small dip before spike
    -0.5, -0.75, -0.95, -0.95,    // R wave (sharp spike up)
    0.4, 0.55, 0.35, 0.2,         // S wave (sharp dip down)
    -0.05, -0.03, 0.0, 0.0, 0.0,  // T wave recovery to baseline
  ];
  int _waveformIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.pongNotifier.addListener(_onPong);

    _ticker = createTicker(_onTick);
    _ticker.start();

    // Inject an initial spike so user sees the effect immediately
    if (widget.isAlive) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _onPong();
      });
    }
  }

  /// Resize the buffer to match the actual widget width.
  ///
  /// Called on first build and whenever the layout width changes
  /// (e.g. orientation change). Preserves existing data where
  /// possible by copying the tail of the old buffer.
  void _ensureBufferSize(int newSize) {
    if (newSize == _bufferSize && _points.isNotEmpty) return;
    if (newSize <= 0) return;

    final oldPoints = _points;
    final oldSize = _bufferSize;
    final oldHead = _writeHead;

    _bufferSize = newSize;
    _points = List.filled(newSize, 0.0);

    if (oldPoints.isNotEmpty) {
      // Copy as much old data as fits, reading backwards from old head
      final copyCount = oldSize < newSize ? oldSize : newSize;
      for (int i = 0; i < copyCount; i++) {
        final srcIdx = (oldHead - 1 - i + oldSize) % oldSize;
        final dstIdx = (newSize - 1 - i + newSize) % newSize;
        _points[dstIdx] = oldPoints[srcIdx];
      }
      // Place write head at the end so new data appears at right edge
      _writeHead = 0;
    } else {
      // Fresh buffer — start writing from the end so the full line
      // is visible immediately (all zeros = flat baseline)
      _writeHead = 0;
    }
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _lastTick < _tickInterval) return;
    _lastTick = elapsed;
    if (_bufferSize == 0) return;
    _advanceTrace();
    setState(() {});
  }

  void _onPong() {
    _waveformIndex = 0;
  }

  void _advanceTrace() {
    double y = 0.0;
    if (_waveformIndex >= 0 && _waveformIndex < _qrsWaveform.length) {
      y = _qrsWaveform[_waveformIndex];
      _waveformIndex++;
      if (_waveformIndex >= _qrsWaveform.length) {
        _waveformIndex = -1;
      }
    }
    _points[_writeHead] = y;
    _writeHead = (_writeHead + 1) % _bufferSize;
  }

  @override
  void didUpdateWidget(covariant _EcgTrace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pongNotifier != widget.pongNotifier) {
      oldWidget.pongNotifier.removeListener(_onPong);
      widget.pongNotifier.addListener(_onPong);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.pongNotifier.removeListener(_onPong);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      // LayoutBuilder gives us the actual available width so we
      // can size the ring buffer to match — no hardcoded constants.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.ceil();
          _ensureBufferSize(width);
          return CustomPaint(
            painter: _EcgPainter(
              points: _points,
              writeHead: _writeHead,
              bufferSize: _bufferSize,
              color: widget.color,
              isAlive: widget.isAlive,
            ),
            size: Size(constraints.maxWidth, 24),
          );
        },
      ),
    );
  }
}

/// CustomPainter that draws the ECG trace from the ring buffer.
///
/// Reads points backwards from [writeHead], drawing newest data
/// at the right edge scrolling left. The number of points drawn
/// equals the widget width, which equals the buffer size.
class _EcgPainter extends CustomPainter {
  final List<double> points;
  final int writeHead;
  final int bufferSize;
  final Color color;
  final bool isAlive;

  _EcgPainter({
    required this.points,
    required this.writeHead,
    required this.bufferSize,
    required this.color,
    required this.isAlive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bufferSize < 2) return;

    final paint = Paint()
      ..color = isAlive ? color : color.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final midY = size.height / 2;
    final amplitude = size.height * 0.45;
    final drawCount = size.width.toInt().clamp(0, bufferSize);

    final path = Path();
    for (int i = 0; i < drawCount; i++) {
      final bufIndex = (writeHead - 1 - i + bufferSize) % bufferSize;
      final x = size.width - i.toDouble();
      final y = midY + points[bufIndex] * amplitude;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Subtle baseline reference
    final baselinePaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), baselinePaint);
  }

  @override
  bool shouldRepaint(covariant _EcgPainter oldDelegate) => true;
}
