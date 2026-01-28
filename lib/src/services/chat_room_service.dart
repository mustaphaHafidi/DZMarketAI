import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class ChatRoomSummary {
  const ChatRoomSummary({
    required this.roomId,
    required this.productId,
    required this.buyerId,
    required this.sellerId,
    required this.lastMessage,
    required this.lastMessageType,
    required this.lastMessageAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.lastSenderId,
    required this.unreadByBuyer,
    required this.unreadBySeller,
    required this.hiddenBy,
    required this.deletedByBuyer,
    required this.deletedBySeller,
  });

  final String roomId;
  final String? productId;
  final String buyerId;
  final String sellerId;
  final String? lastMessage;
  final String? lastMessageType;
  final DateTime? lastMessageAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final String? lastSenderId;
  final int unreadByBuyer;
  final int unreadBySeller;
  final List<String> hiddenBy;
  final bool deletedByBuyer;
  final bool deletedBySeller;

  factory ChatRoomSummary.fromJson(Map<String, dynamic> json) {
    final hiddenRaw = json['hidden_by'];
    final hiddenList = hiddenRaw is List
        ? hiddenRaw.map((e) => e.toString()).toList()
        : <String>[];
    return ChatRoomSummary(
      roomId: json['room_id']?.toString() ?? '',
      productId: json['product_id']?.toString(),
      buyerId: json['buyer_id']?.toString() ?? '',
      sellerId: json['seller_id']?.toString() ?? '',
      lastMessage: json['last_message']?.toString(),
      lastMessageType: json['last_message_type']?.toString(),
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.tryParse(json['last_message_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      deletedAt: json['deleted_at'] != null
          ? DateTime.tryParse(json['deleted_at'] as String)
          : null,
      lastSenderId: json['last_sender_id']?.toString(),
      unreadByBuyer: (json['unread_by_buyer'] as num?)?.toInt() ?? 0,
      unreadBySeller: (json['unread_by_seller'] as num?)?.toInt() ?? 0,
      hiddenBy: hiddenList,
      deletedByBuyer: json['deleted_by_buyer'] as bool? ?? false,
      deletedBySeller: json['deleted_by_seller'] as bool? ?? false,
    );
  }
}

class ChatRoomService {
  Stream<List<ChatRoomSummary>> streamRoomsForUser(String userId) {
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
    return RateLimiter.instance.stream(
      'chat_rooms.stream',
      () => supabase
          .from('chat_rooms_visible')
          .stream(primaryKey: ['room_id', 'user_id'])
          .eq('user_id', safeUserId)
          .order('last_message_at', ascending: false)
          .order('updated_at', ascending: false)
          .map((rows) => rows
              .map(ChatRoomSummary.fromJson)
              .where((room) => room.deletedAt == null)
              .toList()),
    );
  }

  Future<String?> findExistingRoom({
    required String productId,
    required String buyerId,
    required String sellerId,
  }) async {
    final safeProductId = InputSanitizer.sanitizeId(productId, maxLength: 64);
    final safeBuyerId = InputSanitizer.sanitizeId(buyerId, maxLength: 64);
    final safeSellerId = InputSanitizer.sanitizeId(sellerId, maxLength: 64);
    final row = await RateLimiter.instance.run(
      'chat_rooms.find',
      () => supabase
          .from(SupabaseTables.chatRooms)
          .select('room_id,buyer_id,seller_id')
          .eq('product_id', safeProductId)
          .or('and(buyer_id.eq.$safeBuyerId,seller_id.eq.$safeSellerId),and(buyer_id.eq.$safeSellerId,seller_id.eq.$safeBuyerId)')
          .limit(1)
          .maybeSingle(),
    );
    return row?['room_id']?.toString();
  }

  Future<void> ensureRoom({
    required String roomId,
    required String productId,
    required String buyerId,
    required String sellerId,
  }) async {
    final safeRoomId = InputSanitizer.sanitizeId(roomId, maxLength: 80);
    final safeProductId = InputSanitizer.sanitizeId(productId, maxLength: 64);
    final safeBuyerId = InputSanitizer.sanitizeId(buyerId, maxLength: 64);
    final safeSellerId = InputSanitizer.sanitizeId(sellerId, maxLength: 64);
    await RateLimiter.instance.run(
      'chat_rooms.upsert',
      () => supabase.from(SupabaseTables.chatRooms).upsert({
        'room_id': safeRoomId,
        'product_id': safeProductId,
        'buyer_id': safeBuyerId,
        'seller_id': safeSellerId,
      }),
    );
  }

  Future<void> hideRoom(String roomId) async {
    final safeRoomId = InputSanitizer.sanitizeId(roomId, maxLength: 80);
    await RateLimiter.instance.run(
      'chat_rooms.hide',
      () => supabase.rpc('hide_chat_room', params: {'p_room_id': safeRoomId}),
    );
  }
}
