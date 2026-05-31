/// device_code_auth.dart — Device Code authentication UI.
///
/// Shown when a CLI requires OAuth login via Device Code Flow.
/// Displays the verification URL and code, with a button to open
/// the URL in the phone's browser. The user completes login in the
/// browser, and the Agent detects completion automatically.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';
import '../utils/logger.dart';

final _log = getLogger('DeviceCodeAuth');

/// Device Code authentication widget.
///
/// Shows a large device code for the user to enter in their browser,
/// a button to open the verification URL, and a waiting indicator.
class DeviceCodeAuth extends StatelessWidget {
  /// The verification URL (e.g. https://www.openai.com/device).
  final String url;

  /// The device code to enter (e.g. ABCD-EFGH).
  final String code;

  /// Optional status message from the agent.
  final String message;

  /// Called when user wants to go back to auth method selection.
  final VoidCallback? onCancel;

  const DeviceCodeAuth({
    super.key,
    required this.url,
    required this.code,
    this.message = '',
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Icon
        Icon(Icons.devices, size: 48, color: colors.primary),
        SizedBox(height: spacing.lg),

        // Title
        Text(
          S.of(context).deviceCodeTitle,
          style: typography.titleMedium,
          textAlign: TextAlign.center,
        ),
        SizedBox(height: spacing.sm),

        // Description
        Text(
          message.isNotEmpty ? message : S.of(context).deviceCodeDescription,
          style: typography.bodySmall.copyWith(color: colors.onSurfaceMuted),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: spacing.xl),

        // Device code (large, copyable)
        if (code.isNotEmpty) ...[
          Text(
            S.of(context).deviceCodeLabel,
            style: typography.labelSmall.copyWith(color: colors.onSurfaceMuted),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: spacing.xs),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              _log.info('验证码已复制: $code');
              AppToast.show(context, S.of(context).deviceCodeCopied, type: AppToastType.success);
            },
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.xl,
                vertical: spacing.lg,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(context.radii.md),
                border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    code,
                    style: typography.displayLarge.copyWith(
                      letterSpacing: 4,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Icon(Icons.copy, size: 18, color: colors.onSurfaceMuted),
                ],
              ),
            ),
          ),
          SizedBox(height: spacing.xs),
          Text(
            S.of(context).deviceCodeTapToCopy,
            style: typography.labelSmall.copyWith(color: colors.onSurfaceMuted),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: spacing.lg),
        ],

        // Hint when code is empty but URL exists
        if (code.isEmpty && url.isNotEmpty) ...[
          Text(
            S.of(context).deviceCodeCheckTerminal,
            style: typography.bodySmall.copyWith(color: colors.onSurfaceMuted),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: spacing.lg),
        ],

        // Open browser button
        if (url.isNotEmpty)
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _openUrl(context),
              icon: const Icon(Icons.open_in_browser),
              label: Text(S.of(context).deviceCodeOpenBrowser),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

        SizedBox(height: spacing.lg),

        // Waiting indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.onSurfaceMuted,
              ),
            ),
            SizedBox(width: spacing.sm),
            Text(
              S.of(context).deviceCodeWaiting,
              style: typography.bodySmall.copyWith(color: colors.onSurfaceMuted),
            ),
          ],
        ),

        SizedBox(height: spacing.md),

        // URL display (for manual copy)
        if (url.isNotEmpty)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              AppToast.show(context, S.of(context).deviceCodeUrlCopied, type: AppToastType.success);
            },
            child: Text(
              url,
              style: typography.codeSmall.copyWith(
                color: colors.secondary,
                decoration: TextDecoration.underline,
                decorationColor: colors.secondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),

        // Cancel button — go back to auth method selection
        if (onCancel != null) ...[
          SizedBox(height: spacing.xl),
          TextButton(
            onPressed: onCancel,
            child: Text(
              S.of(context).deviceCodeSkip,
              style: typography.bodySmall.copyWith(color: colors.onSurfaceMuted),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openUrl(BuildContext context) async {
    _log.info('打开认证 URL: $url');
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        _log.warning('无法打开 URL: $url');
        if (context.mounted) {
          AppToast.show(context, S.of(context).deviceCodeCannotOpenBrowser, type: AppToastType.error);
        }
      }
    } catch (e) {
      _log.severe('打开 URL 失败: $e');
      if (context.mounted) {
        Clipboard.setData(ClipboardData(text: url));
        AppToast.show(context, S.of(context).deviceCodeLinkCopied, type: AppToastType.info);
      }
    }
  }
}
