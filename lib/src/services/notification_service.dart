import 'dart:async';

import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;
  GlobalKey<ScaffoldMessengerState>? _messengerKey;
  final Map<String, bool> _orderAccessCache = {};

  void start(GlobalKey<ScaffoldMessengerState> messengerKey) {
    _messengerKey = messengerKey;
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      _subscribe();
    });
    _subscribe();
  }

  void _subscribe() {
    _channel?.unsubscribe();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _channel = Supabase.instance.client
        .channel('public:notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            _handleMessageInsert(payload, userId);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'offers',
          callback: (payload) {
            final newRow = payload.newRecord;
            final sellerId = newRow['seller_id'] as String?;
            if (sellerId != userId) return;
            final amount = newRow['amount']?.toString() ?? '';
            _showSnack('New offer', 'Offer: $amount');
          },
        )
        .subscribe();
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _channel?.unsubscribe();
  }

  void notifyLocal(String title, String body) => _showSnack(title, body);

  void _showSnack(String title, String body) {
    _messengerKey?.currentState?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(body),
          ],
        ),
      ),
    );
  }

  void _handleMessageInsert(PostgresChangePayload payload, String userId) {
    final newRow = payload.newRecord;
    final sender = newRow['sender_id'] as String?;
    if (sender == userId) return;
    final roomId = newRow['room_id'] as String?;
    if (roomId == null || roomId.isEmpty) return;
    final msgType = newRow['type']?.toString();
    final msgPayload = newRow['payload'];

    // Skip global room notifications to reduce noise unless explicitly needed.
    if (roomId == 'general') return;

    if (roomId.startsWith('product:')) {
      final parts = roomId.split(':');
      if (!parts.contains(userId)) return;
      final content = newRow['content'] as String? ?? 'New message';
      _showSnack('New message', content);
      return;
    }

    if (roomId.startsWith('order:')) {
      final parts = roomId.split(':');
      if (parts.length < 2) return;
      final orderId = parts[1];
      if (msgType == 'label') {
        final tracking = msgPayload is Map
            ? msgPayload['tracking_number']?.toString()
            : null;
        final body =
            tracking == null ? 'Bordereau disponible' : 'Bordereau $tracking';
        _handleOrderMessage(orderId, userId, body, title: 'Bordereau');
        return;
      }
      final content = newRow['content'] as String? ?? 'New message';
      _handleOrderMessage(orderId, userId, content);
      return;
    }
  }

  Future<void> _handleOrderMessage(
    String orderId,
    String userId,
    String content,
    {String title = 'New message'}
  ) async {
    final cached = _orderAccessCache[orderId];
    if (cached != null) {
      if (cached) _showSnack(title, content);
      return;
    }
    final allowed = await _hasOrderAccess(orderId, userId);
    _orderAccessCache[orderId] = allowed;
    if (allowed) _showSnack(title, content);
  }

  Future<bool> _hasOrderAccess(String orderId, String userId) async {
    try {
      final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
      final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
      final row = await RateLimiter.instance.run(
        'orders.access.check',
        () => Supabase.instance.client
            .from('orders')
            .select('id')
            .eq('id', safeOrderId)
            .or(
                'buyer_id.eq.$safeUserId,seller_id.eq.$safeUserId,driver_id.eq.$safeUserId')
            .maybeSingle(),
      );
      return row != null;
    } catch (_) {
      return false;
    }
  }
}
