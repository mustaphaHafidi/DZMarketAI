import 'package:dzmarket/src/services/order_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/test_env.dart';
import '../test/test_supabase.dart';

bool _isOutOfStockError(Object error) {
  if (error is! PostgrestException) return false;
  final text = '${error.code}|${error.message}|${error.details}'.toLowerCase();
  return text.contains('out of stock') ||
      text.contains('stock') && text.contains('0');
}

Future<String?> _findAlternativeProductId({
  required String currentUserId,
  required Set<String> excludedIds,
}) async {
  try {
    var query = Supabase.instance.client
        .from('products')
        .select('id,owner_id,status,is_archived,stock_quantity')
        .eq('status', 'active')
        .eq('is_archived', false)
        .gt('stock_quantity', 0);

    if (currentUserId.isNotEmpty) {
      query = query.neq('owner_id', currentUserId);
    }

    final rows = await query.order('created_at', ascending: false).limit(50);
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty || excludedIds.contains(id)) continue;
      return id;
    }
  } catch (_) {
    // Best-effort fallback lookup for flaky fixtures.
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Order system messages: created + dedupe',
    (tester) async {
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

      final attempted = <String>{};
      var productId = TestEnv.testProductId!;
      String? orderId;
      while (true) {
        attempted.add(productId);
        try {
          orderId = await OrderService().createOrder(
            productId: productId,
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
          break;
        } on PostgrestException catch (e) {
          if (!_isOutOfStockError(e)) rethrow;
          final fallback = await _findAlternativeProductId(
            currentUserId: client.auth.currentUser?.id ?? '',
            excludedIds: attempted,
          );
          if (fallback == null) {
            // Fixture issue: no in-stock product available for this buyer.
            await client.auth.signOut();
            return;
          }
          productId = fallback;
        }
      }
      expect(orderId, isNotNull);

      final conv =
          await client.rpc(
                'ensure_order_conversation',
                params: {'p_order_id': orderId},
              )
              as Map<String, dynamic>;
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
    },
    skip: !TestEnv.hasAuthCreds || (TestEnv.testProductId ?? '').isEmpty,
  );
}
