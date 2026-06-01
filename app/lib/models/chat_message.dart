/// chat_message.dart — Chat message model and content blocks.
///
/// Aligned with ACP event types, supports AI IDE-style rendering
/// (text, thought, tool calls, file edits, plans, code blocks, errors).

enum ChatRole { user, assistant, system }

/// Content block type (maps to ACP session/update events).
enum BlockType {
  text, // plain text
  thought, // AI thinking process
  toolCall, // tool invocation (expandable card)
  fileEdit, // file edit (diff preview)
  plan, // multi-step plan
  code, // code block
  error, // error message
  commandList, // available command list
  sessionInfo, // session info
  interruption, // stream interrupted (connection drop / watchdog timeout)
}

/// Tool call execution status.
enum ToolStatus { running, completed, failed }

/// A single chat message containing one or more [ContentBlock]s.
///
/// Messages are either user-sent or assistant-generated. During streaming,
/// [isStreaming] is true and blocks are appended incrementally.
class ChatMessage {
  final String id;
  final ChatRole role;
  final List<ContentBlock> blocks;
  final DateTime timestamp;
  bool isStreaming;

  /// Whether this message was interrupted before completion (connection drop,
  /// watchdog timeout, or manual disconnect). UI renders a visual indicator.
  bool isInterrupted;

  /// Local attachment file paths (for user messages with images/files).
  /// These are local paths used for UI display only; the actual content
  /// is sent as base64 via the WebSocket payload.
  final List<String> attachmentPaths;

  ChatMessage({
    String? id,
    required this.role,
    List<ContentBlock>? blocks,
    DateTime? timestamp,
    this.isStreaming = false,
    this.isInterrupted = false,
    List<String>? attachmentPaths,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toRadixString(36),
        blocks = blocks ?? [],
        timestamp = timestamp ?? DateTime.now(),
        attachmentPaths = attachmentPaths ?? [];

  /// Append text, merging into the last text block if possible.
  void appendText(String text) {
    if (blocks.isNotEmpty && blocks.last.type == BlockType.text) {
      blocks.last.text += text;
    } else {
      blocks.add(ContentBlock.text(text));
    }
  }

  /// Append thought text, merging into the last thought block if possible.
  ///
  /// Mirrors [appendText] logic: ACP sends thinking as many small chunks,
  /// so we merge them into a single thought block for clean UI display.
  void appendThought(String text) {
    if (blocks.isNotEmpty && blocks.last.type == BlockType.thought) {
      blocks.last.text += text;
    } else {
      blocks.add(ContentBlock.thought(text));
    }
  }

  /// Append a content block to this message.
  void addBlock(ContentBlock block) {
    blocks.add(block);
  }

  /// Extract concatenated plain text from all text blocks.
  String get plainText => blocks
      .where((b) => b.type == BlockType.text)
      .map((b) => b.text)
      .join('\n');

  /// Update the status of a specific tool card by [toolId].
  ///
  /// If [toolId] is empty, updates the last running tool card instead.
  void updateToolStatus(String toolId, String status, {String? progress, List<Map<String, dynamic>>? contentBlocks}) {
    if (toolId.isEmpty) {
      for (var i = blocks.length - 1; i >= 0; i--) {
        if (blocks[i].type == BlockType.toolCall &&
            blocks[i].toolStatus == ToolStatus.running) {
          blocks[i].updateStatus(status, progress: progress, newContentBlocks: contentBlocks);
          return;
        }
      }
      return;
    }
    for (final block in blocks) {
      if (block.type == BlockType.toolCall && block.toolId == toolId) {
        block.updateStatus(status, progress: progress, newContentBlocks: contentBlocks);
        return;
      }
    }
    // Fallback: update the last running tool if exact ID not found
    for (var i = blocks.length - 1; i >= 0; i--) {
      if (blocks[i].type == BlockType.toolCall &&
          blocks[i].toolStatus == ToolStatus.running) {
        blocks[i].updateStatus(status, progress: progress, newContentBlocks: contentBlocks);
        return;
      }
    }
  }

  /// Mark all still-running tools as completed when the turn ends.
  void finalizeAllTools() {
    for (final block in blocks) {
      if (block.type == BlockType.toolCall &&
          block.toolStatus == ToolStatus.running) {
        block.toolStatus = ToolStatus.completed;
      }
    }
  }
}

/// A single file edit record with accept/reject tracking.
///
/// Each AI file edit produces one entry. Multiple edits to the same file
/// are grouped into a single [ContentBlock] of type [BlockType.fileEdit].
class FileEditEntry {
  final String oldContent;
  final String newContent;
  final DateTime timestamp;
  bool? accepted; // null=pending, true=accepted, false=rejected

  FileEditEntry({
    required this.oldContent,
    required this.newContent,
    DateTime? timestamp,
    this.accepted,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Number of lines added compared to old content.
  int get linesAdded {
    final oldLines = oldContent.isEmpty ? 0 : oldContent.split('\n').length;
    final newLines = newContent.isEmpty ? 0 : newContent.split('\n').length;
    return (newLines - oldLines).clamp(0, 999999);
  }

  /// Number of lines deleted compared to old content.
  int get linesDeleted {
    final oldLines = oldContent.isEmpty ? 0 : oldContent.split('\n').length;
    final newLines = newContent.isEmpty ? 0 : newContent.split('\n').length;
    return (oldLines - newLines).clamp(0, 999999);
  }

  bool get isPending => accepted == null;
  bool get isAccepted => accepted == true;
  bool get isRejected => accepted == false;
}

/// A content block within a [ChatMessage] (maps to ACP session/update events).
///
/// Each block has a [type] and type-specific fields (tool info, file edit
/// data, plan entries, etc.). Factory constructors provide convenient creation.
class ContentBlock {
  final BlockType type;
  String text;

  // Tool call fields
  String? toolName;
  /// Tool kind: execute / edit / search / fetch / move / think / read / other
  String? toolKind;
  String? toolId;
  ToolStatus? toolStatus;
  String? toolProgress;
  Duration? toolDuration;
  /// File locations involved: [{path, line?}]
  List<Map<String, dynamic>>? toolLocations;
  /// ACP terminal embed ID
  String? terminalId;
  /// ACP ToolCallContent blocks [{type, ...}]
  List<Map<String, dynamic>>? contentBlocks;

  // File edit fields (multiple edits to one file are grouped)
  String? filePath;
  /// Latest edit's old content (backward compat; prefer editEntries)
  String? oldContent;
  /// Latest edit's new content (backward compat; prefer editEntries)
  String? newContent;
  String? editDescription;
  /// Group-level accept status (backward compat; prefer editEntries)
  bool? editAccepted;
  /// Ordered list of edit entries for this file
  List<FileEditEntry> editEntries = [];

  // Code block fields
  String? language;

  // Plan fields
  List<PlanEntry>? planEntries;

  // Command list
  List<Map<String, String>>? commands;

  // Session info
  double? contextUsage;

  // Thought block streaming state
  /// Whether the thinking phase has completed (no more thought chunks expected).
  /// Set by ChatState when a non-thinking chunk arrives after thinking chunks.
  bool isThinkingDone = false;

  ContentBlock({
    required this.type,
    this.text = '',
    this.toolName,
    this.toolKind,
    this.toolId,
    this.toolStatus,
    this.toolProgress,
    this.toolDuration,
    this.toolLocations,
    this.terminalId,
    this.contentBlocks,
    this.filePath,
    this.oldContent,
    this.newContent,
    this.editDescription,
    this.editAccepted,
    List<FileEditEntry>? editEntries,
    this.language,
    this.planEntries,
    this.commands,
    this.contextUsage,
  }) {
    if (editEntries != null) this.editEntries = editEntries;
  }

  // Factory constructors

  /// Create a plain text block.
  factory ContentBlock.text(String text) =>
      ContentBlock(type: BlockType.text, text: text);

  /// Create a thought/reasoning block.
  factory ContentBlock.thought(String text) =>
      ContentBlock(type: BlockType.thought, text: text);

  /// Create an error block.
  factory ContentBlock.error(String text) =>
      ContentBlock(type: BlockType.error, text: text);

  /// Create a tool call block with running status.
  factory ContentBlock.toolCall({
    required String name,
    String? kind,
    String? id,
    String? toolInput,
    List<Map<String, dynamic>>? locations,
    String? terminalId,
    List<Map<String, dynamic>>? contentBlocks,
    ToolStatus status = ToolStatus.running,
  }) =>
      ContentBlock(
        type: BlockType.toolCall,
        toolName: name,
        toolKind: kind,
        toolId: id,
        toolStatus: status,
        toolProgress: toolInput,
        toolLocations: locations,
        terminalId: terminalId,
        contentBlocks: contentBlocks,
      );

  /// Update tool status and merge content blocks from updates.
  void updateStatus(String statusStr, {String? progress, List<Map<String, dynamic>>? newContentBlocks}) {
    if (statusStr == 'completed') {
      toolStatus = ToolStatus.completed;
    } else if (statusStr == 'failed') {
      toolStatus = ToolStatus.failed;
    }
    if (progress != null && progress.isNotEmpty) {
      toolProgress = (toolProgress ?? '') + progress;
    }
    // Merge content blocks from tool_call_update
    if (newContentBlocks != null && newContentBlocks.isNotEmpty) {
      contentBlocks = newContentBlocks;
    }
  }

  /// Create a file edit block, initializing the first [FileEditEntry].
  factory ContentBlock.fileEdit({
    required String path,
    String? oldContent,
    String? newContent,
    String? description,
  }) {
    final block = ContentBlock(
      type: BlockType.fileEdit,
      filePath: path,
      oldContent: oldContent,
      newContent: newContent,
      editDescription: description,
    );
    // Create the first entry if content is provided
    if (oldContent != null || newContent != null) {
      block.editEntries.add(FileEditEntry(
        oldContent: oldContent ?? '',
        newContent: newContent ?? '',
      ));
    }
    return block;
  }

  /// Create a plan block with a list of [PlanEntry] steps.
  factory ContentBlock.plan(List<PlanEntry> entries) => ContentBlock(
        type: BlockType.plan,
        planEntries: entries,
      );

  /// Create a code block with optional [language] hint.
  factory ContentBlock.code(String text, {String? language}) => ContentBlock(
        type: BlockType.code,
        text: text,
        language: language,
      );

  /// Create an interruption indicator block.
  ///
  /// Displayed as a subtle visual marker indicating the AI response
  /// was cut short due to connection loss or watchdog timeout.
  /// Distinct from error blocks (which indicate failures from the Agent).
  factory ContentBlock.interruption() =>
      ContentBlock(type: BlockType.interruption);
}

/// A single step within a plan block.
class PlanEntry {
  final String title;
  final String status; // pending / in_progress / completed
  final String priority;

  PlanEntry({required this.title, this.status = 'pending', this.priority = ''});
}
