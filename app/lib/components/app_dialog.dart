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

/// Show an app-styled error dialog with an optional retry action.
///
/// Displays an error message with prominent styling and offers the user
/// a choice: cancel or retry with an alternative action (e.g. force commit).
/// Used when an operation fails and there's a recoverable alternative.
Future<bool?> showAppErrorActionDialog(
  BuildContext context, {
  required String title,
  required String error,
  String? description,
  String? actionLabel,
  String? cancelLabel,
}) {
  final effectiveActionLabel = actionLabel ?? S.of(context).commonRetry;
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
          label: effectiveActionLabel,
          isDanger: true,
          onTap: () => Navigator.pop(ctx, true),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Error message in highlighted container
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(ctx.spacing.md),
            decoration: BoxDecoration(
              color: ctx.colors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(ctx.radii.sm),
              border: Border.all(color: ctx.colors.error.withValues(alpha: 0.2)),
            ),
            child: Text(
              error,
              style: ctx.typography.codeSmall.copyWith(
                color: ctx.colors.error,
              ),
            ),
          ),
          if (description != null) ...[
            SizedBox(height: ctx.spacing.md),
            Text(
              description,
              style: ctx.typography.bodyMedium.copyWith(
                color: ctx.colors.onSurfaceVariant,
              ),
            ),
          ],
          SizedBox(height: ctx.spacing.lg),
        ],
      ),
    ),
  );
}

/// Data class representing a single option in an options dialog.
class AppDialogOption<T> {
  /// The value returned when this option is selected.
  final T value;

  /// Primary label displayed on the option card.
  final String title;

  /// Optional secondary description below the title.
  final String? subtitle;

  /// Whether this option is dangerous (e.g. hard reset).
  final bool isDanger;

  const AppDialogOption({
    required this.value,
    required this.title,
    this.subtitle,
    this.isDanger = false,
  });
}

/// Show an app-styled radio options dialog.
///
/// Displays a list of selectable options as styled cards with radio behavior.
/// Returns the selected value on confirm, or null on cancel/dismiss.
Future<T?> showAppOptionsDialog<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<AppDialogOption<T>> options,
  T? initialValue,
  String? confirmLabel,
  String? cancelLabel,
  bool isDanger = false,
}) {
  final effectiveConfirmLabel = confirmLabel ?? S.of(context).commonConfirm;
  final effectiveCancelLabel = cancelLabel ?? S.of(context).commonCancel;
  return showAppDialog<T>(
    context,
    builder: (ctx) => _AppOptionsDialogContent<T>(
      title: title,
      message: message,
      options: options,
      initialValue: initialValue ?? (options.isNotEmpty ? options.first.value : null),
      confirmLabel: effectiveConfirmLabel,
      cancelLabel: effectiveCancelLabel,
      isDanger: isDanger,
    ),
  );
}

/// Show an app-styled confirm dialog with an optional checkbox.
///
/// Extends [showAppConfirmDialog] with a toggleable checkbox option.
/// Returns a record of (confirmed, checkboxValue) or null on dismiss.
Future<({bool confirmed, bool checked})?> showAppCheckConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String checkboxLabel,
  bool initialChecked = false,
  String? confirmLabel,
  String? cancelLabel,
  bool isDanger = false,
}) {
  final effectiveConfirmLabel = confirmLabel ?? S.of(context).commonConfirm;
  final effectiveCancelLabel = cancelLabel ?? S.of(context).commonCancel;
  return showAppDialog<({bool confirmed, bool checked})>(
    context,
    builder: (ctx) => _AppCheckConfirmDialogContent(
      title: title,
      message: message,
      checkboxLabel: checkboxLabel,
      initialChecked: initialChecked,
      confirmLabel: effectiveConfirmLabel,
      cancelLabel: effectiveCancelLabel,
      isDanger: isDanger,
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

/// Stateful dialog content for radio options selection.
class _AppOptionsDialogContent<T> extends StatefulWidget {
  final String title;
  final String? message;
  final List<AppDialogOption<T>> options;
  final T? initialValue;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDanger;

  const _AppOptionsDialogContent({
    required this.title,
    this.message,
    required this.options,
    this.initialValue,
    required this.confirmLabel,
    required this.cancelLabel,
    this.isDanger = false,
  });

  @override
  State<_AppOptionsDialogContent<T>> createState() =>
      _AppOptionsDialogContentState<T>();
}

class _AppOptionsDialogContentState<T>
    extends State<_AppOptionsDialogContent<T>> {
  late T? _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.initialValue;
  }

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
                padding: EdgeInsets.fromLTRB(
                    spacing.xl, spacing.xl, spacing.xl, spacing.sm),
                child: Text(widget.title,
                    style: context.typography.titleMedium),
              ),
              // Optional message
              if (widget.message != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      spacing.xl, 0, spacing.xl, spacing.md),
                  child: Text(
                    widget.message!,
                    style: context.typography.bodyMedium.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              // Option cards
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.options.map((option) {
                    final isSelected = _selectedValue == option.value;
                    return _OptionCard<T>(
                      option: option,
                      isSelected: isSelected,
                      onTap: () => setState(() => _selectedValue = option.value),
                    );
                  }).toList(),
                ),
              ),
              SizedBox(height: spacing.md),
              // Action buttons
              Padding(
                padding: EdgeInsets.fromLTRB(
                    spacing.md, spacing.sm, spacing.md, spacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: spacing.sm),
                      child: _DialogButton(
                        label: widget.cancelLabel,
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: spacing.sm),
                      child: _DialogButton(
                        label: widget.confirmLabel,
                        isPrimary: !widget.isDanger,
                        isDanger: widget.isDanger,
                        onTap: () => Navigator.pop(context, _selectedValue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single option card within the options dialog.
class _OptionCard<T> extends StatelessWidget {
  final AppDialogOption<T> option;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final spacing = context.spacing;

    // Selected state colors
    final borderColor = isSelected
        ? (option.isDanger ? colors.error : colors.primary)
        : colors.borderSubtle;
    final bgColor = isSelected
        ? (option.isDanger
            ? colors.error.withValues(alpha: 0.08)
            : colors.primary.withValues(alpha: 0.08))
        : colors.surfaceVariant.withValues(alpha: 0.5);
    final indicatorColor =
        option.isDanger ? colors.error : colors.primary;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: PressableAnimator(
        onTap: onTap,
        pressScale: 0.97,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: spacing.lg,
            vertical: spacing.md,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(radii.md),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Row(
            children: [
              // Custom radio indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? indicatorColor : colors.onSurfaceMuted,
                    width: isSelected ? 5 : 1.5,
                  ),
                  color: isSelected
                      ? indicatorColor.withValues(alpha: 0.1)
                      : Colors.transparent,
                ),
              ),
              SizedBox(width: spacing.md),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.title,
                      style: context.typography.labelSmall.copyWith(
                        color: option.isDanger
                            ? colors.error
                            : colors.onSurface,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    if (option.subtitle != null) ...[
                      SizedBox(height: spacing.xxs),
                      Text(
                        option.subtitle!,
                        style: context.typography.bodySmall.copyWith(
                          color: option.isDanger
                              ? colors.error.withValues(alpha: 0.7)
                              : colors.onSurfaceMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stateful dialog content for confirm dialog with checkbox.
class _AppCheckConfirmDialogContent extends StatefulWidget {
  final String title;
  final String? message;
  final String checkboxLabel;
  final bool initialChecked;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDanger;

  const _AppCheckConfirmDialogContent({
    required this.title,
    this.message,
    required this.checkboxLabel,
    required this.initialChecked,
    required this.confirmLabel,
    required this.cancelLabel,
    this.isDanger = false,
  });

  @override
  State<_AppCheckConfirmDialogContent> createState() =>
      _AppCheckConfirmDialogContentState();
}

class _AppCheckConfirmDialogContentState
    extends State<_AppCheckConfirmDialogContent> {
  late bool _checked;

  @override
  void initState() {
    super.initState();
    _checked = widget.initialChecked;
  }

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
                padding: EdgeInsets.fromLTRB(
                    spacing.xl, spacing.xl, spacing.xl, spacing.md),
                child: Text(widget.title,
                    style: context.typography.titleMedium),
              ),
              // Optional message
              if (widget.message != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      spacing.xl, 0, spacing.xl, spacing.md),
                  child: Text(
                    widget.message!,
                    style: context.typography.bodyMedium.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              // Checkbox option card
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: PressableAnimator(
                  onTap: () => setState(() => _checked = !_checked),
                  pressScale: 0.97,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.lg,
                      vertical: spacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: _checked
                          ? colors.primary.withValues(alpha: 0.08)
                          : colors.surfaceVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(radii.md),
                      border: Border.all(
                        color: _checked
                            ? colors.primary
                            : colors.borderSubtle,
                        width: _checked ? 1.5 : 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Custom checkbox indicator
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _checked
                                  ? colors.primary
                                  : colors.onSurfaceMuted,
                              width: _checked ? 0 : 1.5,
                            ),
                            color: _checked
                                ? colors.primary
                                : Colors.transparent,
                          ),
                          child: _checked
                              ? Icon(Icons.check,
                                  size: 14, color: colors.onPrimary)
                              : null,
                        ),
                        SizedBox(width: spacing.md),
                        Expanded(
                          child: Text(
                            widget.checkboxLabel,
                            style: context.typography.labelSmall.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.md),
              // Action buttons
              Padding(
                padding: EdgeInsets.fromLTRB(
                    spacing.md, spacing.sm, spacing.md, spacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: spacing.sm),
                      child: _DialogButton(
                        label: widget.cancelLabel,
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: spacing.sm),
                      child: _DialogButton(
                        label: widget.confirmLabel,
                        isPrimary: !widget.isDanger,
                        isDanger: widget.isDanger,
                        onTap: () => Navigator.pop(
                          context,
                          (confirmed: true, checked: _checked),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
