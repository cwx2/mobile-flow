/// app_dialog.dart — App dialog component.
///
/// Unified styled dialog using the design system's colors, radii, and fonts.
/// Supports: confirm dialog, input dialog, custom content dialog.
/// Replaces native AlertDialog to maintain UI consistency.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../animation/pressable_animator.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';

/// Show an app-styled confirm dialog.
Future<bool?> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
  bool isDanger = false,
}) {
  final effectiveConfirmLabel = confirmLabel ?? S.of(context).commonConfirm;
  final effectiveCancelLabel = cancelLabel ?? S.of(context).commonCancel;
  return showAppDialog<bool>(
    context,
    builder: (ctx) => _AppDialogContent(
      title: title,
      actions: [
        _DialogButton(
          label: effectiveCancelLabel,
          onTap: () => Navigator.pop(ctx, false),
        ),
        _DialogButton(
          label: effectiveConfirmLabel,
          isPrimary: true,
          isDanger: isDanger,
          onTap: () => Navigator.pop(ctx, true),
        ),
      ],
      child: message != null
          ? Padding(
              padding: EdgeInsets.only(bottom: ctx.spacing.lg),
              child: Text(message, style: ctx.typography.bodyMedium.copyWith(
                color: ctx.colors.onSurfaceVariant,
              )),
            )
          : null,
    ),
  );
}

/// Show an app-styled input dialog.
Future<String?> showAppInputDialog(
  BuildContext context, {
  required String title,
  String? hintText,
  String? initialValue,
  String? confirmLabel,
  String? cancelLabel,
}) {
  final effectiveConfirmLabel = confirmLabel ?? S.of(context).commonConfirm;
  final effectiveCancelLabel = cancelLabel ?? S.of(context).commonCancel;
  final controller = TextEditingController(text: initialValue);
  return showAppDialog<String>(
    context,
    builder: (ctx) => _AppDialogContent(
      title: title,
      actions: [
        _DialogButton(
          label: effectiveCancelLabel,
          onTap: () => Navigator.pop(ctx),
        ),
        _DialogButton(
          label: effectiveConfirmLabel,
          isPrimary: true,
          onTap: () {
            final text = controller.text.trim();
            Navigator.pop(ctx, text.isEmpty ? null : text);
          },
        ),
      ],
      child: Padding(
        padding: EdgeInsets.only(bottom: ctx.spacing.lg),
        child: TextField(
          controller: controller,
          autofocus: true,
          style: ctx.typography.bodyMedium,
          cursorColor: ctx.colors.primary,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: ctx.typography.bodyMedium.copyWith(
              color: ctx.colors.onSurfaceMuted,
            ),
            filled: true,
            fillColor: ctx.colors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ctx.radii.md),
              borderSide: BorderSide(color: ctx.colors.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ctx.radii.md),
              borderSide: BorderSide(color: ctx.colors.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ctx.radii.md),
              borderSide: BorderSide(color: ctx.colors.primary, width: 1.5),
            ),
            contentPadding: EdgeInsets.all(ctx.spacing.md),
          ),
        ),
      ),
    ),
  );
}

/// Show an app-styled three-option dialog (save/discard/cancel).
Future<String?> showAppSaveDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? saveLabel,
  String? discardLabel,
  String? cancelLabel,
}) {
  final effectiveSaveLabel = saveLabel ?? S.of(context).componentDialogSave;
  final effectiveDiscardLabel = discardLabel ?? S.of(context).componentDialogDiscard;
  final effectiveCancelLabel = cancelLabel ?? S.of(context).commonCancel;
  return showAppDialog<String>(
    context,
    builder: (ctx) => _AppDialogContent(
      title: title,
      actions: [
        _DialogButton(label: effectiveCancelLabel, onTap: () => Navigator.pop(ctx, 'cancel')),
        _DialogButton(label: effectiveDiscardLabel, isDanger: true, onTap: () => Navigator.pop(ctx, 'discard')),
        _DialogButton(label: effectiveSaveLabel, isPrimary: true, onTap: () => Navigator.pop(ctx, 'save')),
      ],
      child: message != null
          ? Padding(
              padding: EdgeInsets.only(bottom: ctx.spacing.lg),
              child: Text(message, style: ctx.typography.bodyMedium.copyWith(
                color: ctx.colors.onSurfaceVariant,
              )),
            )
          : null,
    ),
  );
}

/// Low-level dialog display method (frosted glass background + custom content).
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: '',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (ctx, anim, secondAnim, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, anim, secondAnim) {
      return Center(child: Material(color: Colors.transparent, child: builder(ctx)));
    },
  );
}

/// Dialog content container.
class _AppDialogContent extends StatelessWidget {
  final String title;
  final Widget? child;
  final List<Widget> actions;

  const _AppDialogContent({
    required this.title,
    this.child,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final spacing = context.spacing;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radii.xl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          decoration: BoxDecoration(
            color: colors.surfaceElevated.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(radii.xl),
            border: Border.all(color: colors.borderSubtle, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Padding(
                padding: EdgeInsets.fromLTRB(spacing.xl, spacing.xl, spacing.xl, spacing.md),
                child: Text(title, style: context.typography.titleMedium),
              ),
              // Content
              if (child != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing.xl),
                  child: child!,
                ),
              // Action buttons
              Padding(
                padding: EdgeInsets.fromLTRB(spacing.md, spacing.sm, spacing.md, spacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions.map((a) => Padding(
                    padding: EdgeInsets.only(left: spacing.sm),
                    child: a,
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog button.
class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isDanger;

  const _DialogButton({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;

    Color bg;
    Color fg;
    if (isPrimary) {
      bg = colors.primary;
      fg = colors.onPrimary;
    } else if (isDanger) {
      bg = colors.error.withValues(alpha: 0.15);
      fg = colors.error;
    } else {
      bg = colors.surfaceVariant;
      fg = colors.onSurface;
    }

    return PressableAnimator(
      onTap: onTap,
      pressScale: 0.94,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.lg,
          vertical: context.spacing.md,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radii.md),
        ),
        child: Text(
          label,
          style: context.typography.labelSmall.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
