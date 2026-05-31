/// thought_block.dart — AI thinking process block (collapsible).
///
/// Maps to ACP agent_thought_chunk events.
/// Streaming chunks are merged into a single block by [ChatMessage.appendThought].
/// Shows "思考中..." with a pulsing indicator while streaming,
/// switches to "思考过程" once the stream finishes.
/// Tap to expand and see the full thinking content.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/theme_extensions.dart';

/// Collapsible AI thought/reasoning block.
///
/// [isStreaming] controls the header label: animated "思考中..." during
/// streaming, static "思考过程" after completion.
class ThoughtBlock extends StatefulWidget {
  final String text;
  final bool isStreaming;

  const ThoughtBlock({
    super.key,
    required this.text,
    this.isStreaming = false,
  });

  @override
  State<ThoughtBlock> createState() => _ThoughtBlockState();
}

class _ThoughtBlockState extends State<ThoughtBlock>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      // Breathing animation for streaming indicator — intentionally slower
      // than the 200ms standard for state transitions, as this is a
      // continuous loop meant to convey "in progress" rather than a
      // discrete state change.
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isStreaming) _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ThoughtBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Start/stop pulse animation based on streaming state
    if (widget.isStreaming && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isStreaming && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: colors.onSurfaceMuted,
                ),
                const SizedBox(width: 4),
                // Pulsing opacity during streaming, static after
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, child) {
                    final opacity = widget.isStreaming
                        ? 0.4 + 0.6 * _pulseController.value
                        : 1.0;
                    return Opacity(opacity: opacity, child: child);
                  },
                  child: Text(
                    widget.isStreaming ? S.of(context).thoughtBlockThinking : S.of(context).thoughtBlockDone,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
