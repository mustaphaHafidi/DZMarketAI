import 'package:dzmarket/src/models/chat_message.dart';
import 'package:dzmarket/src/models/conversation.dart';
import 'package:dzmarket/src/utils/conversation_display_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Conversation buildConversation({
    String? lastMessageText,
    DateTime? lastMessageAt,
  }) {
    return Conversation(
      id: 'conv-1',
      buyerId: 'buyer',
      sellerId: 'seller',
      productId: 'product-1',
      orderId: null,
      lastMessageAt: lastMessageAt,
      lastMessageText: lastMessageText,
    );
  }

  test('empty placeholder conversation is not treated as unread activity', () {
    final conversation = buildConversation(
      lastMessageAt: DateTime.parse('2026-08-07T10:00:00Z'),
      lastMessageText: null,
    );

    expect(hasDisplayableConversationMessage(conversation), isFalse);
    expect(
      fallbackConversationUnreadCount(
        conversation: conversation,
        readState: null,
      ),
      0,
    );
    expect(conversationPreviewText(conversation), isEmpty);
  });

  test('real last message still produces unread fallback and preview text', () {
    final conversation = buildConversation(
      lastMessageAt: DateTime.parse('2026-08-07T10:00:00Z'),
      lastMessageText: 'Bonjour',
    );

    expect(hasDisplayableConversationMessage(conversation), isTrue);
    expect(
      fallbackConversationUnreadCount(
        conversation: conversation,
        readState: null,
      ),
      1,
    );
    expect(conversationPreviewText(conversation), 'Bonjour');
    expect(
      fallbackConversationUnreadCount(
        conversation: conversation,
        readState: const ReadState(
          conversationId: 'conv-1',
          userId: 'buyer',
          lastReadAt: null,
          lastReadMessageId: null,
        ),
      ),
      1,
    );
  });
}
