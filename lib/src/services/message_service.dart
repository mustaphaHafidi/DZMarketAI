import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/message.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class MessageService {
  Future<String?> findExistingProductRoom({
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
          .or(
            'and(buyer_id.eq.$safeBuyerId,seller_id.eq.$safeSellerId),and(buyer_id.eq.$safeSellerId,seller_id.eq.$safeBuyerId)',
          )
          .limit(1)
          .maybeSingle(),
    );
    return row?['room_id']?.toString();
  }

  Stream<List<Message>> streamMessages(String roomId) {
    final safeRoomId = InputSanitizer.sanitizeId(roomId, maxLength: 120);
    return RateLimiter.instance.stream(
      'messages.stream',
      () => supabase
          .from(SupabaseTables.messages)
          .stream(primaryKey: ['id'])
          .eq('room_id', safeRoomId)
          .order('created_at')
          .map((rows) => rows.map(Message.fromJson).toList()),
    );
  }

  /// Stream latest messages grouped by room (last message per room).
  Stream<List<Message>> streamLatestPerRoom({int limit = 200}) {
    return RateLimiter.instance.stream(
      'messages.latest.stream',
      () => supabase
          .from(SupabaseTables.messages)
          .stream(primaryKey: ['id'])
          .order('created_at')
          .limit(limit)
          .map((rows) {
            final latest = <String, Message>{};
            for (final row in rows) {
              final msg = Message.fromJson(row);
              final existing = latest[msg.roomId];
              if (existing == null ||
                  (msg.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                      .isAfter(
                        existing.createdAt ??
                            DateTime.fromMillisecondsSinceEpoch(0),
                      )) {
                latest[msg.roomId] = msg;
              }
            }
            final list = latest.values.toList()
              ..sort(
                (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
                  a.createdAt ?? DateTime.now(),
                ),
              );
            return list;
          }),
    );
  }

  Future<void> sendMessage({
    required String roomId,
    required String content,
    MessageType type = MessageType.text,
    Map<String, dynamic>? payload,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('User must be signed in to chat.');
    final safeRoomId = InputSanitizer.sanitizeId(roomId, maxLength: 120);
    final safeContent = type == MessageType.image
        ? InputSanitizer.sanitizeUrl(content, maxLength: 400)
        : InputSanitizer.sanitizeText(
            content,
            maxLength: 800,
            allowNewlines: true,
          );
    if (safeContent == null || safeContent.isEmpty) {
      throw FormatException('Message required.');
    }
    final safePayload = _sanitizePayload(payload);

    await RateLimiter.instance.run(
      'messages.insert',
      () => supabase.from(SupabaseTables.messages).insert({
        'room_id': safeRoomId,
        'content': safeContent,
        'sender_id': userId,
        'type': switch (type) {
          MessageType.label => 'label',
          MessageType.image => 'image',
          _ => 'text',
        },
        'payload': safePayload,
      }),
    );
  }

  /// Legacy no-op.
  ///
  /// Conversations can exist without an automatic hello message.
  /// Auto-seeding "Nouveau contact" created noisy chat entries and confused
  /// offer/order threads that already share the same buyer/seller/product room.
  Future<void> ensureRoomWithHello(String roomId) async {
    return;
  }

  Future<void> markRead(String roomId) async {
    final safeRoomId = InputSanitizer.sanitizeId(roomId, maxLength: 120);
    await RateLimiter.instance.run(
      'chat_rooms.read',
      () => supabase.rpc(
        'mark_chat_room_read',
        params: {'p_room_id': safeRoomId},
      ),
    );
  }

  Map<String, dynamic>? _sanitizePayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final sanitized = <String, dynamic>{};
    payload.forEach((key, value) {
      if (value is String) {
        if (key.contains('url')) {
          final safeUrl = InputSanitizer.sanitizeUrl(value, maxLength: 400);
          if (safeUrl != null) {
            sanitized[key] = safeUrl;
          }
          return;
        }
        sanitized[key] = InputSanitizer.sanitizeText(value, maxLength: 200);
        return;
      }
      sanitized[key] = value;
    });
    return sanitized;
  }
}
