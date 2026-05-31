// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/chat.py

/// Payload for ``chat.send`` — user sends a message to the AI.
class ChatSendPayload {
  final String cli;
  final String message;
  final Map<String, dynamic>? context;
  final String? sessionId;
  final List<Map<String, dynamic>>? attachments;
  final List<Map<String, dynamic>>? contextReferences;

  const ChatSendPayload({
    required this.cli,
    required this.message,
    this.context = null,
    this.sessionId = null,
    this.attachments = null,
    this.contextReferences = null,
  });

  factory ChatSendPayload.fromJson(Map<String, dynamic> json) {
    return ChatSendPayload(
      cli: json['cli'] as String? ?? '',
      message: json['message'] as String? ?? '',
      context: json['context'] != null ? Map<String, dynamic>.from(json['context'] as Map) : null,
      sessionId: json['session_id'] as String?,
      attachments: (json['attachments'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      contextReferences: (json['context_references'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'message': message,
        'context': context,
        'session_id': sessionId,
        'attachments': attachments,
        'context_references': contextReferences,
      };
}

/// Payload for ``chat.stream`` — one streaming chunk from the AI.
class ChatStreamPayload {
  final Map<String, dynamic> chunk;

  const ChatStreamPayload({
    required this.chunk,
  });

  factory ChatStreamPayload.fromJson(Map<String, dynamic> json) {
    return ChatStreamPayload(
      chunk: Map<String, dynamic>.from(json['chunk'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'chunk': chunk,
      };
}

/// Payload for ``chat.done`` — AI turn completed.
class ChatDonePayload {
  final bool? cancelled;
  final int? tokensUsed;
  final int? durationMs;
  final String? sessionId;

  const ChatDonePayload({
    this.cancelled = null,
    this.tokensUsed = null,
    this.durationMs = null,
    this.sessionId = null,
  });

  factory ChatDonePayload.fromJson(Map<String, dynamic> json) {
    return ChatDonePayload(
      cancelled: json['cancelled'] as bool?,
      tokensUsed: json['tokens_used'] as int?,
      durationMs: json['duration_ms'] as int?,
      sessionId: json['session_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'cancelled': cancelled,
        'tokens_used': tokensUsed,
        'duration_ms': durationMs,
        'session_id': sessionId,
      };
}

/// Payload for ``chat.error`` — prompt-level error.
class ChatErrorPayload {
  final String error;

  const ChatErrorPayload({
    required this.error,
  });

  factory ChatErrorPayload.fromJson(Map<String, dynamic> json) {
    return ChatErrorPayload(
      error: json['error'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'error': error,
      };
}

/// Payload for ``chat.cancel`` — cancel the current AI operation.
class ChatCancelPayload {
  final String cli;

  const ChatCancelPayload({
    this.cli = '',
  });

  factory ChatCancelPayload.fromJson(Map<String, dynamic> json) {
    return ChatCancelPayload(
      cli: json['cli'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
      };
}

/// Payload for ``chat.history`` — request conversation history.
class ChatHistoryPayload {
  final String cli;
  final String? sessionId;

  const ChatHistoryPayload({
    required this.cli,
    this.sessionId = null,
  });

  factory ChatHistoryPayload.fromJson(Map<String, dynamic> json) {
    return ChatHistoryPayload(
      cli: json['cli'] as String? ?? '',
      sessionId: json['session_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'session_id': sessionId,
      };
}

/// Payload for ``chat.history.result`` — history page response.
class ChatHistoryResultPayload {
  final List<Map<String, dynamic>> messages;
  final int total;
  final bool hasMore;
  final String cli;
  final bool resumed;

  const ChatHistoryResultPayload({
    this.messages = const [],
    this.total = 0,
    this.hasMore = false,
    this.cli = '',
    this.resumed = false,
  });

  factory ChatHistoryResultPayload.fromJson(Map<String, dynamic> json) {
    return ChatHistoryResultPayload(
      messages: (json['messages'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      total: json['total'] as int? ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
      cli: json['cli'] as String? ?? '',
      resumed: json['resumed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'messages': messages,
        'total': total,
        'has_more': hasMore,
        'cli': cli,
        'resumed': resumed,
      };
}

/// Payload for ``chat.history.more`` — request next page of history.
class ChatHistoryMorePayload {
  final String cli;
  final int offset;
  final int limit;

  const ChatHistoryMorePayload({
    required this.cli,
    this.offset = 0,
    this.limit = 20,
  });

  factory ChatHistoryMorePayload.fromJson(Map<String, dynamic> json) {
    return ChatHistoryMorePayload(
      cli: json['cli'] as String? ?? '',
      offset: json['offset'] as int? ?? 0,
      limit: json['limit'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'offset': offset,
        'limit': limit,
      };
}

/// Payload for ``chat.history.more.result`` — next page response.
class ChatHistoryMoreResultPayload {
  final List<Map<String, dynamic>> messages;
  final int total;
  final bool hasMore;
  final String cli;

  const ChatHistoryMoreResultPayload({
    this.messages = const [],
    this.total = 0,
    this.hasMore = false,
    this.cli = '',
  });

  factory ChatHistoryMoreResultPayload.fromJson(Map<String, dynamic> json) {
    return ChatHistoryMoreResultPayload(
      messages: (json['messages'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      total: json['total'] as int? ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
      cli: json['cli'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'messages': messages,
        'total': total,
        'has_more': hasMore,
        'cli': cli,
      };
}

/// Payload for ``chat.replay`` — request buffered stream chunks.
class ChatReplayPayload {
  final int afterSeq;

  const ChatReplayPayload({
    this.afterSeq = 0,
  });

  factory ChatReplayPayload.fromJson(Map<String, dynamic> json) {
    return ChatReplayPayload(
      afterSeq: json['after_seq'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'after_seq': afterSeq,
      };
}

/// Payload for ``chat.replay.result`` — replayed chunks batch.
class ChatReplayResultPayload {
  final List<Map<String, dynamic>> chunks;
  final bool streaming;
  final int seq;
  final String? streamingState;

  const ChatReplayResultPayload({
    this.chunks = const [],
    this.streaming = false,
    this.seq = 0,
    this.streamingState = null,
  });

  factory ChatReplayResultPayload.fromJson(Map<String, dynamic> json) {
    return ChatReplayResultPayload(
      chunks: (json['chunks'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      streaming: json['streaming'] as bool? ?? false,
      seq: json['seq'] as int? ?? 0,
      streamingState: json['streaming_state'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'chunks': chunks,
        'streaming': streaming,
        'seq': seq,
        'streaming_state': streamingState,
      };
}
