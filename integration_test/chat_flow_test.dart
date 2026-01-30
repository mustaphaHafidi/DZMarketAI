import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/chat_room_service.dart';
import 'package:dzmarket/src/services/message_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/test_env.dart';
import '../test/test_supabase.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Chat: unique room + hide/unhide per user', (tester) async {
    if (!TestEnv.hasAuthCreds || !TestEnv.hasChatFixtures) {
      return;
    }
    await ensureSupabaseInitialized(
      url: TestEnv.supabaseUrl!,
      anonKey: TestEnv.supabaseAnonKey!,
    );

    await AuthService.instance
        .signIn(
          TestEnv.testEmail!,
          TestEnv.testPassword!,
        )
        .timeout(const Duration(seconds: 20));

    final roomId = TestEnv.testRoomId!;
    final productId = TestEnv.testProductId!;
    final buyerId = TestEnv.testBuyerId!;
    final sellerId = TestEnv.testSellerId!;

    await ChatRoomService()
        .ensureRoom(
          roomId: roomId,
          productId: productId,
          buyerId: buyerId,
          sellerId: sellerId,
        )
        .timeout(const Duration(seconds: 10));
    await ChatRoomService()
        .ensureRoom(
          roomId: roomId,
          productId: productId,
          buyerId: buyerId,
          sellerId: sellerId,
        )
        .timeout(const Duration(seconds: 10));

    await ChatRoomService()
        .hideRoom(roomId)
        .timeout(const Duration(seconds: 10));
    final hidden = await Supabase.instance.client
        .from('chat_room_users')
        .select('deleted_at')
        .eq('room_id', roomId)
        .eq('user_id', Supabase.instance.client.auth.currentUser?.id ?? '')
        .maybeSingle();
    expect(hidden?['deleted_at'], isNotNull);

    await MessageService()
        .sendMessage(
          roomId: roomId,
          content: 'Ping',
        )
        .timeout(const Duration(seconds: 10));
    final unhidden = await Supabase.instance.client
        .from('chat_room_users')
        .select('deleted_at')
        .eq('room_id', roomId)
        .eq('user_id', Supabase.instance.client.auth.currentUser?.id ?? '')
        .maybeSingle();
    expect(unhidden?['deleted_at'], isNull);

    await AuthService.instance.signOut().timeout(const Duration(seconds: 10));
  }, skip: !TestEnv.hasAuthCreds || !TestEnv.hasChatFixtures);

  testWidgets('Chat: rooms sorted by last message', (tester) async {
    if (!TestEnv.hasAuthCreds || !TestEnv.hasChatFixtures || !TestEnv.hasSecondChatRoom) {
      return;
    }
    await ensureSupabaseInitialized(
      url: TestEnv.supabaseUrl!,
      anonKey: TestEnv.supabaseAnonKey!,
    );

    await AuthService.instance
        .signIn(
          TestEnv.testEmail!,
          TestEnv.testPassword!,
        )
        .timeout(const Duration(seconds: 20));

    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final roomId1 = TestEnv.testRoomId!;
    final roomId2 = TestEnv.testRoomId2!;

    await ChatRoomService()
        .ensureRoom(
          roomId: roomId1,
          productId: TestEnv.testProductId!,
          buyerId: TestEnv.testBuyerId!,
          sellerId: TestEnv.testSellerId!,
        )
        .timeout(const Duration(seconds: 10));
    await ChatRoomService()
        .ensureRoom(
          roomId: roomId2,
          productId: TestEnv.testProductId2!,
          buyerId: TestEnv.testBuyerId!,
          sellerId: TestEnv.testSellerId!,
        )
        .timeout(const Duration(seconds: 10));

    await MessageService()
        .sendMessage(
          roomId: roomId1,
          content: 'First room message',
        )
        .timeout(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await MessageService()
        .sendMessage(
          roomId: roomId2,
          content: 'Second room message',
        )
        .timeout(const Duration(seconds: 10));

    final rooms = await ChatRoomService()
        .streamRoomsForUser(userId)
        .first
        .timeout(const Duration(seconds: 5));
    expect(rooms.first.roomId, roomId2);

    await AuthService.instance.signOut().timeout(const Duration(seconds: 10));
  }, skip: !TestEnv.hasAuthCreds || !TestEnv.hasChatFixtures || !TestEnv.hasSecondChatRoom);

  testWidgets('Chat: unauthorized user cannot read room', (tester) async {
    if (!TestEnv.hasAuthCreds || !TestEnv.hasChatFixtures || !TestEnv.hasOtherAuthCreds) {
      return;
    }
    await ensureSupabaseInitialized(
      url: TestEnv.supabaseUrl!,
      anonKey: TestEnv.supabaseAnonKey!,
    );

    await AuthService.instance.signOut().timeout(const Duration(seconds: 10));
    await AuthService.instance
        .signIn(
          TestEnv.testOtherEmail!,
          TestEnv.testOtherPassword!,
        )
        .timeout(const Duration(seconds: 20));

    final row = await Supabase.instance.client
        .from('chat_rooms')
        .select('room_id')
        .eq('room_id', TestEnv.testRoomId!)
        .maybeSingle();
    expect(row, isNull);

    await AuthService.instance.signOut().timeout(const Duration(seconds: 10));
  }, skip: !TestEnv.hasAuthCreds || !TestEnv.hasChatFixtures || !TestEnv.hasOtherAuthCreds);

  testWidgets('Chat: hard delete stays hidden after new message', (tester) async {
    // This is the desired behavior, but current server trigger restores visibility
    // on new messages. Keep this skipped until hard delete is implemented.
  }, skip: true);
}
