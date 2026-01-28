import 'package:dzmarket/src/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/test_env.dart';
import '../test/test_supabase.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RLS: user cannot read other user orders', (tester) async {
    if (!TestEnv.hasAuthCreds || (TestEnv.testOtherOrderId ?? '').isEmpty) {
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

    final row = await Supabase.instance.client
        .from('orders')
        .select('id')
        .eq('id', TestEnv.testOtherOrderId!)
        .maybeSingle();
    expect(row, isNull);

    await AuthService.instance.signOut();
  }, skip: !TestEnv.hasAuthCreds || (TestEnv.testOtherOrderId ?? '').isEmpty);
}
