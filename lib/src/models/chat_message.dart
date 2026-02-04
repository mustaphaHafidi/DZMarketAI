class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    this.createdAt,
    this.deletedAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime? createdAt;
  final DateTime? deletedAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      deletedAt: json['deleted_at'] != null
          ? DateTime.tryParse(json['deleted_at'] as String)
          : null,
    );
  }
}

class ReadState {
  const ReadState({
    required this.conversationId,
    required this.userId,
    this.lastReadAt,
    this.lastReadMessageId,
  });

  final String conversationId;
  final String userId;
  final DateTime? lastReadAt;
  final String? lastReadMessageId;

  factory ReadState.fromJson(Map<String, dynamic> json) {
    return ReadState(
      conversationId: json['conversation_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      lastReadAt: json['last_read_at'] != null
          ? DateTime.tryParse(json['last_read_at'] as String)
          : null,
      lastReadMessageId: json['last_read_message_id']?.toString(),
    );
  }
}
