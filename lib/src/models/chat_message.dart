import 'package:dzmarket/src/utils/text_encoding_utils.dart';

enum ChatMessageType { text, system, label }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.type,
    this.payload,
    this.moderationStatus,
    this.createdAt,
    this.deletedAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final ChatMessageType type;
  final Map<String, dynamic>? payload;
  final String? moderationStatus;
  final DateTime? createdAt;
  final DateTime? deletedAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final typeString = (json['type'] as String?) ?? 'text';
    final payload = (json['payload'] as Map?)?.cast<String, dynamic>();
    final inferredSystem =
        payload != null &&
        (payload.containsKey('status') ||
            payload.containsKey('tracking_number') ||
            payload.containsKey('label_url') ||
            payload.containsKey('i18n_key'));
    final type = switch (typeString) {
      'system' => ChatMessageType.system,
      'label' => ChatMessageType.label,
      _ => inferredSystem ? ChatMessageType.system : ChatMessageType.text,
    };
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      text: repairMojibake(json['text']?.toString()),
      type: type,
      payload: payload,
      moderationStatus: json['moderation_status']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      deletedAt: json['deleted_at'] != null
          ? DateTime.tryParse(json['deleted_at'] as String)
          : null,
    );
  }

  bool get isSystem => type == ChatMessageType.system;
  bool get isLabel => type == ChatMessageType.label;
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
