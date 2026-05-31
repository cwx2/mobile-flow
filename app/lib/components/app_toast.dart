/// app_toast.dart — Lightweight toast notification component.
///
/// Slide-in toast from top or bottom, supports success/error/info types.
/// Auto-dismisses after [duration] (default 3s).
///
/// Used by: all screens for user feedback.
library;

import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// Toast type determines icon and accent color.
enum AppToastType { success, error, info }

/// Toast slide direction.
enum AppToastPosition { top, bottom }

/// Show a lightweight toast notification.
///
/// ```dart
/// AppToast.show(context, 'Done', type: AppToastType.success);
/// AppToast.show(context, 'Error', position: AppToastPosition.bottom);
/// ```
class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.info,
    AppToastPosition position = AppToastPosition.top,
    Duration duration = const Duration(seconds: 3),
    IconData? icon,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _AppToastWidget(
        message: message,
        type: type,
        position: position,
        onDismiss: () => entry.remove(),
        duration: duration,
        customIcon: icon,
      ),
    );

    overlay.insert(entry);
  }
}

class _AppToastWidget extends StatefulWidget {
  final String message;
  final AppToastType type;
  final AppToastPosition position;
  final VoidCallback onDismiss;
  final Duration duration;
  final IconData? customIcon;

  const _AppToastWidget({
    required this.message,
    required this.type,
    required this.position,
    required this.onDismiss,
    required this.duration,
    this.customIcon,
  });

  @override
  State<_AppToastWidget> createState() => _AppToastWidgetState();
}

class _AppToastWidgetState extends State<_AppToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _controller.forward();

    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isTop = widget.position == AppToastPosition.top;

    final (defaultIcon, color) = switch (widget.type) {
      AppToastType.success => (Icons.check_circle, colors.success),
      AppToastType.error => (Icons.error, colors.error),
      AppToastType.info => (Icons.info, colors.primary),
    };
    final icon = widget.customIcon ?? defaultIcon;

    // Slide from above (top) or below (bottom)
    final slideBegin = Offset(0, isTop ? -1 : 1);

    return Positioned(
      top: isTop ? MediaQuery.of(context).padding.top + 12 : null,
      bottom: isTop ? null : MediaQuery.of(context).padding.bottom + 80,
      left: 24,
      right: 24,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: slideBegin,
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        )),
        child: FadeTransition(
          opacity: _controller,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.lg,
              vertical: context.spacing.md,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(context.radii.md),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                SizedBox(width: context.spacing.sm),
                Expanded(
                  child: Text(
                    widget.message,
                    style: context.typography.bodyMedium.copyWith(
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
