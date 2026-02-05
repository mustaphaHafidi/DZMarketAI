import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/test_env.dart';
import '../test/test_supabase.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Chat v2: hide stays hidden until restore', (tester) async {
    if (!(TestEnv.hasSupabaseCreds &&
        TestEnv.hasAuthCreds &&
        TestEnv.hasSellerAuthCreds)) {
      return;
    }

    await ensureSupabaseInitialized(
      url: TestEnv.supabaseUrl!,
      anonKey: TestEnv.supabaseAnonKey!,
    );

    final client = Supabase.instance.client;
    final repo = ChatRepository();

    // 1) Get seller id (login seller)
    await client.auth.signInWithPassword(
      email: TestEnv.testSellerEmail!,
      password: TestEnv.testSellerPassword!,
    );
    final sellerId = client.auth.currentUser!.id;
    await client.auth.signOut();

    // 2) Login buyer and create conversation
    await client.auth.signInWithPassword(
      email: TestEnv.testEmail!,
      password: TestEnv.testPassword!,
    );
    final buyerId = client.auth.currentUser!.id;

    final conversation = await repo.ensureConversation(
      productId: TestEnv.testProductId!,
      buyerId: buyerId,
      sellerId: sellerId,
    );
    final conversationId = conversation.id;

    // Initial message to set last_message_at
    final first = await repo.sendMessage(conversationId, 'hello initial');
    expect(first.conversationId, conversationId);

    // Delete conversation for buyer
    await repo.deleteConversation(conversationId);

    // Ensure hidden for buyer (not returned by get_conversations)
    final afterDelete = await client.rpc(
      'get_conversations',
      params: {'p_limit': 20},
    ) as List<dynamic>;
    final foundAfterDelete =
        afterDelete.any((row) => row['id'].toString() == conversationId);
    expect(foundAfterDelete, isFalse);

    // 3) Seller sends new message (should stay hidden for buyer)
    await client.auth.signOut();
    await client.auth.signInWithPassword(
      email: TestEnv.testSellerEmail!,
      password: TestEnv.testSellerPassword!,
    );
    await repo.sendMessage(conversationId, 'seller ping');

    // 4) Buyer logs back in: conversation should still be hidden
    await client.auth.signOut();
    await client.auth.signInWithPassword(
      email: TestEnv.testEmail!,
      password: TestEnv.testPassword!,
    );

    final refreshed = await client
        .rpc('get_conversations', params: {'p_limit': 20}) as List;
    final stillHidden =
        refreshed.any((row) => row['id'].toString() == conversationId);
    expect(stillHidden, isFalse);

    // 5) Restore and ensure it reappears
    await client.rpc('restore_conversation', params: {
      'p_conversation_id': conversationId,
    });
    final restored = await client
        .rpc('get_conversations', params: {'p_limit': 20}) as List;
    final foundRestored =
        restored.any((row) => row['id'].toString() == conversationId);
    expect(foundRestored, isTrue);

    await client.auth.signOut();
  });
}
