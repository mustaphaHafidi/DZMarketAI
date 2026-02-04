import 'dart:async';

import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/chat_message.dart';
import 'package:dzmarket/src/models/conversation.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal chat repository for the Vinted-like conversation rules.
class ChatRepository {
  ChatRepository();

  final SupabaseClient _client = supabase;

  /// Stream visible conversations sorted client-side by last_message_at desc.
  Stream<List<Conversation>> watchConversations({
    int limit = 100,
    ConversationCursor? cursor,
  }) {
    var query = _client
        .from(SupabaseTables.conversations)
        .stream(primaryKey: ['id'])
        .limit(limit);

    // Sort client-side to avoid heavy ORDER BY on the server (prevents timeouts).
    return query.map((rows) {
      final list = rows.map(Conversation.fromJson).toList();
      list.sort((a, b) {
        final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return list;
    });
  }

  /// Stream messages for a conversation, newest last.
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _client
        .from(SupabaseTables.messages)
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map((rows) => rows
            .map(ChatMessage.fromJson)
            .where((m) => m.deletedAt == null)
            .toList());
  }

  Future<ChatMessage> sendMessage(String conversationId, String text) async {
    final result = await _client.rpc(
      'send_message',
      params: {
        'p_conversation_id': conversationId,
        'p_text': text,
      },
    );
    if (result == null) {
      throw StateError('send_message returned null');
    }
    return ChatMessage.fromJson(result as Map<String, dynamic>);
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
        .map((rows) => {
              for (final row in rows)
                row['conversation_id'].toString():
                    ReadState.fromJson(row as Map<String, dynamic>)
            });
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
