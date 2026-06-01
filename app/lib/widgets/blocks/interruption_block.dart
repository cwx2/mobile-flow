/// interruption_block.dart — Stream interruption indicator.
///
/// Displayed when an AI response was cut short due to connection loss,
/// watchdog timeout, or manual disconnect. Visually distinct from error
/// blocks — uses a muted warning style rather than red error styling.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/theme_extensions.dart';

/// Visual indicator that the AI response was interrupted.
///
/// Renders as a subtle inline banner with a warning icon and
/// explanatory text. Intentionally understated — the user should
/// notice it but not be alarmed (the partial response is still valid).
class InterruptionBlock extends StatelessWidget {
  const InterruptionBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colors.warning.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 14,
            color: colors.warning,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              S.of(context).chatStreamInterrupted,
              style: typography.labelSmall.copyWith(
                color: colors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
