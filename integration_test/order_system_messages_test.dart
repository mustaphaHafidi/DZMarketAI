import 'package:dzmarket/src/services/order_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/test_env.dart';
import '../test/test_supabase.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Order system messages: created + dedupe', (tester) async {
    if (!TestEnv.hasAuthCreds || (TestEnv.testProductId ?? '').isEmpty) {
      return;
    }

    await ensureSupabaseInitialized(
      url: TestEnv.supabaseUrl!,
      anonKey: TestEnv.supabaseAnonKey!,
    );

    final client = Supabase.instance.client;
    await client.auth.signInWithPassword(
      email: TestEnv.testEmail!,
      password: TestEnv.testPassword!,
    );

    final orderId = await OrderService().createOrder(
      productId: TestEnv.testProductId!,
      paymentMethod: 'cod',
      shippingOption: 'cod',
      deliveryMethod: 'home',
      shippingCost: 0,
      feeAmount: 0,
      shippingSelection: const {
        'senderWilaya': 'Alger',
        'receiverWilaya': 'M\'Sila',
        'receiverCommune': 'M\'Sila',
        'firstname': 'Test',
        'familyname': 'Test',
        'phone': '0700000000',
        'address': 'Test address',
        'productList': 'Test product',
        'price': 1000,
        'weight': 2,
        'height': 30,
        'width': 30,
        'length': 30,
      },
    );
    expect(orderId, isNotNull);

    final conv = await client.rpc(
      'ensure_order_conversation',
      params: {'p_order_id': orderId},
    ) as Map<String, dynamic>;
    final conversationId = conv['id'].toString();

    final created = await client
        .from('messages')
        .select('id,type,dedupe_key,text')
        .eq('conversation_id', conversationId)
        .eq('dedupe_key', 'order:$orderId:created');
    expect(created, isNotEmpty);
    expect(created.first['type'], 'system');

    final payload = {
      'i18n_key': 'order.system.validated',
      'status': 'validated',
      'status_i18n': 'order.status.validated',
    };
    await client.rpc(
      'post_order_event',
      params: {
        'p_order_id': orderId,
        'p_event': 'order_validated',
        'p_payload': payload,
        'p_dedupe_key': 'order:$orderId:validated',
      },
    );
    await client.rpc(
      'post_order_event',
      params: {
        'p_order_id': orderId,
        'p_event': 'order_validated',
        'p_payload': payload,
        'p_dedupe_key': 'order:$orderId:validated',
      },
    );

    final validated = await client
        .from('messages')
        .select('id')
        .eq('conversation_id', conversationId)
        .eq('dedupe_key', 'order:$orderId:validated');
    expect(validated.length, 1);

    await client.auth.signOut();
  }, skip: !TestEnv.hasAuthCreds || (TestEnv.testProductId ?? '').isEmpty);
}
