/// tool_call_card.dart — Tool call card (auto-adapts style by kind).
///
/// Maps to ACP tool_call / tool_call_update events.
/// Displays different icons, colors, and layouts based on ToolCallKind:
///   - execute  → terminal icon, shows command
///   - edit     → edit icon (FileEditCard handles separately)
///   - search   → search icon, shows keywords
///   - fetch    → globe icon, shows URL
///   - move     → file move icon, shows path
///   - think    → brain icon, shows reasoning
///   - read     → eye icon, shows file path
///   - other    → generic gear icon

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../../animation/page_transition_builder.dart';
import '../../models/chat_message.dart';
import '../../models/context_reference.dart';
import '../../screens/file_viewer_screen.dart';
import '../../services/websocket_service.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/content_detect.dart';
import '../../utils/logger.dart';
import '../image_viewer.dart';

final _log = getLogger('ToolCallCard');

/// Visual configuration for a tool kind.
class _ToolKindStyle {
  final IconData icon;
  final Color color;
  final String label;

  const _ToolKindStyle(this.icon, this.color, this.label);
}

/// Get visual configuration for a tool [kind] string.
_ToolKindStyle _getKindStyle(String? kind, BuildContext context) {
  final s = S.of(context);
  switch (kind) {
    case 'execute':
      return _ToolKindStyle(Icons.terminal, const Color(0xFFF6C177), s.toolCallKindExecute);
    case 'edit' || 'write':
      return _ToolKindStyle(Icons.edit_note, const Color(0xFFC4A7E7), s.toolCallKindEdit);
    case 'search':
      return _ToolKindStyle(Icons.search, const Color(0xFF9CCFD8), s.toolCallKindSearch);
    case 'fetch':
      return _ToolKindStyle(Icons.language, const Color(0xFF3E8FB0), s.toolCallKindFetch);
    case 'move':
      return _ToolKindStyle(
          Icons.drive_file_move_outline, const Color(0xFFEA9A97), s.toolCallKindMove);
    case 'delete':
      return _ToolKindStyle(
          Icons.delete_outline, const Color(0xFFEB6F92), s.toolCallKindDelete);
    case 'think':
      return _ToolKindStyle(Icons.psychology, const Color(0xFF908CAA), s.toolCallKindThink);
    case 'read':
      return _ToolKindStyle(
          Icons.visibility_outlined, const Color(0xFF9CCFD8), s.toolCallKindRead);
    default:
      return _ToolKindStyle(
          Icons.build_circle_outlined, const Color(0xFF908CAA), s.toolCallKindDefault);
  }
}

/// Card widget that displays an ACP tool call with auto-adapted style by kind.
class ToolCallCard extends StatefulWidget {
  final ContentBlock block;
  const ToolCallCard({super.key, required this.block});

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard>
    with TickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: _shouldReverse(widget.block.toolKind));
  }

  /// Some animations need reverse (breathing, swaying), some don't (rotation).
  bool _shouldReverse(String? kind) {
    return kind == 'think' ||
        kind == 'search' ||
        kind == 'execute' ||
        kind == 'delete';
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Build an animated icon based on tool kind.
  Widget _buildAnimatedIcon(IconData icon, Color color, String? kind) {
    switch (kind) {
      // Terminal: pulse blink (opacity change, simulates cursor)
      case 'execute':
        return FadeTransition(
          opacity: Tween(begin: 0.4, end: 1.0).animate(
            CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
          ),
          child: Icon(icon, size: 16, color: color),
        );

      // Search: left-right sway (simulates scanning)
      case 'search':
        return AnimatedBuilder(
          animation: _animController,
          builder: (_, child) {
            final angle = ((_animController.value - 0.5) * 0.5);
            return Transform.rotate(angle: angle, child: child);
          },
          child: Icon(icon, size: 16, color: color),
        );

      // Network/globe: continuous rotation
      case 'fetch':
        return RotationTransition(
          turns: _animController,
          child: Icon(icon, size: 16, color: color),
        );

      // Thinking: breathing scale
      case 'think':
        return ScaleTransition(
          scale: Tween(begin: 0.8, end: 1.2).animate(
            CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
          ),
          child: Icon(icon, size: 16, color: color),
        );

      // Read: pulse
      case 'read':
        return FadeTransition(
          opacity: Tween(begin: 0.5, end: 1.0).animate(
            CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
          ),
          child: Icon(icon, size: 16, color: color),
        );

      // Delete: left-right shake
      case 'delete':
        return AnimatedBuilder(
          animation: _animController,
          builder: (_, child) {
            final offset = ((_animController.value - 0.5) * 4);
            return Transform.translate(offset: Offset(offset, 0), child: child);
          },
          child: Icon(icon, size: 16, color: color),
        );

      // Default: rotation
      default:
        return RotationTransition(
          turns: _animController,
          child: Icon(icon, size: 16, color: color),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final isRunning = b.toolStatus == ToolStatus.running;
    final isFailed = b.toolStatus == ToolStatus.failed;
    final kindStyle = _getKindStyle(b.toolKind, context);

    final colors = context.colors;

    final statusColor = isFailed
        ? colors.error
        : isRunning
            ? kindStyle.color
            : colors.secondary;
    final statusIcon = isFailed
        ? Icons.error_outline
        : isRunning
            ? kindStyle.icon
            : Icons.check_circle_outline;

    if (!isRunning && _animController.isAnimating) {
      _animController.stop();
    } else if (isRunning && !_animController.isAnimating) {
      _animController.repeat(reverse: _shouldReverse(b.toolKind));
    }

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(b, isRunning, statusColor, statusIcon, kindStyle),
            if (_expanded) _buildContent(b),
          ],
        ),
      ),
    );
  }

  /// Card header.
  Widget _buildHeader(
    ContentBlock b,
    bool isRunning,
    Color color,
    IconData icon,
    _ToolKindStyle kindStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          // Status icon (animated when running)
          isRunning
              ? _buildAnimatedIcon(icon, color, b.toolKind)
              : Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          // Tool name
          Expanded(
            child: Text(
              b.toolName ?? S.of(context).toolCallDefaultName,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Kind label (with icon)
          if (b.toolKind != null && b.toolKind!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kindStyle.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(kindStyle.icon, size: 10, color: kindStyle.color),
                  const SizedBox(width: 3),
                  Text(
                    kindStyle.label,
                    style: TextStyle(fontSize: 10, color: kindStyle.color),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 4),
          Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 16,
            color: context.colors.onSurfaceMuted,
          ),
        ],
      ),
    );
  }

  /// Expanded content (different layout per kind).
  Widget _buildContent(ContentBlock b) {
    final hasProgress = b.toolProgress != null && b.toolProgress!.isNotEmpty;
    final hasLocations = b.toolLocations != null && b.toolLocations!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      decoration: BoxDecoration(
        color: context.colors.surfaceDim,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File location list (tap path to navigate, tap + icon to add to context)
          if (hasLocations)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: b.toolLocations!.map((loc) {
                  final path = loc['path'] as String? ?? '';
                  final line = loc['line'] as int?;
                  final display = line != null ? '$path:$line' : path;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        // Tap path text to open file viewer (only for files, not directories)
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (!looksLikeFile(path)) return;
                              Navigator.of(context).push(AppPageRoute(
                                type: PageTransitionType.slideUp,
                                page: FileViewerScreen(filePath: path, line: line),
                              ));
                            },
                            child: Row(
                              children: [
                                Icon(Icons.open_in_new,
                                    size: 10, color: context.colors.secondary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(display,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.colors.secondary,
                                        fontFamily: 'monospace',
                                        decoration: TextDecoration.underline,
                                        decorationColor: context.colors.secondary,
                                      )),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Tap + icon to add file to pending context references
                        if (path.isNotEmpty)
                          GestureDetector(
                            onTap: () => _addFileToContext(path),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(Icons.add_link,
                                  size: 14, color: context.colors.secondary),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          // Tool content: prefer structured content_blocks, fallback to toolProgress
          if (hasProgress || _hasContentBlocks(b))
            Padding(
              padding: const EdgeInsets.all(4),
              child: _hasContentBlocks(b)
                  ? _buildContentBlocks(b.contentBlocks!)
                  : _buildContentByKind(b.toolKind ?? '', b.toolProgress!),
            ),
          // Embedded terminal output (ACP Terminal type)
          if (b.terminalId != null && b.terminalId!.isNotEmpty)
            _buildTerminalEmbed(b.terminalId!),
        ],
      ),
    );
  }

  /// Check if the block has structured ACP content blocks
  bool _hasContentBlocks(ContentBlock b) {
    return b.contentBlocks != null && b.contentBlocks!.isNotEmpty;
  }

  /// Render structured ACP content blocks (text, image, audio, terminal, etc.)
  Widget _buildContentBlocks(List<Map<String, dynamic>> blocks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((block) {
        final type = block['type'] as String? ?? '';
        switch (type) {
          case 'text':
            final text = (block['text'] as String? ?? '').trim();
            if (text.isEmpty) return const SizedBox.shrink();
            if (text.length > 500) {
              return _CollapsibleText(content: text, isFormatted: true);
            }
            return SelectableText(
              text,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.onSurface,
                height: 1.5,
              ),
            );
          case 'image':
            final data = block['data'] as String? ?? '';
            if (data.isEmpty) return const SizedBox.shrink();
            try {
              final bytes = Uint8List.fromList(base64Decode(data));
              return GestureDetector(
                onTap: () => showImageViewer(context, bytes),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(bytes, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text('Image decode failed'),
                    ),
                  ),
                ),
              );
            } catch (_) {
              return Text('Image decode error', style: TextStyle(color: context.colors.error, fontSize: 11));
            }
          case 'terminal':
            final termId = block['terminal_id'] as String? ?? '';
            if (termId.isNotEmpty) return _buildTerminalEmbed(termId);
            return const SizedBox.shrink();
          case 'resource_link':
            final uri = block['uri'] as String? ?? '';
            final name = block['name'] as String? ?? block['title'] as String? ?? uri;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.link, size: 12, color: context.colors.secondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(name, style: TextStyle(
                      fontSize: 12, color: context.colors.secondary,
                      decoration: TextDecoration.underline,
                    )),
                  ),
                ],
              ),
            );
          case 'raw_output':
            // Non-standard: rawOutput from CLI when content[] is empty
            final data = block['data'];
            if (data == null) return const SizedBox.shrink();
            final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
            return _CollapsibleText(content: jsonStr);
          default:
            // Forward-compatible: render unknown types as text if possible
            final text = block['text'] as String? ?? '';
            if (text.isNotEmpty) {
              return SelectableText(text, style: TextStyle(
                fontSize: 12, color: context.colors.onSurface, fontFamily: 'monospace', height: 1.4,
              ));
            }
            return const SizedBox.shrink();
        }
      }).toList(),
    );
  }

  /// Render expanded content by tool kind.
  Widget _buildContentByKind(String kind, String content) {
    // Detect image data
    final imageBytes = tryExtractImageBytes(content);
    if (imageBytes != null) {
      return GestureDetector(
        onTap: () => showImageViewer(context, imageBytes),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(imageBytes, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('Image decode failed'),
          ),
        ),
      );
    }

    // Large content: try smart formatting before falling back to collapsible raw text
    if (content.length > 500) {
      // Try to parse and render structured JSON content
      final formatted = _tryFormatJsonContent(content);
      if (formatted != null) {
        return _CollapsibleText(content: formatted, isFormatted: true);
      }
      return _CollapsibleText(content: content);
    }

    switch (kind) {
      // Command execution: terminal-style with command + output sections
      case 'execute':
        return _buildExecuteContent(content);

      // Search: search icon + keywords
      case 'search':
        return Row(
          children: [
            Icon(Icons.search, size: 14, color: context.colors.secondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                content,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.secondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        );

      // Network request: globe icon + URL (clickable feel)
      case 'fetch':
        return Row(
          children: [
            const Icon(Icons.language, size: 14, color: Color(0xFF3E8FB0)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                content,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF3E8FB0),
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF3E8FB0),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        );

      // File move: source → target
      case 'move':
        return Row(
          children: [
            const Icon(Icons.drive_file_move_outline,
                size: 14, color: Color(0xFFEA9A97)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                content,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFEA9A97),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        );

      // File delete: red path + delete icon
      case 'delete':
        return Row(
          children: [
            Icon(Icons.delete_outline, size: 14, color: context.colors.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                content,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.error,
                  fontFamily: 'monospace',
                  decoration: TextDecoration.lineThrough,
                  decorationColor: context.colors.error,
                ),
              ),
            ),
          ],
        );

      // Read file: clickable to navigate (files open viewer, directories are ignored)
      case 'read':
        return GestureDetector(
          onTap: () {
            if (isFilePath(content) && looksLikeFile(content)) {
              Navigator.of(context).push(AppPageRoute(
                type: PageTransitionType.slideUp,
                page: FileViewerScreen(filePath: content),
              ));
            }
          },
          child: Row(
            children: [
              Icon(Icons.visibility_outlined,
                  size: 14, color: context.colors.secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  content,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.secondary,
                    fontFamily: 'monospace',
                    // Only underline file paths (not directories) to indicate clickability
                    decoration: isFilePath(content) && looksLikeFile(content)
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: context.colors.secondary,
                  ),
                ),
              ),
            ],
          ),
        );

      // Reasoning: italic gray
      case 'think':
        return Text(
          content,
          style: TextStyle(
            fontSize: 12,
            color: context.colors.onSurfaceVariant,
            fontStyle: FontStyle.italic,
            height: 1.4,
          ),
        );

      // Default: monospace, clickable if file path (not directory)
      default:
        if (isFilePath(content) && looksLikeFile(content)) {
          return GestureDetector(
            onTap: () => Navigator.of(context).push(AppPageRoute(
              type: PageTransitionType.slideUp,
              page: FileViewerScreen(filePath: content),
            )),
            child: Row(
              children: [
                Icon(Icons.open_in_new,
                    size: 12, color: context.colors.secondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    content,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.secondary,
                      fontFamily: 'monospace',
                      decoration: TextDecoration.underline,
                      decorationColor: context.colors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return SelectableText(
          content,
          style: TextStyle(
            fontSize: 12,
            color: context.colors.onSurface,
            fontFamily: 'monospace',
            height: 1.4,
          ),
        );
    }
  }

  /// Build execute (command) tool content with command + output sections
  Widget _buildExecuteContent(String command) {
    // Extract output from content blocks if available
    final b = widget.block;
    final blocks = b.contentBlocks;
    String? output;
    if (blocks != null) {
      final textBlocks = blocks
          .where((bl) => bl['type'] == 'text' && (bl['text'] as String? ?? '').isNotEmpty)
          .map((bl) => bl['text'] as String)
          .toList();
      if (textBlocks.isNotEmpty) {
        output = textBlocks.join('\n').trim();
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11111B),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Command line
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('\$ ', style: TextStyle(
                  fontSize: 12, fontFamily: 'monospace',
                  color: context.colors.warning.withValues(alpha: 0.7),
                )),
                Expanded(
                  child: SelectableText(
                    command,
                    style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace',
                      color: Color(0xFFCDD6F4), height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Output section (if available)
          if (output != null && output.isNotEmpty) ...[
            Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: SelectableText(
                  output.length > 2000 ? '${output.substring(0, 2000)}...' : output,
                  style: const TextStyle(
                    fontSize: 11, fontFamily: 'monospace',
                    color: Color(0xFFA6E3A1), height: 1.3,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Try to extract readable text from JSON tool results.
  /// Looks for "text" fields, "content" arrays, etc. and formats them nicely.
  String? _tryFormatJsonContent(String raw) {
    try {
      final json = jsonDecode(raw);
      final lines = <String>[];
      _extractReadableText(json, lines, 0);
      if (lines.isEmpty) return null;
      return lines.join('\n');
    } catch (_) {
      // Not valid JSON, try simple \n unescape
      if (raw.contains('\\n')) {
        return raw.replaceAll('\\n', '\n').replaceAll('\\t', '  ');
      }
      return null;
    }
  }

  /// Recursively extract human-readable text from JSON structures
  void _extractReadableText(dynamic json, List<String> lines, int depth) {
    if (json is String) {
      final text = json.replaceAll('\\n', '\n').replaceAll('\\t', '  ').trim();
      if (text.isNotEmpty) lines.add(text);
      return;
    }
    if (json is Map) {
      // Direct text field — highest priority
      if (json.containsKey('text') && json['text'] is String) {
        final t = (json['text'] as String).replaceAll('\\n', '\n').replaceAll('\\t', '  ').trim();
        if (t.isNotEmpty) lines.add(t);
      }
      // Recurse into all values to find nested text (handles "Json", "items", etc.)
      for (final entry in json.entries) {
        if (entry.key == 'text') continue; // already handled
        final val = entry.value;
        if (val is Map || val is List) {
          _extractReadableText(val, lines, depth + 1);
        }
      }
      return;
    }
    if (json is List) {
      for (final item in json) {
        _extractReadableText(item, lines, depth);
        if (lines.length > 200) break; // safety limit
      }
    }
  }

  /// Add a file path to pending context references with toast feedback.
  void _addFileToContext(String path) {
    final ref = ContextReference(type: ContextRefType.files, path: path);
    context.read<WebSocketService>().addContextReference(ref);
    AppToast.show(context, S.of(context).toolCallAddedToContext);
    _log.fine('添加文件到上下文: $path');
  }

  /// Embedded terminal output panel (ACP Terminal type content).
  Widget _buildTerminalEmbed(String terminalId) {
    final ws = context.read<WebSocketService>();
    final lines = ws.getTerminalOutput(terminalId);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF11111B),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: context.colors.border.withValues(alpha: 0.5)),
      ),
      constraints: const BoxConstraints(maxHeight: 200),
      child: lines.isEmpty
          ? Text(
              S.of(context).toolCallWaitingTerminal,
              style: TextStyle(
                fontSize: 11,
                color: context.colors.onSurfaceMuted,
                fontFamily: 'monospace',
                fontStyle: FontStyle.italic,
              ),
            )
          : SingleChildScrollView(
              reverse: true, // Auto-scroll to bottom
              child: SelectableText(
                lines.join('\n'),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFA6E3A1),
                  fontFamily: 'monospace',
                  height: 1.3,
                ),
              ),
            ),
    );
  }
}

/// Collapsible long text widget with optional formatted rendering
class _CollapsibleText extends StatefulWidget {
  final String content;
  final bool isFormatted;
  const _CollapsibleText({required this.content, this.isFormatted = false});

  @override
  State<_CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<_CollapsibleText> {
  bool _showFull = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final preview = widget.content.length > 500
        ? '${widget.content.substring(0, 500)}...'
        : widget.content;
    final displayText = _showFull ? widget.content : preview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          displayText,
          style: TextStyle(
            fontSize: 12,
            color: colors.onSurface,
            fontFamily: widget.isFormatted ? null : 'monospace',
            height: 1.5,
          ),
        ),
        if (widget.content.length > 500)
          GestureDetector(
            onTap: () => setState(() => _showFull = !_showFull),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _showFull ? S.of(context).commonCollapse : S.of(context).widgetExpandAll(widget.content.length),
                style: TextStyle(fontSize: 11, color: colors.primary),
              ),
            ),
          ),
      ],
    );
  }
}
