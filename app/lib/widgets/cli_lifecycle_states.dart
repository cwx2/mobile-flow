/// cli_lifecycle_states.dart — CLI lifecycle state UI widgets.
///
/// Full-screen state widgets shown in the chat area based on the
/// CLI provider's lifecycle: initializing, failed, auth required,
/// no project, empty chat, and loading history.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/empty_state.dart';
import '../components/glass_card.dart';
import '../l10n/app_localizations.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../widgets/auth_form.dart';
import '../widgets/device_code_auth.dart';

/// Initializing state: centered spinner with animated status message.
///
/// Includes a retry button that gives the user an escape hatch
/// when initialization gets stuck.
class CliInitializingState extends StatelessWidget {
  final WebSocketService ws;

  const CliInitializingState({super.key, required this.ws});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48, height: 48,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: colors.primary),
          ),
          SizedBox(height: context.spacing.lg),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              ws.cliStatusMessage.isNotEmpty
                  ? ws.cliStatusMessage
                  : S.of(context).chatConnectingAgent,
              key: ValueKey(ws.cliStatusMessage),
              style: typography.bodyMedium
                  .copyWith(color: colors.onSurfaceMuted),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: context.spacing.xl),
          TextButton.icon(
            onPressed: () {
              HapticFeedback.selectionClick();
              ws.cliOps.retryCli();
            },
            icon: Icon(Icons.refresh, size: 18,
                color: colors.onSurfaceMuted),
            label: Text(
              S.of(context).commonRetry,
              style: typography.labelMedium
                  .copyWith(color: colors.onSurfaceMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Failed state: error icon + human-readable message + retry button.
///
/// Always shows [ws.cliStatusMessage] (user-facing) instead of
/// [ws.cliErrorMessage] (technical debug info for logs only).
class CliFailedState extends StatelessWidget {
  final WebSocketService ws;

  const CliFailedState({super.key, required this.ws});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: colors.error),
            SizedBox(height: context.spacing.lg),
            Text(
              ws.cliStatusMessage,
              style: typography.bodyMedium
                  .copyWith(color: colors.onSurfaceMuted),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: context.spacing.xl),
            ElevatedButton.icon(
              onPressed: () => ws.cliOps.retryCli(),
              icon: const Icon(Icons.refresh),
              label: Text(S.of(context).commonRetry),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Auth required state: show authentication form or device code UI.
class CliAuthRequiredState extends StatelessWidget {
  final WebSocketService ws;

  const CliAuthRequiredState({super.key, required this.ws});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final methods = ws.authMethods;
    final authType = ws.authType;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Device code flow: show URL + code + open browser button
            if (authType == 'device_code' &&
                (ws.deviceCodeUrl.isNotEmpty ||
                    ws.deviceCode.isNotEmpty))
              DeviceCodeAuth(
                url: ws.deviceCodeUrl,
                code: ws.deviceCode,
                message: ws.cliStatusMessage,
                onCancel: () {
                  ws.clearDeviceCodeState();
                },
              )
            // Env var / default: show API key form
            else ...[
              Icon(Icons.lock_outline, size: 56, color: colors.primary),
              SizedBox(height: context.spacing.lg),
              Text(S.of(context).chatAuthRequired,
                  style: typography.titleMedium),
              SizedBox(height: context.spacing.sm),
              Text(
                ws.cliStatusMessage.isNotEmpty
                    ? ws.cliStatusMessage
                    : S.of(context).chatAuthApiKeyNeeded,
                style: typography.bodySmall
                    .copyWith(color: colors.onSurfaceMuted),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: context.spacing.xl),
              if (methods.isEmpty)
                Text(S.of(context).chatAuthNoMethods,
                    style: typography.bodySmall
                        .copyWith(color: colors.error))
              else
                AuthForm(methods: methods, ws: ws),
            ],
          ],
        ),
      ),
    );
  }
}

/// No project selected prompt.
class ChatNoProjectState extends StatelessWidget {
  const ChatNoProjectState({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.folder_off_outlined,
      title: S.of(context).chatNoProjectTitle,
      description: S.of(context).chatNoProjectDescription,
      useGlassCard: false,
    );
  }
}

/// Empty chat state with suggestion chips and gradient glow icon.
///
/// [onSuggestionTap] is called when the user taps a suggestion chip,
/// passing the suggestion text to be sent as a chat message.
class ChatEmptyState extends StatelessWidget {
  final void Function(String text) onSuggestionTap;

  const ChatEmptyState({super.key, required this.onSuggestionTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: spacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.15),
                    colors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
              child: Icon(Icons.chat_bubble_outline,
                  size: 48, color: colors.primary),
            ),
            SizedBox(height: spacing.lg),
            Text(S.of(context).chatEmptyTitle,
                style: typography.headlineMedium),
            SizedBox(height: spacing.sm),
            Text(
              S.of(context).chatEmptySubtitle,
              style: typography.bodySmall
                  .copyWith(color: colors.onSurfaceMuted),
            ),
            SizedBox(height: spacing.xl),
            Wrap(
              spacing: spacing.sm,
              runSpacing: spacing.sm,
              alignment: WrapAlignment.center,
              children: [
                _SuggestionChip(
                    text: S.of(context).chatSuggestion1,
                    onTap: onSuggestionTap),
                _SuggestionChip(
                    text: S.of(context).chatSuggestion2,
                    onTap: onSuggestionTap),
                _SuggestionChip(
                    text: S.of(context).chatSuggestion3,
                    onTap: onSuggestionTap),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Suggestion chip button (GlassCard style + haptic feedback).
class _SuggestionChip extends StatelessWidget {
  final String text;
  final void Function(String text) onTap;

  const _SuggestionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GlassCard(
      enableBlur: false,
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.md,
        vertical: context.spacing.sm,
      ),
      borderRadius: BorderRadius.circular(context.radii.full),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap(text);
      },
      child: Text(
        text,
        style: context.typography.bodySmall
            .copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}
