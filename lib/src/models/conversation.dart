class Conversation {
  const Conversation({
    required this.id,
    required this.buyerId,
    required this.sellerId,
    this.productId,
    this.orderId,
    required this.lastMessageAt,
    required this.lastMessageText,
    this.buyerHiddenAt,
    this.sellerHiddenAt,
    this.unreadByBuyer = 0,
    this.unreadBySeller = 0,
    this.hasUnreadCounters = false,
  });

  final String id;
  final String? buyerId;
  final String? sellerId;
  final String? productId;
  final String? orderId;
  final DateTime? lastMessageAt;
  final String? lastMessageText;
  final DateTime? buyerHiddenAt;
  final DateTime? sellerHiddenAt;
  final int unreadByBuyer;
  final int unreadBySeller;
  final bool hasUnreadCounters;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final hasUnreadByBuyer = json.containsKey('unread_by_buyer');
    final hasUnreadBySeller = json.containsKey('unread_by_seller');
    return Conversation(
      id: json['id']?.toString() ?? '',
      buyerId: json['buyer_id']?.toString(),
      sellerId: json['seller_id']?.toString(),
      productId: json['product_id']?.toString(),
      orderId: json['order_id']?.toString(),
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
      unreadByBuyer: (json['unread_by_buyer'] as num?)?.toInt() ?? 0,
      unreadBySeller: (json['unread_by_seller'] as num?)?.toInt() ?? 0,
      hasUnreadCounters: hasUnreadByBuyer || hasUnreadBySeller,
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

  int unreadCountForUser(String userId) {
    if (buyerId == userId) {
      return unreadByBuyer < 0 ? 0 : unreadByBuyer;
    }
    if (sellerId == userId) {
      return unreadBySeller < 0 ? 0 : unreadBySeller;
    }
    return 0;
  }
}

class ConversationCursor {
  const ConversationCursor({required this.lastMessageAt, required this.id});

  final DateTime lastMessageAt;
  final String id;
}
