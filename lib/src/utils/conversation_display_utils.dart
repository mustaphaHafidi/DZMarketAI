import 'package:dzmarket/src/models/chat_message.dart';
import 'package:dzmarket/src/models/conversation.dart';

bool hasDisplayableConversationMessage(Conversation conversation) {
  final text = conversation.lastMessageText?.trim() ?? '';
  return conversation.lastMessageAt != null && text.isNotEmpty;
}

int fallbackConversationUnreadCount({
  required Conversation conversation,
  required ReadState? readState,
}) {
  if (!hasDisplayableConversationMessage(conversation)) {
    return 0;
  }
  final readAt = readState?.lastReadAt;
  if (readAt == null) {
    return 1;
  }
  return conversation.lastMessageAt!.isAfter(readAt) ? 1 : 0;
}

String conversationPreviewText(Conversation conversation) {
  return conversation.lastMessageText?.trim() ?? '';
}
