/// diff_minimap.dart — Diff change position indicator bar.
//
// A narrow bar that marks change positions proportionally.
// Red = deleted, green = added, orange = modified.
// Tap to jump to the corresponding position.
// Reusable by both split_diff_viewer and diff_viewer.
//
// Usage:
//   DiffMinimap(
//     totalRows: 500,
//     changeMarkers: [ChangeMarker(index: 42, type: ChangeType.added), ...],
//     scrollController: _scrollController,
//     itemExtent: 20,
//   )

import 'package:flutter/material.dart';

import 'diff_theme.dart';

/// Change type.
enum ChangeType { added, deleted, modified }

/// Single change marker.
class ChangeMarker {
  final int index; // index in the display list
  final ChangeType type;
  const ChangeMarker({required this.index, required this.type});
}

/// Diff minimap widget.
class DiffMinimap extends StatelessWidget {
  /// Total row count (display list length).
  final int totalRows;

  /// Change marker list.
  final List<ChangeMarker> markers;

  /// Associated vertical scroll controller (for tap-to-jump and viewport position).
  final ScrollController scrollController;

  /// Row height (for calculating jump offset).
  final double itemExtent;

  /// Minimap width.
  final double width;

  const DiffMinimap({
    super.key,
    required this.totalRows,
    required this.markers,
    required this.scrollController,
    this.itemExtent = 20,
    this.width = 10,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          if (totalRows == 0 || height == 0) return const SizedBox.shrink();

          return GestureDetector(
            onTapDown: (details) => _jumpTo(details.localPosition.dy, height),
            onVerticalDragUpdate: (details) =>
                _jumpTo(details.localPosition.dy, height),
            child: AnimatedBuilder(
              animation: scrollController,
              builder: (context, child) {
                // On the first layout frame, the ListView has attached the
                // ScrollPosition (hasClients=true) but hasn't finished
                // measuring yet (viewportDimension is unset). Painting the
                // minimap at this point would crash. Return a plain
                // background and let the next frame — triggered by the
                // scroll controller notification after layout completes —
                // paint the real minimap with correct viewport metrics.
                final ready = scrollController.hasClients &&
                    scrollController.position.hasViewportDimension;
                if (!ready) {
                  return SizedBox(
                    width: width,
                    height: height,
                  );
                }
                return CustomPaint(
                  size: Size(width, height),
                  painter: _MinimapPainter(
                    totalRows: totalRows,
                    markers: markers,
                    viewportFraction: _viewportFraction(height),
                    scrollFraction: _scrollFraction(),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Tap/drag to jump to the corresponding position.
  void _jumpTo(double tapY, double mapHeight) {
    if (!scrollController.hasClients || totalRows == 0) return;
    final fraction = (tapY / mapHeight).clamp(0.0, 1.0);
    final maxScroll = scrollController.position.maxScrollExtent;
    scrollController.jumpTo(fraction * maxScroll);
  }

  /// Fraction of total content currently visible in the viewport.
  double _viewportFraction(double mapHeight) {
    final viewportHeight = scrollController.position.viewportDimension;
    final totalHeight = totalRows * itemExtent;
    if (totalHeight == 0) return 1.0;
    return (viewportHeight / totalHeight).clamp(0.0, 1.0);
  }

  /// Current scroll position as a fraction of total content.
  double _scrollFraction() {
    final maxScroll = scrollController.position.maxScrollExtent;
    if (maxScroll == 0) return 0.0;
    return (scrollController.offset / maxScroll).clamp(0.0, 1.0);
  }
}

/// Minimap painter.
class _MinimapPainter extends CustomPainter {
  final int totalRows;
  final List<ChangeMarker> markers;
  final double viewportFraction;
  final double scrollFraction;

  _MinimapPainter({
    required this.totalRows,
    required this.markers,
    required this.viewportFraction,
    required this.scrollFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF1A1826),
    );

    if (totalRows == 0) return;

    // Change markers (draw a small rect for each marker)
    final markerHeight = (h / totalRows).clamp(2.0, 6.0);
    for (final marker in markers) {
      final y = (marker.index / totalRows) * h;
      final color = switch (marker.type) {
        ChangeType.added => DiffTheme.addedGutter,
        ChangeType.deleted => DiffTheme.deletedGutter,
        ChangeType.modified => const Color(0xFFE0A458),
      };
      canvas.drawRect(
        Rect.fromLTWH(1, y, w - 2, markerHeight),
        Paint()..color = color,
      );
    }

    // Viewport indicator (semi-transparent rect showing visible area)
    final vpHeight = (viewportFraction * h).clamp(8.0, h);
    final vpTop = scrollFraction * (h - vpHeight);
    canvas.drawRect(
      Rect.fromLTWH(0, vpTop, w, vpHeight),
      Paint()..color = const Color(0x30FFFFFF),
    );

    // Viewport border
    canvas.drawRect(
      Rect.fromLTWH(0, vpTop, w, vpHeight),
      Paint()
        ..color = const Color(0x50FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(_MinimapPainter old) =>
      totalRows != old.totalRows ||
      markers.length != old.markers.length ||
      viewportFraction != old.viewportFraction ||
      scrollFraction != old.scrollFraction;
}
