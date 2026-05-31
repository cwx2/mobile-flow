/// send_to_ai_payload.dart — Data model for the "Send to AI" pipeline.
///
/// Any page can construct a [SendToAiPayload] to send content to the AI
/// chat. The payload carries the content, its type, and optional source
/// metadata (file path, line range, language) for rich preview and
/// context reference generation.
library;

/// Content type for the Send to AI pipeline.
///
/// Determines how the content is previewed in the sheet and how it's
/// formatted when sent to the AI (e.g., code gets wrapped in a fenced
/// code block with language tag).
enum SendToAiType {
  /// Source code snippet (with optional file path and line range).
  code,

  /// Diff / file change content.
  diff,

  /// Terminal output.
  terminal,

  /// File reference (send entire file for analysis).
  file,

  /// Run a file (ask AI to execute it via terminal).
  run,

  /// Error message or stack trace.
  error,

  /// Plain text (generic fallback).
  text,
}

/// Payload for the "Send to AI" pipeline.
///
/// Constructed by any page that wants to send content to the AI chat.
/// Passed to [SendToAiService.send()] which shows the confirmation
/// sheet and handles the actual sending.
class SendToAiPayload {
  /// Content type (determines preview style and formatting).
  final SendToAiType type;

  /// The actual content to send (code, text, terminal output, etc.).
  final String content;

  /// Source file path (optional, for code/diff/file types).
  final String? filePath;

  /// Start line number in the source file (1-based, optional).
  final int? startLine;

  /// End line number in the source file (1-based, optional).
  final int? endLine;

  /// Programming language for syntax highlighting (optional).
  final String? language;

  const SendToAiPayload({
    required this.type,
    required this.content,
    this.filePath,
    this.startLine,
    this.endLine,
    this.language,
  });

  /// Human-readable label for the content type (used in sheet header).
  String get typeLabel => switch (type) {
        SendToAiType.code => '代码',
        SendToAiType.diff => '变更',
        SendToAiType.terminal => '终端输出',
        SendToAiType.file => '文件',
        SendToAiType.run => '运行文件',
        SendToAiType.error => '错误',
        SendToAiType.text => '文本',
      };

  /// Source description (e.g., "auth.py:42-58") for display.
  String get sourceLabel {
    if (filePath == null || filePath!.isEmpty) return '';
    final name = filePath!.split('/').last;
    if (startLine != null && endLine != null) {
      return '$name:$startLine-$endLine';
    }
    if (startLine != null) return '$name:$startLine';
    return name;
  }

  /// Format the content as a message string for the AI.
  ///
  /// Wraps code in fenced code blocks with language tag, prefixes
  /// terminal output with a label, etc. Truncates content exceeding
  /// [_maxContentChars] to stay within reasonable token limits.
  String formatForAi(String userDescription) {
    final buf = StringBuffer();
    if (userDescription.isNotEmpty) {
      buf.writeln(userDescription);
      buf.writeln();
    }

    // Truncate overly long content to prevent token budget overflow.
    // Agent-side token_budget is 30000 tokens (~120K chars); we cap at
    // 50K chars to leave room for description, system prompt, and history.
    final truncated = content.length > _maxContentChars
        ? '${content.substring(0, _maxContentChars)}\n\n... (truncated, ${content.length} chars total)'
        : content;

    switch (type) {
      case SendToAiType.code:
        if (filePath != null) buf.writeln('File: $sourceLabel');
        buf.writeln('```${language ?? ''}');
        buf.writeln(truncated);
        buf.writeln('```');
      case SendToAiType.diff:
        if (filePath != null) buf.writeln('File: $sourceLabel');
        buf.writeln('```diff');
        buf.writeln(truncated);
        buf.writeln('```');
      case SendToAiType.terminal:
        buf.writeln('Terminal output:');
        buf.writeln('```');
        buf.writeln(truncated);
        buf.writeln('```');
      case SendToAiType.error:
        buf.writeln('Error:');
        buf.writeln('```');
        buf.writeln(truncated);
        buf.writeln('```');
      case SendToAiType.file:
        if (content.isEmpty && filePath != null) {
          // File reference only (no inline content) — ask AI to read it
          if (userDescription.isEmpty) {
            buf.writeln('Please analyze this file: ${filePath!}');
          } else {
            buf.writeln('File: ${filePath!}');
          }
        } else {
          if (filePath != null) buf.writeln('File: $sourceLabel');
          buf.writeln('```${language ?? ''}');
          buf.writeln(truncated);
          buf.writeln('```');
        }
      case SendToAiType.run:
        if (userDescription.isEmpty) {
          buf.writeln('Please run this file: ${filePath ?? sourceLabel}');
        }
      case SendToAiType.text:
        buf.writeln(truncated);
    }
    return buf.toString().trimRight();
  }

  /// Max content chars before truncation in formatForAi.
  static const _maxContentChars = 50000;
}
