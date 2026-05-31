/// image_renderer.dart — Base64 PNG image display with pinch-to-zoom.
///
/// Module: widgets/renderers/
/// Responsibility:
///   Displays base64-encoded PNG images with pinch-to-zoom and
///   optional swipe comparison mode for before/after visual diffs.
///
/// Called by:
///   - screens/test_panel/web_preview_panel.dart (visual diff UI)
///   - Any screen needing image display from base64 data
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

/// A widget that displays a base64-encoded PNG image with pinch-to-zoom.
///
/// Supports:
/// - Single image display with interactive zoom/pan
/// - Comparison mode with swipe slider for before/after
class ImageRenderer extends StatelessWidget {
  /// Base64-encoded PNG image data.
  final String imageData;

  /// Optional label shown above the image.
  final String? label;

  const ImageRenderer({
    super.key,
    required this.imageData,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bytes = base64Decode(imageData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Expanded(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, error, __) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image, size: 48, color: colors.error),
                    const SizedBox(height: 8),
                    Text(
                      'Failed to decode image',
                      style: TextStyle(color: colors.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A comparison widget showing before/after images with a swipe slider.
///
/// Displays two images side by side with a draggable divider that
/// reveals the "after" image as the user swipes.
class ImageComparisonRenderer extends StatefulWidget {
  /// Base64-encoded PNG of the "before" state.
  final String beforeImage;

  /// Base64-encoded PNG of the "after" state.
  final String afterImage;

  /// Optional base64-encoded PNG of the diff overlay.
  final String? diffImage;

  const ImageComparisonRenderer({
    super.key,
    required this.beforeImage,
    required this.afterImage,
    this.diffImage,
  });

  @override
  State<ImageComparisonRenderer> createState() =>
      _ImageComparisonRendererState();
}

class _ImageComparisonRendererState extends State<ImageComparisonRenderer> {
  /// Current slider position (0.0 = all before, 1.0 = all after).
  double _sliderPosition = 0.5;

  /// Which view mode is active.
  _CompareMode _mode = _CompareMode.slider;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Column(
      children: [
        // Mode selector
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.md, vertical: spacing.xs),
          child: SegmentedButton<_CompareMode>(
            segments: const [
              ButtonSegment(value: _CompareMode.slider, label: Text('Slider', style: TextStyle(fontSize: 12))),
              ButtonSegment(value: _CompareMode.sideBySide, label: Text('Side', style: TextStyle(fontSize: 12))),
              ButtonSegment(value: _CompareMode.diff, label: Text('Diff', style: TextStyle(fontSize: 12))),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        // Image display
        Expanded(
          child: switch (_mode) {
            _CompareMode.slider => _buildSliderView(context),
            _CompareMode.sideBySide => _buildSideBySideView(context),
            _CompareMode.diff => _buildDiffView(context),
          },
        ),
      ],
    );
  }

  Widget _buildSliderView(BuildContext context) {
    final beforeBytes = base64Decode(widget.beforeImage);
    final afterBytes = base64Decode(widget.afterImage);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final dividerX = width * _sliderPosition;

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _sliderPosition = (details.localPosition.dx / width).clamp(0.0, 1.0);
            });
          },
          child: Stack(
            children: [
              // Before image (full width, clipped from right)
              Positioned.fill(
                child: Image.memory(beforeBytes, fit: BoxFit.contain),
              ),
              // After image (clipped from left)
              Positioned.fill(
                child: ClipRect(
                  clipper: _RightClipper(dividerX),
                  child: Image.memory(afterBytes, fit: BoxFit.contain),
                ),
              ),
              // Divider line
              Positioned(
                left: dividerX - 1,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: context.colors.primary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSideBySideView(BuildContext context) {
    final beforeBytes = base64Decode(widget.beforeImage);
    final afterBytes = base64Decode(widget.afterImage);
    final colors = context.colors;

    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Text('Before', style: TextStyle(fontSize: 11, color: colors.onSurfaceMuted)),
              Expanded(
                child: InteractiveViewer(
                  child: Image.memory(beforeBytes, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: colors.border),
        Expanded(
          child: Column(
            children: [
              Text('After', style: TextStyle(fontSize: 11, color: colors.onSurfaceMuted)),
              Expanded(
                child: InteractiveViewer(
                  child: Image.memory(afterBytes, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDiffView(BuildContext context) {
    final diffData = widget.diffImage ?? widget.afterImage;
    final diffBytes = base64Decode(diffData);

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Image.memory(diffBytes, fit: BoxFit.contain),
    );
  }
}

/// Clips the right portion of a widget starting at [dividerX].
class _RightClipper extends CustomClipper<Rect> {
  final double dividerX;

  _RightClipper(this.dividerX);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(dividerX, 0, size.width, size.height);
  }

  @override
  bool shouldReclip(_RightClipper oldClipper) => dividerX != oldClipper.dividerX;
}

/// Comparison view modes.
enum _CompareMode { slider, sideBySide, diff }
