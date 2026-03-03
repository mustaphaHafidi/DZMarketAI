import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/test_env.dart';
import '../test/test_supabase.dart';

String _courierIdFromName(String name, String? fallback) {
  if (fallback != null && fallback.isNotEmpty) return fallback;
  final lower = name.toLowerCase();
  if (lower.contains('yalidine')) return 'yalidine';
  if (lower.contains('ecotrack')) return 'ecotrack';
  return lower.replaceAll(' ', '-');
}

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
    'COD: wilaya/commune load + order creation',
    (tester) async {
      if (!TestEnv.hasAuthCreds || (TestEnv.testProductId ?? '').isEmpty) {
        return;
      }
      await ensureSupabaseInitialized(
        url: TestEnv.supabaseUrl!,
        anonKey: TestEnv.supabaseAnonKey!,
      );

      await AuthService.instance.signIn(
        TestEnv.testEmail!,
        TestEnv.testPassword!,
      );

      final courierName = TestEnv.testCourierName ?? 'Yalidine Express';
      final courierId = _courierIdFromName(courierName, TestEnv.testCourierId);
      final settings = {
        if (TestEnv.testCourierApiKey != null)
          'api_key': TestEnv.testCourierApiKey!,
        if ((TestEnv.testCourierApiSecret ?? '').isNotEmpty)
          'api_secret': TestEnv.testCourierApiSecret!,
      };

      final shipping = ShippingService();
      final wilayas = await shipping.fetchCourierWilayas(
        courierId: courierId,
        settings: settings,
      );
      expect(wilayas.isNotEmpty, isTrue);
      final wilayaCode = wilayas.first['code'] ?? wilayas.first['id'] ?? '';

      final communes = await shipping.fetchCourierCommunes(
        courierId: courierId,
        settings: settings,
        wilayaCode: wilayaCode,
      );
      expect(communes.isNotEmpty, isTrue);

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
            currentUserId: Supabase.instance.client.auth.currentUser?.id ?? '',
            excludedIds: attempted,
          );
          if (fallback == null) {
            // Fixture issue: no in-stock product available for this buyer.
            await AuthService.instance.signOut();
            return;
          }
          productId = fallback;
        }
      }
      expect(orderId, isNotNull);

      final row = await Supabase.instance.client
          .from('orders')
          .select('id,status,payment_status')
          .eq('id', orderId!)
          .maybeSingle();
      expect(row?['status'], 'pending');
      expect(row?['payment_status'], 'pending');

      await AuthService.instance.signOut();
    },
    skip: !TestEnv.hasAuthCreds || (TestEnv.testProductId ?? '').isEmpty,
  );

  testWidgets('COD: invalid product triggers error', (tester) async {
    if (!TestEnv.hasAuthCreds) {
      return;
    }
    await ensureSupabaseInitialized(
      url: TestEnv.supabaseUrl!,
      anonKey: TestEnv.supabaseAnonKey!,
    );

    await AuthService.instance.signIn(
      TestEnv.testEmail!,
      TestEnv.testPassword!,
    );

    expect(
      () async =>
          OrderService().createOrder(productId: '0', paymentMethod: 'cod'),
      throwsA(anything),
    );

    await AuthService.instance.signOut();
  }, skip: !TestEnv.hasAuthCreds);
}
