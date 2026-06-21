/// operation_banner.dart — Global floating operation status banner.
///
/// A persistent overlay that slides down from the top when an operation
/// is in progress. Users can collapse it to a small indicator or expand
/// to see full status + action buttons. Works from any page via Overlay.
///
/// Usage:
///   OperationBanner.show(context, label: '...', actions: [...]);
///   OperationBanner.dismiss();
///
/// Behavior:
///   - Expanded: slides down from top, shows label + action buttons
///   - Collapsed: small pill indicator at top-right, tap to expand
///   - Dismiss: call OperationBanner.dismiss() when operation completes
///   - Auto-dismiss: pass autoHide duration to auto-dismiss on success
library;

import 'package:flutter/material.dart';

import '../animation/pressable_animator.dart';
import '../theme/theme_extensions.dart';

/// A single action button configuration for the banner.
class BannerAction {
  /// Button label text.
  final String label;

  /// Accent color for the button.
  final Color color;

  /// Whether the button is enabled (grayed out if false).
  final bool enabled;

  /// Tap callback.
  final VoidCallback? onTap;

  const BannerAction({
    required this.label,
    required this.color,
    this.enabled = true,
    this.onTap,
  });
}

/// Global key for single-instance management.
GlobalKey<_OperationBannerOverlayState>? _activeBannerKey;

/// Global floating operation banner (Overlay-based, works from any page).
class OperationBanner {
  OperationBanner._();

  static OverlayEntry? _currentEntry;

  /// Show a floating operation banner from the top.
  static void show(
    BuildContext context, {
    required String label,
    IconData icon = Icons.warning_amber_rounded,
    Color? accentColor,
    List<BannerAction> actions = const [],
  }) {
    // Remove previous synchronously
    if (_currentEntry != null) {
      _currentEntry!.remove();
      _currentEntry = null;
      _activeBannerKey = null;
    }

    final overlay = Overlay.of(context);
    final key = GlobalKey<_OperationBannerOverlayState>();
    _activeBannerKey = key;

    _currentEntry = OverlayEntry(
      builder: (_) => _OperationBannerOverlay(
        key: key,
        label: label,
        icon: icon,
        accentColor: accentColor,
        actions: actions,
      ),
    );
    overlay.insert(_currentEntry!);
  }

  /// Dismiss the banner with slide-up animation.
  static void dismiss() {
    final state = _activeBannerKey?.currentState;
    if (state != null && state.mounted) {
      state.animateOut();
    } else {
      _removeEntry();
    }
  }

  /// Remove immediately (called after animation completes).
  static void _removeEntry() {
    _currentEntry?.remove();
    _currentEntry = null;
    _activeBannerKey = null;
  }

  /// Whether a banner is currently showing.
  static bool get isActive => _currentEntry != null;
}

/// Overlay widget for the banner.
class _OperationBannerOverlay extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color? accentColor;
  final List<BannerAction> actions;

  const _OperationBannerOverlay({
    super.key,
    required this.label,
    required this.icon,
    this.accentColor,
    required this.actions,
  });

  @override
  State<_OperationBannerOverlay> createState() =>
      _OperationBannerOverlayState();
}

class _OperationBannerOverlayState extends State<_OperationBannerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
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

  void animateOut() {
    _controller.reverse().then((_) {
      OperationBanner._removeEntry();
    });
  }

  void _collapse() => setState(() => _collapsed = true);
  void _expand() => setState(() => _collapsed = false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 4,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: child,
              ),
              child: _collapsed
                  ? _CollapsedPill(
                      key: const ValueKey('collapsed'),
                      icon: widget.icon,
                      accentColor: widget.accentColor,
                      onTap: _expand,
                    )
                  : _ExpandedBanner(
                      key: const ValueKey('expanded'),
                      label: widget.label,
                      icon: widget.icon,
                      accentColor: widget.accentColor,
                      actions: widget.actions,
                      onCollapse: _collapse,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Collapsed state: small pill at top-center.
class _CollapsedPill extends StatelessWidget {
  final IconData icon;
  final Color? accentColor;
  final VoidCallback onTap;

  const _CollapsedPill({
    super.key,
    required this.icon,
    this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final isDark = context.isDark;
    final accent = accentColor ?? colors.warning;

    return Center(
      child: PressableAnimator(
        onTap: onTap,
        pressScale: 0.92,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceElevated.withValues(alpha: isDark ? 0.92 : 0.97),
            borderRadius: BorderRadius.circular(radii.full),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.4 : 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.scrim.withValues(alpha: isDark ? 0.2 : 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 14, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expanded state: full banner with label + actions.
class _ExpandedBanner extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? accentColor;
  final List<BannerAction> actions;
  final VoidCallback onCollapse;

  const _ExpandedBanner({
    super.key,
    required this.label,
    required this.icon,
    this.accentColor,
    required this.actions,
    required this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radii = context.radii;
    final isDark = context.isDark;
    final accent = accentColor ?? colors.warning;

    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: spacing.md),
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.sm,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.surfaceElevated.withValues(alpha: isDark ? 0.92 : 0.97),
              colors.surface.withValues(alpha: isDark ? 0.95 : 0.99),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(radii.md),
          border: Border.all(
            color: accent.withValues(alpha: isDark ? 0.35 : 0.3),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.scrim.withValues(alpha: isDark ? 0.2 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon + label
            Icon(icon, size: 14, color: accent),
            SizedBox(width: spacing.xs),
            Flexible(
              child: Text(
                label,
                style: context.typography.labelSmall.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Action buttons
            if (actions.isNotEmpty) ...[
              SizedBox(width: spacing.sm),
              for (int i = 0; i < actions.length; i++) ...[
                if (i > 0) SizedBox(width: spacing.xs),
                _BannerActionButton(action: actions[i]),
              ],
            ],
            // Collapse button
            SizedBox(width: spacing.xs),
            PressableAnimator(
              onTap: onCollapse,
              pressScale: 0.85,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.expand_less, size: 16,
                    color: colors.onSurfaceMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a single action button inside the banner.
class _BannerActionButton extends StatelessWidget {
  final BannerAction action;

  const _BannerActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radii = context.radii;
    final effectiveColor =
        action.enabled ? action.color : action.color.withValues(alpha: 0.4);

    return PressableAnimator(
      onTap: action.enabled ? action.onTap : null,
      pressScale: 0.93,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.xxs + 1,
        ),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(radii.xs),
          border: Border.all(
            color: effectiveColor.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Text(
          action.label,
          style: context.typography.bodySmall.copyWith(
            color: effectiveColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
