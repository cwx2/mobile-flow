/// auth_form.dart — Compact multi-method authentication form.
///
/// Displays all auth methods as a compact grouped list inside one card.
/// Each method is a single row; env_var methods expand inline with
/// smooth animation to show input fields. Browser-auth methods submit
/// immediately on tap.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../utils/logger.dart';

final _log = getLogger('AuthForm');

/// Compact multi-method authentication form with smooth animations.
class AuthForm extends StatefulWidget {
  final List<Map<String, dynamic>> methods;
  final WebSocketService ws;

  const AuthForm({super.key, required this.methods, required this.ws});

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> with TickerProviderStateMixin {
  final _controllers = <String, TextEditingController>{};
  String? _submittingMethod;
  String? _expandedMethod;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < widget.methods.length; i++) ...[
            _buildMethodRow(widget.methods[i]),
            if (i < widget.methods.length - 1)
              Divider(height: 1, color: colors.borderSubtle),
          ],
        ],
      ),
    );
  }

  Widget _buildMethodRow(Map<String, dynamic> method) {
    final colors = context.colors;
    final typography = context.typography;

    final methodId = method['id'] as String? ?? '';
    final methodName = method['name'] as String? ?? 'Authentication';
    final description = method['description'] as String? ?? '';
    final methodType = method['type'] as String? ?? '';
    final link = method['link'] as String? ?? '';
    final vars = (method['vars'] as List?)
            ?.map((v) => Map<String, dynamic>.from(v as Map))
            .toList() ??
        [];

    final isEnvVar = methodType == 'env_var' && vars.isNotEmpty;
    final isSubmitting = _submittingMethod == methodId;
    final isExpanded = _expandedMethod == methodId;

    final IconData icon = isEnvVar ? Icons.key : Icons.open_in_browser;
    final Color iconColor = isEnvVar ? colors.warning : colors.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tappable row
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            if (isEnvVar) {
              setState(() => _expandedMethod = isExpanded ? null : methodId);
            } else {
              _submitBrowserAuth(methodId);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                // Animated icon color on expand
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: (isExpanded ? iconColor : iconColor.withValues(alpha: 0.1)),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(icon, size: 15,
                    color: isExpanded ? Colors.white : iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(methodName, style: typography.bodyMedium.copyWith(fontSize: 13)),
                      if (description.isNotEmpty)
                        Text(
                          description,
                          style: typography.labelSmall.copyWith(
                            color: colors.onSurfaceMuted, fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (isSubmitting)
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: colors.primary),
                  )
                else if (isEnvVar)
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more, size: 18,
                      color: colors.onSurfaceMuted),
                  )
                else
                  Icon(Icons.chevron_right, size: 18,
                    color: colors.onSurfaceMuted),
              ],
            ),
          ),
        ),

        // Smooth expand/collapse with AnimatedSize (no jump, iOS-style)
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isExpanded && isEnvVar
              ? _buildEnvVarExpanded(methodId, vars, link, isSubmitting)
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  Widget _buildEnvVarExpanded(
    String methodId,
    List<Map<String, dynamic>> vars,
    String link,
    bool isSubmitting,
  ) {
    final colors = context.colors;
    final typography = context.typography;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (_, opacity, child) => Opacity(opacity: opacity, child: child),
      child: Container(
      color: colors.surfaceDim,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in vars) ...[
            _buildVarField(v),
            const SizedBox(height: 8),
          ],
          if (link.isNotEmpty) ...[
            GestureDetector(
              onTap: () => _openLink(link),
              child: Text(
                '${S.of(context).authFormGetKey} →',
                style: typography.labelSmall.copyWith(
                  color: colors.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: isSubmitting ? null : () => _submitEnvVar(methodId, vars),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              ),
              child: isSubmitting
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                  : Text(S.of(context).authFormAuthenticate, style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildVarField(Map<String, dynamic> v) {
    final name = v['name'] as String? ?? '';
    final label = v['label'] as String? ?? name;
    final isSecret = v['secret'] as bool? ?? true;
    final isOptional = v['optional'] as bool? ?? false;

    _controllers.putIfAbsent(name, () => TextEditingController());
    final controller = _controllers[name]!;

    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        obscureText: isSecret,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: isOptional ? '${label} (${S.of(context).authFormOptional})' : label,
          labelStyle: const TextStyle(fontSize: 11),
          hintText: isSecret ? S.of(context).authFormPasteKey : S.of(context).authFormEnterValue,
          hintStyle: const TextStyle(fontSize: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          isDense: true,
          suffixIcon: isSecret
              ? const Icon(Icons.visibility_off, size: 14)
              : null,
        ),
      ),
    );
  }

  void _submitEnvVar(String methodId, List<Map<String, dynamic>> vars) {
    _log.info('提交 env_var 认证: method=$methodId');
    final data = <String, String>{};
    for (final v in vars) {
      final name = v['name'] as String? ?? '';
      final value = _controllers[name]?.text.trim() ?? '';
      final isOptional = v['optional'] as bool? ?? false;
      if (value.isEmpty && !isOptional) {
        AppToast.show(context, S.of(context).authFormFillField(v['label'] ?? name), type: AppToastType.error);
        return;
      }
      if (value.isNotEmpty) data[name] = value;
    }
    setState(() => _submittingMethod = methodId);
    widget.ws.cliOps.submitAuth(methodId: methodId, data: data);
    _resetSubmitting();
  }

  void _submitBrowserAuth(String methodId) {
    _log.info('提交浏览器认证: method=$methodId');
    setState(() => _submittingMethod = methodId);
    widget.ws.cliOps.submitAuth(methodId: methodId, data: {});
    _resetSubmitting();
  }

  void _resetSubmitting() {
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted) setState(() => _submittingMethod = null);
    });
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          Clipboard.setData(ClipboardData(text: url));
          AppToast.show(context, S.of(context).authFormLinkCopied, type: AppToastType.info);
        }
      }
    }
  }
}
