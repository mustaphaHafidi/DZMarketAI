enum MessageType { text, image, label }

class Message {
  const Message({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.type,
    this.payload,
    this.createdAt,
    this.readBy = const [],
  });

  final String id;
  final String roomId;
  final String senderId;
  final String content;
  final MessageType type;
  final Map<String, dynamic>? payload;
  final DateTime? createdAt;
  final List<String> readBy;

  factory Message.fromJson(Map<String, dynamic> json) {
    final typeString = (json['type'] as String?) ?? 'text';
    final type = switch (typeString) {
      'image' => MessageType.image,
      'label' => MessageType.label,
      _ => MessageType.text,
    };
    return Message(
      id: json['id']?.toString() ?? '',
      roomId: json['room_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      type: type,
      payload: (json['payload'] as Map?)?.cast<String, dynamic>(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      readBy: ((json['read_by'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  bool get isImage =>
      (payload != null && payload?['type'] == 'image') ||
      type == MessageType.image;
}
