class Conversation {
  const Conversation({
    required this.id,
    required this.buyerId,
    required this.sellerId,
    this.productId,
    required this.lastMessageAt,
    required this.lastMessageText,
    this.buyerHiddenAt,
    this.sellerHiddenAt,
  });

  final String id;
  final String? buyerId;
  final String? sellerId;
  final String? productId;
  final DateTime? lastMessageAt;
  final String? lastMessageText;
  final DateTime? buyerHiddenAt;
  final DateTime? sellerHiddenAt;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id']?.toString() ?? '',
      buyerId: json['buyer_id']?.toString(),
      sellerId: json['seller_id']?.toString(),
      productId: json['product_id']?.toString(),
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.tryParse(json['last_message_at'] as String)
          : null,
      lastMessageText: json['last_message_text']?.toString(),
      buyerHiddenAt: json['buyer_hidden_at'] != null
          ? DateTime.tryParse(json['buyer_hidden_at'] as String)
          : null,
      sellerHiddenAt: json['seller_hidden_at'] != null
          ? DateTime.tryParse(json['seller_hidden_at'] as String)
          : null,
    );
  }

  bool isHiddenForUser(String userId) {
    if (buyerId == userId) {
      return buyerHiddenAt != null;
    }
    if (sellerId == userId) {
      return sellerHiddenAt != null;
    }
    return false;
  }
}

class ConversationCursor {
  const ConversationCursor({required this.lastMessageAt, required this.id});

  final DateTime lastMessageAt;
  final String id;
}
