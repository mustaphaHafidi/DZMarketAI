import 'dart:async';

import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/chat_message.dart';
import 'package:dzmarket/src/models/conversation.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/moderation_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal chat repository for the Vinted-like conversation rules.
class ChatRepository {
  ChatRepository();

  final SupabaseClient _client = supabase;

  /// Stream visible conversations sorted client-side by last_message_at desc.
  Stream<List<Conversation>> watchConversations({
    int limit = 30,
    ConversationCursor? cursor,
  }) {
    final fetchLimit = (limit * 4).clamp(60, 200);
    var query = _client
        .from(SupabaseTables.conversations)
        .stream(primaryKey: ['id'])
        .order('last_message_at', ascending: false)
        .order('id', ascending: false)
        .limit(fetchLimit);

    // Sort + dedupe client-side to avoid heavy ORDER BY on the server
    // and to collapse legacy duplicate rooms for the same thread.
    return query.map((rows) {
      final list = rows.map(Conversation.fromJson).toList();
      list.sort((a, b) {
        final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      final deduped = _dedupeThreads(list);
      return deduped.take(limit).toList();
    });
  }

  List<Conversation> _dedupeThreads(List<Conversation> sorted) {
    final userId = _client.auth.currentUser?.id;
    final byKey = <String, Conversation>{};
    for (final conversation in sorted) {
      final key = _threadKey(conversation);
      final current = byKey[key];
      if (current == null ||
          _isPreferredConversation(
            candidate: conversation,
            current: current,
            userId: userId,
          )) {
        byKey[key] = conversation;
      }
    }
    final deduped = byKey.values.toList();
    deduped.sort((a, b) {
      final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return deduped;
  }

  String _threadKey(Conversation conversation) {
    final productId = conversation.productId ?? '';
    final buyerId = conversation.buyerId ?? '';
    final sellerId = conversation.sellerId ?? '';
    if (productId.isNotEmpty && buyerId.isNotEmpty && sellerId.isNotEmpty) {
      return 'p:$productId|b:$buyerId|s:$sellerId';
    }
    final orderId = conversation.orderId ?? '';
    if (orderId.isNotEmpty) {
      return 'o:$orderId';
    }
    return 'c:${conversation.id}';
  }

  bool _isPreferredConversation({
    required Conversation candidate,
    required Conversation current,
    required String? userId,
  }) {
    if (userId != null) {
      final candidateHidden = candidate.isHiddenForUser(userId);
      final currentHidden = current.isHiddenForUser(userId);
      if (candidateHidden != currentHidden) {
        return !candidateHidden;
      }
    }
    final candidateAt =
        candidate.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final currentAt =
        current.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return candidateAt.isAfter(currentAt);
  }

  /// Stream messages for a conversation, newest last.
  Stream<List<ChatMessage>> watchMessages(
    String conversationId, {
    int limit = 30,
  }) {
    return _client
        .from(SupabaseTables.messages)
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) {
          final list = rows
              .map(ChatMessage.fromJson)
              .where(
                (m) => m.deletedAt == null && m.moderationStatus != 'blocked',
              )
              .toList();
          list.sort((a, b) {
            final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return at.compareTo(bt);
          });
          return list;
        });
  }

  Future<ChatMessage> sendMessage(
    String conversationId,
    String text, {
    String type = 'text',
    Map<String, dynamic>? payload,
    String? dedupeKey,
  }) async {
    if (type == 'text' && text.trim().isNotEmpty) {
      final moderation = await ModerationService().moderateText(text);
      if (!moderation.allowed) {
        final locale =
            LocaleService.instance.locale.value?.languageCode ?? 'fr';
        throw FormatException(
          L10n.trLocale(locale, 'moderation.blocked_message'),
        );
      }
    }
    try {
      final result = await _client.rpc(
        'send_message',
        params: {
          'p_conversation_id': conversationId,
          'p_text': text,
          if (type.isNotEmpty) 'p_type': type,
          if (payload != null) 'p_payload': payload,
          if (dedupeKey != null) 'p_dedupe_key': dedupeKey,
        },
      );
      if (result == null) {
        throw StateError('send_message returned null');
      }
      return ChatMessage.fromJson(result as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      final missingNewArgs =
          e.code == 'PGRST202' ||
          e.code == '42883' ||
          e.message.contains('send_message') &&
              (e.message.contains('p_type') ||
                  e.message.contains('p_payload') ||
                  e.message.contains('p_dedupe_key'));
      if (!missingNewArgs) rethrow;
      final result = await _client.rpc(
        'send_message',
        params: {'p_conversation_id': conversationId, 'p_text': text},
      );
      if (result == null) {
        throw StateError('send_message returned null');
      }
      return ChatMessage.fromJson(result as Map<String, dynamic>);
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    await _client.rpc(
      'delete_conversation',
      params: {'p_conversation_id': conversationId},
    );
  }

  Future<void> restoreConversation(String conversationId) async {
    await _client.rpc(
      'restore_conversation',
      params: {'p_conversation_id': conversationId},
    );
  }

  Future<void> markRead(String conversationId, String lastMessageId) async {
    await _client.rpc(
      'mark_read',
      params: {
        'p_conversation_id': conversationId,
        'p_last_message_id': lastMessageId,
      },
    );
  }

  /// Ensure a conversation exists for a product/buyer/seller trio.
  Future<Conversation> ensureConversation({
    required String productId,
    required String buyerId,
    required String sellerId,
  }) async {
    final result = await _client.rpc(
      'ensure_conversation',
      params: {
        'p_product_id': productId,
        'p_buyer_id': buyerId,
        'p_seller_id': sellerId,
      },
    );
    if (result == null) {
      throw StateError('ensure_conversation returned null');
    }
    return Conversation.fromJson(result as Map<String, dynamic>);
  }

  /// Ensure a conversation exists for a given order.
  Future<Conversation> ensureOrderConversation(String orderId) async {
    try {
      final result = await _client.rpc(
        'ensure_order_conversation',
        params: {'p_order_id': orderId},
      );
      if (result == null) {
        throw StateError('ensure_order_conversation returned null');
      }
      return Conversation.fromJson(result as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      final missingFn =
          e.code == 'PGRST202' ||
          e.code == '42883' ||
          e.message.contains('ensure_order_conversation');
      if (!missingFn) rethrow;
      final orderRow = await _client
          .from(SupabaseTables.orders)
          .select('product_id,buyer_id,seller_id')
          .eq('id', orderId)
          .maybeSingle();
      if (orderRow == null) {
        throw StateError('Order not found');
      }
      final productId = orderRow['product_id']?.toString() ?? '';
      final buyerId = orderRow['buyer_id']?.toString() ?? '';
      final sellerId = orderRow['seller_id']?.toString() ?? '';
      if (productId.isEmpty || buyerId.isEmpty || sellerId.isEmpty) {
        throw StateError('Order missing participants');
      }
      return ensureConversation(
        productId: productId,
        buyerId: buyerId,
        sellerId: sellerId,
      );
    }
  }

  Future<void> postOrderSystemMessage({
    required String orderId,
    required String text,
    Map<String, dynamic>? payload,
    String? dedupeKey,
  }) async {
    final conv = await ensureOrderConversation(orderId);
    final payloadWithText = <String, dynamic>{
      if (payload != null) ...payload,
      if ((payload?['text'] as String?)?.isNotEmpty != true) 'text': text,
    };

    if (dedupeKey != null && dedupeKey.isNotEmpty) {
      try {
        final existing = await _client
            .from(SupabaseTables.messages)
            .select('id')
            .eq('conversation_id', conv.id)
            .eq('dedupe_key', dedupeKey)
            .maybeSingle();
        if (existing != null) return;
      } catch (_) {
        // Ignore lookup errors; best-effort only.
      }
    }

    try {
      await _client.rpc(
        'post_order_event',
        params: {
          'p_order_id': orderId,
          'p_event': 'client_event',
          'p_payload': payloadWithText,
          'p_dedupe_key': dedupeKey ?? '',
        },
      );
      return;
    } on PostgrestException catch (e) {
      final missingFn =
          e.code == 'PGRST202' ||
          e.code == '42883' ||
          e.message.contains('post_order_event');
      if (!missingFn) {
        // RPC exists but failed; fall back to send_message with dedupe.
      }
    } catch (_) {
      // Ignore and fall back.
    }

    try {
      await sendMessage(
        conv.id,
        text,
        type: 'system',
        payload: payloadWithText,
        dedupeKey: dedupeKey,
      );
      return;
    } on PostgrestException catch (e) {
      final missingUnique =
          e.code == '42P10' ||
          e.message.contains('no unique or exclusion constraint');
      if (!missingUnique && dedupeKey != null && dedupeKey.isNotEmpty) {
        return;
      }
    } catch (_) {
      // If we have a dedupe key, avoid inserting duplicates without it.
      if (dedupeKey != null && dedupeKey.isNotEmpty) return;
    }

    final senderId = _client.auth.currentUser?.id;
    if (senderId == null) return;

    try {
      await _client.from(SupabaseTables.messages).insert({
        'conversation_id': conv.id,
        'sender_id': senderId,
        'text': text,
        'type': 'system',
        if (payloadWithText.isNotEmpty) 'payload': payloadWithText,
      });
    } catch (_) {
      // Best-effort: do not block.
    }

    try {
      await _client
          .from(SupabaseTables.conversations)
          .update({
            'last_message_at': DateTime.now().toIso8601String(),
            'last_message_text': text,
          })
          .eq('id', conv.id);
    } catch (_) {}
  }

  /// Stream read states for the current user; can be combined client-side.
  Stream<Map<String, ReadState>> watchReadStates() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream.empty();
    }
    return _client
        .from(SupabaseTables.reads)
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('user_id', userId)
        .order('last_read_at', ascending: false)
        .limit(200)
        .map(
          (rows) => {
            for (final row in rows)
              row['conversation_id'].toString(): ReadState.fromJson(row),
          },
        );
  }
}

/// Example usage (pseudo-widget):
///
/// final repo = ChatRepository();
/// final convStream = repo.watchConversations();
/// final readsStream = repo.watchReadStates();
/// StreamBuilder(
///   stream: Rx.combineLatest2(convStream, readsStream, (convs, reads) {
///     return convs.map((c) {
///       final read = reads[c.id];
///       final unread = read == null ||
///           (c.lastMessageAt != null &&
///               (read.lastReadAt == null ||
///                   c.lastMessageAt!.isAfter(read.lastReadAt!)));
///       return (c, unread);
///     }).toList();
///   }),
///   builder: ...
/// );
