/// app_bottom_sheet.dart — App bottom sheet component.
///
/// Module: components/
/// Responsibility:
///   GlassCard-styled bottom sheet with a top drag handle,
///   supports gesture-based drag-to-dismiss.
///   Uses a spring-curve slide-up animation for a polished feel.
library;

import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import '../utils/logger.dart';

final _log = getLogger('BottomSheet');

/// Show an app-styled bottom sheet.
///
/// Usage:
/// ```dart
/// AppBottomSheet.show(context, builder: (ctx) => YourContent());
/// ```
class AppBottomSheet {
  AppBottomSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isDismissible = true,
    bool enableDrag = true,
  }) async {
    // Temporarily disable focus on the primary focus node to prevent
    // Flutter's route focus restoration from re-focusing the TextField
    // when the dialog closes. This is more reliable than unfocus()
    // because it blocks the focus request at the FocusNode level,
    // before the keyboard show request reaches the platform.
    final previousFocus = FocusManager.instance.primaryFocus;
    final wasFocusable = previousFocus?.canRequestFocus ?? true;
    previousFocus?.canRequestFocus = false;
    _log.fine('弹窗打开: 禁用焦点恢复, node=${previousFocus?.debugLabel}');

    final colors = context.colors;
    final radii = context.radii;
    final spacing = context.spacing;

    final result = await showGeneralDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        // Spring-curve slide up from bottom + fade barrier
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
      pageBuilder: (ctx, anim, secondAnim) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radii.xl),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    GestureDetector(
                      onVerticalDragEnd: enableDrag
                          ? (details) {
                              // Swipe down to dismiss
                              if (details.primaryVelocity != null &&
                                  details.primaryVelocity! > 300) {
                                Navigator.of(ctx).pop();
                              }
                            }
                          : null,
                      child: Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        padding: EdgeInsets.symmetric(vertical: spacing.md),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.onSurfaceMuted.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(radii.full),
                          ),
                        ),
                      ),
                    ),
                    Flexible(child: builder(ctx)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    // Restore focusability after dialog closes. The brief window
    // where canRequestFocus=false prevents the route pop from
    // triggering keyboard show via focus restoration.
    previousFocus?.canRequestFocus = wasFocusable;
    _log.fine('弹窗关闭: 恢复焦点能力');

    return result;
  }
}
