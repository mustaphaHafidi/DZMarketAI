import 'dart:convert';

import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/test_env.dart';
import '../test/test_supabase.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Couriers: validate token success/failure', (tester) async {
    if (!TestEnv.hasCourierCreds) {
      return;
    }
    final courier = TestEnv.testCourierName!;
    final apiKey = TestEnv.testCourierApiKey!;
    final apiSecret = TestEnv.testCourierApiSecret ?? '';

    final service = ShippingService();
    final ok = await service.validateCredentialsDetailed(
      courierName: courier,
      apiKey: apiKey,
      apiSecret: apiSecret,
    );
    expect(ok['ok'], isTrue);

    final bad = await service.validateCredentialsDetailed(
      courierName: courier,
      apiKey: 'invalid-token',
      apiSecret: 'invalid-secret',
    );
    expect(bad['ok'], isFalse);
  }, skip: !TestEnv.hasCourierCreds);

  testWidgets('Couriers: create parcel + label (live)', (tester) async {
    final allowLive = (TestEnv.testCourierCreateParcel ?? '').toLowerCase() == 'true';
    if (!allowLive ||
        !TestEnv.hasAuthCreds ||
        !TestEnv.hasOrderFixture ||
        !TestEnv.hasCourierCreds ||
        (TestEnv.testShipmentSelectionJson ?? '').isEmpty) {
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

    final selection = jsonDecode(TestEnv.testShipmentSelectionJson!) as Map<String, dynamic>;
    final courierName = TestEnv.testCourierName!;
    final courierId = TestEnv.testCourierId ?? courierName.toLowerCase().replaceAll(' ', '-');

    final result = await ShippingService().createShipment(
      orderId: TestEnv.testOrderId!,
      courierId: courierId,
      courierName: courierName,
      selection: selection,
    );

    expect(result['ok'], isNot(false));

    await AuthService.instance.signOut();
  }, skip: (TestEnv.testCourierCreateParcel ?? '').toLowerCase() != 'true');
}
