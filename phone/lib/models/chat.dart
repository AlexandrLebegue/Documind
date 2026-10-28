class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Conversation').toString(),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class ToolCallLog {
  const ToolCallLog({
    required this.tool,
    required this.args,
    required this.resultPreview,
  });

  final String tool;
  final Map<String, dynamic> args;
  final String resultPreview;

  factory ToolCallLog.fromJson(Map<String, dynamic> json) {
    return ToolCallLog(
      tool: (json['tool'] ?? '').toString(),
      args: (json['args'] as Map?)?.cast<String, dynamic>() ?? const {},
      resultPreview: (json['result_preview'] ?? '').toString(),
    );
  }
}

class SourceDocument {
  const SourceDocument({required this.id, required this.title, this.filename});

  final String id;
  final String title;
  final String? filename;

  factory SourceDocument.fromJson(Map<String, dynamic> json) {
    return SourceDocument(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? json['filename'] ?? 'Document').toString(),
      filename: json['filename']?.toString(),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.message,
    required this.createdAt,
    this.contextDocIds = const [],
    this.contextDocs = const [],
    this.toolCalls = const [],
    this.pending = false,
  });

  final String id;
  final String role;
  final String message;
  final DateTime createdAt;
  final List<String> contextDocIds;
  final List<SourceDocument> contextDocs;
  final List<ToolCallLog> toolCalls;
  final bool pending;

  bool get isUser => role == 'user';

  ChatMessage copyWith({
    String? message,
    bool? pending,
    List<ToolCallLog>? toolCalls,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      message: message ?? this.message,
      createdAt: createdAt,
      contextDocIds: contextDocIds,
      contextDocs: contextDocs,
      toolCalls: toolCalls ?? this.toolCalls,
      pending: pending ?? this.pending,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      role: (json['role'] ?? 'assistant').toString(),
      message: (json['message'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      contextDocIds: (json['context_doc_ids'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      contextDocs: (json['context_docs'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SourceDocument.fromJson)
          .toList(),
      toolCalls: (json['tool_calls'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ToolCallLog.fromJson)
          .toList(),
    );
  }
}

class ChatReply {
  const ChatReply({
    required this.reply,
    required this.sessionId,
    this.sourceDocumentIds = const [],
    this.sourceDocuments = const [],
    this.toolCalls = const [],
  });

  final String reply;
  final String sessionId;
  final List<String> sourceDocumentIds;
  final List<SourceDocument> sourceDocuments;
  final List<ToolCallLog> toolCalls;

  factory ChatReply.fromJson(Map<String, dynamic> json) {
    return ChatReply(
      reply: (json['reply'] ?? '').toString(),
      sessionId: (json['session_id'] ?? '').toString(),
      sourceDocumentIds: (json['source_document_ids'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      sourceDocuments: (json['source_documents'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SourceDocument.fromJson)
          .toList(),
      toolCalls: (json['tool_calls_log'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ToolCallLog.fromJson)
          .toList(),
    );
  }
}

sealed class AgentEvent {
  const AgentEvent();
}

class AgentSessionEvent extends AgentEvent {
  const AgentSessionEvent(this.sessionId);
  final String sessionId;
}

class AgentToolStart extends AgentEvent {
  const AgentToolStart(this.tool, this.args);
  final String tool;
  final Map<String, dynamic> args;
}

class AgentToolDone extends AgentEvent {
  const AgentToolDone(this.tool, this.args, this.resultPreview);
  final String tool;
  final Map<String, dynamic> args;
  final String resultPreview;
}

class AgentDone extends AgentEvent {
  const AgentDone(this.reply, this.sessionId, this.toolCalls);
  final String reply;
  final String sessionId;
  final List<ToolCallLog> toolCalls;
}

class AgentError extends AgentEvent {
  const AgentError(this.message);
  final String message;
}
