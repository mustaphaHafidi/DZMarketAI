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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('COD: wilaya/commune load + order creation', (tester) async {
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

    final orderId = await OrderService().createOrder(
      productId: TestEnv.testProductId!,
      paymentMethod: 'cod',
      shippingOption: 'cod',
      deliveryMethod: 'home',
    );
    expect(orderId, isNotNull);

    final row = await Supabase.instance.client
        .from('orders')
        .select('id,status,payment_status')
        .eq('id', orderId!)
        .maybeSingle();
    expect(row?['status'], 'pending');
    expect(row?['payment_status'], 'pending');

    await AuthService.instance.signOut();
  }, skip: !TestEnv.hasAuthCreds || (TestEnv.testProductId ?? '').isEmpty);

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
      () async => OrderService().createOrder(
        productId: '0',
        paymentMethod: 'cod',
      ),
      throwsA(anything),
    );

    await AuthService.instance.signOut();
  }, skip: !TestEnv.hasAuthCreds);
}
