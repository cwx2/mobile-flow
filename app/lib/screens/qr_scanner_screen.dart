/// qr_scanner_screen.dart - Full-screen QR code scanner for connection pairing.
///
/// Opens the device camera and scans for mobileflow://connect QR codes.
/// Returns [ConnectionParams] on successful scan, or null if cancelled.
/// Handles camera permission denial with a localized error message.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../utils/qr_parser.dart';

final _log = getLogger('QrScanner');

/// Full-screen QR scanner that returns [ConnectionParams] on success.
///
/// Push as a route; pops with [ConnectionParams?] result.
/// Returns null if user cancels via the close button.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();

  /// Guard to prevent multiple pops from rapid barcode detections.
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    _log.fine('检测到二维码: ${rawValue.length} 字符');

    try {
      final params = parseConnectionUrl(rawValue);
      _hasScanned = true;
      _log.info('二维码解析成功: host=${params.host}, port=${params.port}');
      Navigator.of(context).pop(params);
    } on QrParseException catch (e) {
      _log.warning('二维码解析失败: ${e.messageKey}, ${e.detail}');
      _showError(e.messageKey);
    }
  }

  /// Show a localized error via SnackBar without closing the scanner.
  void _showError(String messageKey) {
    if (!mounted) return;
    final l10n = S.of(context);
    final message = switch (messageKey) {
      'connectQrInvalid' => l10n.connectQrInvalid,
      'connectQrInvalidPort' => l10n.connectQrInvalidPort,
      _ => l10n.connectQrInvalid,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera feed with permission handling
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return _buildPermissionDenied(context);
            },
          ),

          // Viewfinder overlay
          _buildViewfinderOverlay(),

          // Instruction text at bottom
          _buildInstructionText(context),

          // Close button (top-left, 48dp touch target)
          _buildCloseButton(context),
        ],
      ),
    );
  }

  /// Semi-transparent overlay with a clear 250x250 square in the center.
  Widget _buildViewfinderOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const viewfinderSize = 250.0;
        final left = (constraints.maxWidth - viewfinderSize) / 2;
        final top = (constraints.maxHeight - viewfinderSize) / 2;

        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _ViewfinderPainter(
            viewfinderRect: Rect.fromLTWH(left, top, viewfinderSize, viewfinderSize),
          ),
        );
      },
    );
  }

  /// Instruction text positioned near the bottom of the screen.
  Widget _buildInstructionText(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.of(context).padding.bottom + 80,
      child: Text(
        S.of(context).connectScanInstruction,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Close button in the top-left corner with 48dp minimum touch target.
  Widget _buildCloseButton(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 8,
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          onPressed: () => Navigator.of(context).pop(null),
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          tooltip: S.of(context).connectScanClose,
        ),
      ),
    );
  }

  /// Shown when camera permission is denied.
  Widget _buildPermissionDenied(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          S.of(context).connectScanCameraRequired,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the viewfinder overlay.
///
/// Draws a semi-transparent dark background with a clear rectangular
/// cutout in the center, plus corner brackets for visual guidance.
class _ViewfinderPainter extends CustomPainter {
  final Rect viewfinderRect;

  _ViewfinderPainter({required this.viewfinderRect});

  @override
  void paint(Canvas canvas, Size size) {
    // Semi-transparent background
    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.6);
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Draw background with cutout using path difference
    final bgPath = Path()..addRect(fullRect);
    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(viewfinderRect, const Radius.circular(12)));
    final overlayPath =
        Path.combine(PathOperation.difference, bgPath, cutoutPath);
    canvas.drawPath(overlayPath, bgPaint);

    // Draw corner brackets
    final bracketPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const bracketLength = 24.0;
    const radius = 12.0;
    final r = viewfinderRect;

    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(r.left, r.top + bracketLength)
        ..lineTo(r.left, r.top + radius)
        ..quadraticBezierTo(r.left, r.top, r.left + radius, r.top)
        ..lineTo(r.left + bracketLength, r.top),
      bracketPaint,
    );

    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(r.right - bracketLength, r.top)
        ..lineTo(r.right - radius, r.top)
        ..quadraticBezierTo(r.right, r.top, r.right, r.top + radius)
        ..lineTo(r.right, r.top + bracketLength),
      bracketPaint,
    );

    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(r.left, r.bottom - bracketLength)
        ..lineTo(r.left, r.bottom - radius)
        ..quadraticBezierTo(r.left, r.bottom, r.left + radius, r.bottom)
        ..lineTo(r.left + bracketLength, r.bottom),
      bracketPaint,
    );

    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(r.right - bracketLength, r.bottom)
        ..lineTo(r.right - radius, r.bottom)
        ..quadraticBezierTo(r.right, r.bottom, r.right, r.bottom - radius)
        ..lineTo(r.right, r.bottom - bracketLength),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) =>
      viewfinderRect != oldDelegate.viewfinderRect;
}
