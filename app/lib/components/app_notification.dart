/// app_notification.dart — Persistent notification overlay component.
///
/// A slide-in notification panel that shows detailed error/info messages
/// requiring user acknowledgment. Unlike AppToast (auto-dismiss, non-interactive),
/// this component persists until manually closed and supports copy/action buttons.
///
/// Usage:
///   AppNotification.show(context, title: '...', detail: '...', type: ...);
///
/// Behavior:
///   - Collapsed: small indicator tab on the right edge (icon + pulse dot)
///   - Expanded: slides left to reveal full notification card
///   - Dismiss: tap close button, swipe right, or tap collapsed indicator again
///   - Copy: copies detail text to clipboard
///   - Draggable: vertical drag to reposition on screen
///   - Single instance: new notification replaces previous one
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../animation/pressable_animator.dart';
import '../theme/theme_extensions.dart';
import '../theme/tokens/color_tokens.dart';
import 'app_toast.dart';

/// Notification severity determines icon and accent color.
enum AppNotificationType { error, info, success }

/// Active overlay key (one instance at a time).
GlobalKey<_AppNotificationOverlayState>? _activeOverlayKey;

/// Persistent notification overlay manager.
///
/// Replaces any existing notification on each [show] call.
/// The notification slides in from the right edge and requires manual dismissal.
class AppNotification {
  AppNotification._();

  static OverlayEntry? _currentEntry;
  static bool _dismissing = false;

  /// Show a persistent notification overlay.
  static void show(
    BuildContext context, {
    required String title,
    String? detail,
    AppNotificationType type = AppNotificationType.error,
  }) {
    // Remove previous entry synchronously to avoid GlobalKey conflicts
    if (_currentEntry != null) {
      _currentEntry!.remove();
      _currentEntry = null;
      _activeOverlayKey = null;
    }
    _dismissing = false;

    final overlay = Overlay.of(context);
    final key = GlobalKey<_AppNotificationOverlayState>();
    _activeOverlayKey = key;

    _currentEntry = OverlayEntry(
      builder: (_) => _AppNotificationOverlay(
        key: key,
        title: title,
        detail: detail,
        type: type,
        onDismiss: dismiss,
      ),
    );
    overlay.insert(_currentEntry!);
  }

  /// Dismiss the current notification if any.
  static void dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    final state = _activeOverlayKey?.currentState;
    if (state != null && state.mounted) {
      state.animateOut();
    } else {
      _removeEntry();
    }
  }

  /// Remove the overlay entry directly (called after animation completes).
  static void _removeEntry() {
    _currentEntry?.remove();
    _currentEntry = null;
    _activeOverlayKey = null;
    _dismissing = false;
  }
}

/// The overlay widget managing the notification lifecycle and animation.
class _AppNotificationOverlay extends StatefulWidget {
  final String title;
  final String? detail;
  final AppNotificationType type;
  final VoidCallback onDismiss;

  const _AppNotificationOverlay({
    super.key,
    required this.title,
    this.detail,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_AppNotificationOverlay> createState() =>
      _AppNotificationOverlayState();
}

class _AppNotificationOverlayState extends State<_AppNotificationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _expanded = true;
  double _bottomOffset = 80;

  @override
  void initState() {
    super.initState();
    // Use motion.slow (350ms) for the slide-in animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  /// Animate out then remove the overlay entry.
  void animateOut() {
    _controller.reverse().then((_) {
      AppNotification._removeEntry();
    });
  }

  void _collapse() => setState(() => _expanded = false);
  void _expand() => setState(() => _expanded = true);

  /// Handle vertical drag to reposition the notification.
  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _bottomOffset -= details.delta.dy;
      final screenHeight = MediaQuery.of(context).size.height;
      final bottomPadding = MediaQuery.of(context).padding.bottom;
      _bottomOffset = _bottomOffset.clamp(bottomPadding + 16, screenHeight - 120);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;

    return Positioned(
      right: 0,
      bottom: _bottomOffset,
      child: Material(
        color: Colors.transparent,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: GestureDetector(
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity != null &&
                    details.primaryVelocity! > 200) {
                  _expanded ? _collapse() : animateOut();
                }
              },
              child: AnimatedSwitcher(
                duration: motion.normal,
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.3, 0.0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: anim, curve: motion.easeOut,
                  )),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: _expanded
                    ? _ExpandedCard(
                        key: const ValueKey('expanded'),
                        title: widget.title,
                        detail: widget.detail,
                        type: widget.type,
                        onClose: animateOut,
                        onCollapse: _collapse,
                      )
                    : _CollapsedTab(
                        key: const ValueKey('collapsed'),
                        type: widget.type,
                        onTap: _expand,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Collapsed state: small tab on the right edge.
class _CollapsedTab extends StatelessWidget {
  final AppNotificationType type;
  final VoidCallback onTap;

  const _CollapsedTab({super.key, required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final isDark = context.isDark;
    final accentColor = _accentColor(type, colors);

    return PressableAnimator(
      onTap: onTap,
      pressScale: 0.9,
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: colors.surfaceElevated.withValues(alpha: isDark ? 0.92 : 0.97),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(radii.md),
            bottomLeft: Radius.circular(radii.md),
          ),
          border: Border.all(
            color: accentColor.withValues(alpha: isDark ? 0.4 : 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: colors.scrim.withValues(alpha: isDark ? 0.2 : 0.08),
              blurRadius: 8,
              offset: const Offset(-2, 0),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(_icon(type), size: 20, color: accentColor),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expanded state: full notification card with glass effect.
class _ExpandedCard extends StatelessWidget {
  final String title;
  final String? detail;
  final AppNotificationType type;
  final VoidCallback onClose;
  final VoidCallback onCollapse;

  const _ExpandedCard({
    super.key,
    required this.title,
    this.detail,
    required this.type,
    required this.onClose,
    required this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radii = context.radii;
    final isDark = context.isDark;
    final accentColor = _accentColor(type, colors);
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.82).clamp(280.0, 360.0);

    return Container(
      width: cardWidth,
      margin: EdgeInsets.only(right: spacing.sm),
      constraints: const BoxConstraints(maxHeight: 220),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radii.lg),
        child: RepaintBoundary(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                // Gradient background matching GlassCard pattern
                gradient: LinearGradient(
                  colors: [
                    colors.surfaceElevated.withValues(alpha: isDark ? 0.78 : 0.92),
                    colors.surface.withValues(alpha: isDark ? 0.9 : 0.98),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(radii.lg),
                border: Border.all(
                  color: accentColor.withValues(alpha: isDark ? 0.3 : 0.4),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.scrim.withValues(alpha: isDark ? 0.18 : 0.07),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: accentColor.withValues(alpha: isDark ? 0.06 : 0.03),
                    blurRadius: 20,
                    offset: const Offset(-2, 0),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: icon + title + collapse/close buttons
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        spacing.lg, spacing.md, spacing.xs, 0),
                    child: Row(
                      children: [
                        Icon(_icon(type), size: 18, color: accentColor),
                        SizedBox(width: spacing.sm),
                        Expanded(
                          child: Text(
                            title,
                            style: context.typography.labelSmall.copyWith(
                              color: accentColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _IconBtn(
                          icon: Icons.chevron_right,
                          onTap: onCollapse,
                          color: colors.onSurfaceMuted,
                        ),
                        _IconBtn(
                          icon: Icons.close,
                          onTap: onClose,
                          color: colors.onSurfaceMuted,
                        ),
                      ],
                    ),
                  ),
                  // Detail text (scrollable)
                  if (detail != null && detail!.isNotEmpty)
                    Flexible(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                            spacing.lg, spacing.sm, spacing.lg, 0),
                        child: SingleChildScrollView(
                          child: Text(
                            detail!,
                            style: context.typography.codeSmall.copyWith(
                              color: colors.onSurfaceVariant,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Action buttons
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        spacing.lg, spacing.sm, spacing.lg, spacing.md),
                    child: Row(
                      children: [
                        if (detail != null && detail!.isNotEmpty)
                          _ActionChip(
                            icon: Icons.copy,
                            label: 'Copy',
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: '$title\n${detail ?? ""}'));
                              HapticFeedback.lightImpact();
                              AppToast.show(context, 'Copied',
                                  type: AppToastType.success);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small icon button for the notification header.
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _IconBtn({required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return PressableAnimator(
      onTap: onTap,
      pressScale: 0.85,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

/// Action chip button (copy, send to AI, etc).
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radii = context.radii;
    final isDark = context.isDark;

    return PressableAnimator(
      onTap: onTap,
      pressScale: 0.93,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceVariant.withValues(alpha: isDark ? 0.6 : 0.8),
          borderRadius: BorderRadius.circular(radii.sm),
          border: Border.all(color: colors.borderSubtle, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: colors.onSurfaceVariant),
            SizedBox(width: spacing.xs),
            Text(
              label,
              style: context.typography.bodySmall.copyWith(
                color: colors.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ──

IconData _icon(AppNotificationType type) => switch (type) {
  AppNotificationType.error => Icons.error_outline,
  AppNotificationType.info => Icons.info_outline,
  AppNotificationType.success => Icons.check_circle_outline,
};

Color _accentColor(AppNotificationType type, AppColorTokens colors) => switch (type) {
  AppNotificationType.error => colors.error,
  AppNotificationType.info => colors.primary,
  AppNotificationType.success => colors.success,
};
