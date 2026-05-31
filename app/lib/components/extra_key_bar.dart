/// extra_key_bar.dart — Reusable extra key bar components.
///
/// Provides the visual building blocks for shortcut key bars displayed
/// above the system keyboard. Business logic (Ctrl/Alt toggle, bracket
/// pair completion, etc.) stays in the consuming widgets.
///
/// Components:
///   - [ExtraKeyBar]  — Container with background and top border.
///   - [ExtraKeyRow]  — Horizontally scrollable row of keys.
///   - [ExtraKey]     — Single key button (normal or toggle mode).
///   - [ExtraKeyDivider] — Vertical separator between key groups.
///
/// Used by:
///   - widgets/terminal_extra_keys.dart
///   - widgets/editor_extra_keys.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme_extensions.dart';

// ── Container ──

/// Themed container for one or more [ExtraKeyRow]s.
///
/// Draws a subtle top border and elevated surface background,
/// matching the system keyboard visual style.
class ExtraKeyBar extends StatelessWidget {
  /// Child rows (typically 1–2 [ExtraKeyRow] widgets).
  final List<Widget> children;

  const ExtraKeyBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

// ── Row ──

/// Horizontally scrollable row of key widgets.
///
/// [height] defaults to 36; terminal row 1 uses 38 for larger
/// modifier keys.
class ExtraKeyRow extends StatelessWidget {
  final List<Widget> children;
  final double height;

  const ExtraKeyRow({
    super.key,
    required this.children,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: children,
      ),
    );
  }
}

// ── Key button ──

/// Single key button with press feedback and keyboard-like appearance.
///
/// Normal mode: taps fire [onTap] with haptic + visual press feedback.
/// Toggle mode: set [isActive] and [onToggle] to show a highlighted
/// state (used for Ctrl/Alt modifiers).
///
/// Visual design: raised key appearance with bottom shadow that
/// compresses on press, mimicking a physical keyboard key.
///
/// [small] reduces min-width and font size for dense symbol rows.
class ExtraKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool small;
  final bool isActive;

  const ExtraKey({
    super.key,
    required this.label,
    required this.onTap,
    this.small = false,
    this.isActive = false,
  });

  /// Convenience constructor for toggle-style keys (Ctrl, Alt).
  const ExtraKey.toggle({
    super.key,
    required this.label,
    required this.onTap,
    required this.isActive,
  }) : small = false;

  @override
  State<ExtraKey> createState() => _ExtraKeyState();
}

class _ExtraKeyState extends State<ExtraKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Key face color
    final faceColor = widget.isActive
        ? colors.primary.withValues(alpha: 0.25)
        : colors.surfaceVariant;

    // Bottom edge color (darker, creates depth illusion)
    final edgeColor = widget.isActive
        ? colors.primary.withValues(alpha: 0.4)
        : colors.borderSubtle;

    // Pressed state: key sinks down (reduce bottom shadow)
    final bottomInset = _pressed ? 0.5 : 2.5;
    final topInset = _pressed ? 2.0 : 0.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        constraints: BoxConstraints(minWidth: widget.small ? 32 : 42),
        padding: EdgeInsets.only(
          left: widget.small ? 6 : 8,
          right: widget.small ? 6 : 8,
          top: 3 + topInset,
          bottom: 3 + bottomInset,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2),
        decoration: BoxDecoration(
          color: faceColor,
          borderRadius: BorderRadius.circular(widget.small ? 5 : 6),
          border: widget.isActive
              ? Border.all(color: colors.primary, width: 1)
              : Border.all(color: edgeColor, width: 0.5),
          boxShadow: _pressed
              ? null
              : [
                  BoxShadow(
                    color: edgeColor,
                    offset: const Offset(0, 2),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.small ? 12 : 13,
              color: widget.isActive ? colors.primary : colors.onSurface,
              fontWeight: widget.isActive ? FontWeight.bold : FontWeight.w500,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

// ── Divider ──

/// Vertical separator between key groups within an [ExtraKeyRow].
class ExtraKeyDivider extends StatelessWidget {
  const ExtraKeyDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      color: colors.borderSubtle,
    );
  }
}

// ── Collapse toggle button ──

/// Toggle button for collapsing/expanding key rows.
///
/// Displays a small themed icon button with press feedback.
/// The [icon] and [onTap] are controlled by the consuming widget
/// (which manages its own collapse state).
class ExtraKeyToggle extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const ExtraKeyToggle({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  State<ExtraKeyToggle> createState() => _ExtraKeyToggleState();
}

class _ExtraKeyToggleState extends State<ExtraKeyToggle> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = _pressed ? 0.5 : 2.0;
    final topInset = _pressed ? 1.5 : 0.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        width: 28,
        height: 28,
        margin: EdgeInsets.only(left: 2, right: 2, top: 3 + topInset, bottom: 3 + bottomInset),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          boxShadow: _pressed
              ? null
              : [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.3),
                    offset: const Offset(0, 2),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Icon(widget.icon, size: 18, color: colors.primary),
      ),
    );
  }
}
