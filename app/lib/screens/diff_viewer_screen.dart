/// diff_viewer_screen.dart — Diff comparison screen.
///
/// Three viewing modes, freely switchable via toolbar button:
/// 1. Split — top/bottom full-file comparison
/// 2. Side-by-side — left/right comparison (forces landscape orientation)
/// 3. Inline — line-level + character-level highlighting, hunk grouping
///
/// Defaults to split in portrait, side-by-side in landscape.
/// Side-by-side forces landscape so both panels have enough width.
/// Orientation restores when switching to other modes or leaving the screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diff/diff_viewer.dart';
import '../diff/side_by_side_diff_viewer.dart';
import '../diff/split_diff_viewer.dart';
import '../theme/theme_extensions.dart';

/// Diff display mode.
enum _DiffMode { split, sideBySide, inline }

/// Diff comparison screen with three freely switchable modes.
class DiffViewerScreen extends StatefulWidget {
  final String filePath;
  final String oldCode;
  final String newCode;
  final String language;

  /// Whether to show accept/reject buttons in the app bar.
  /// True for AI edit review, false for Git diff viewing.
  final bool showAcceptReject;

  const DiffViewerScreen({
    super.key,
    required this.filePath,
    required this.oldCode,
    required this.newCode,
    this.language = 'python',
    this.showAcceptReject = true,
  });

  @override
  State<DiffViewerScreen> createState() => _DiffViewerScreenState();
}

class _DiffViewerScreenState extends State<DiffViewerScreen> {
  _DiffMode? _userChoice; // null = auto (follow orientation)
  bool _barVisible = true;

  _DiffMode _effectiveMode(bool isLandscape) {
    if (_userChoice != null) return _userChoice!;
    return isLandscape ? _DiffMode.sideBySide : _DiffMode.split;
  }

  void _cycleMode() {
    final current = _effectiveMode(
        MediaQuery.orientationOf(context) == Orientation.landscape);
    final next = switch (current) {
      _DiffMode.split => _DiffMode.sideBySide,
      _DiffMode.sideBySide => _DiffMode.inline,
      _DiffMode.inline => _DiffMode.split,
    };
    setState(() => _userChoice = next);
    _applyOrientation(next);
  }

  /// Force landscape for side-by-side mode, restore for others.
  void _applyOrientation(_DiffMode mode) {
    if (mode == _DiffMode.sideBySide) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  @override
  void dispose() {
    // Restore all orientations when leaving the diff screen
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  IconData _modeIcon(_DiffMode mode) => switch (mode) {
        _DiffMode.split => Icons.view_agenda_outlined,
        _DiffMode.sideBySide => Icons.view_column_outlined,
        _DiffMode.inline => Icons.view_stream_outlined,
      };

  /// Toggle the floating bar visibility.
  void _toggleBar() => setState(() => _barVisible = !_barVisible);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final mode = _effectiveMode(isLandscape);
    final topPadding = MediaQuery.paddingOf(context).top;

    // Diff viewer fills the entire screen; bar floats on top
    final viewer = switch (mode) {
      _DiffMode.split => SplitDiffViewer(
          oldText: widget.oldCode,
          newText: widget.newCode,
          filePath: widget.filePath,
        ),
      _DiffMode.sideBySide => SideBySideDiffViewer(
          oldText: widget.oldCode,
          newText: widget.newCode,
          filePath: widget.filePath,
        ),
      _DiffMode.inline => DiffViewer(
          oldText: widget.oldCode,
          newText: widget.newCode,
          filePath: widget.filePath,
        ),
    };

    return Scaffold(
      backgroundColor: colors.background,
      body: GestureDetector(
        onTap: _toggleBar,
        behavior: HitTestBehavior.translucent,
        child: Stack(children: [
          // Code viewer fills entire screen
          Positioned.fill(child: SafeArea(child: viewer)),

          // Floating bar — slides up to hide, down to show
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            top: _barVisible ? 0 : -(topPadding + 44),
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _barVisible ? 1.0 : 0.0,
              child: Container(
                padding: EdgeInsets.only(top: topPadding),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.95),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 44,
                  child: Row(children: [
                    // Back button
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 20),
                      onPressed: () => Navigator.pop(context),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      constraints: const BoxConstraints(),
                    ),
                    // File name (truncated)
                    Expanded(
                      child: Text(
                        widget.filePath.split('/').last,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Mode cycle
                    IconButton(
                      icon: Icon(_modeIcon(mode), size: 20, color: colors.primary),
                      onPressed: _cycleMode,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      constraints: const BoxConstraints(),
                    ),
                    // Accept / Reject (AI edit review only)
                    if (widget.showAcceptReject) ...[
                      IconButton(
                        icon: Icon(Icons.check_rounded, size: 20, color: colors.success),
                        onPressed: () => Navigator.pop(context, 'accept'),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, size: 20, color: colors.error),
                        onPressed: () => Navigator.pop(context, 'reject'),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                    const SizedBox(width: 8),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
