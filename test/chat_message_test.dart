import 'package:dzmarket/src/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChatMessage repairs mojibake text from legacy rows', () {
    final message = ChatMessage.fromJson({
      'id': 1,
      'conversation_id': 2,
      'sender_id': 'seller',
      'text': 'RefusÃ©e',
      'type': 'system',
    });

    expect(message.text, 'Refusée');
  });
}
