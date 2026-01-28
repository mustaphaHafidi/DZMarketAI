import 'package:dzmarket/src/app.dart';
import 'package:dzmarket/src/features/home/home_shell.dart';
import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/test_env.dart';
import '../test/test_supabase.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Router refresh: redirects on auth change', (tester) async {
    if (!TestEnv.hasAuthCreds) {
      return;
    }
    await ensureSupabaseInitialized(
      url: TestEnv.supabaseUrl!,
      anonKey: TestEnv.supabaseAnonKey!,
    );

    await LocaleService.instance.init();
    await AuthService.instance.signOut();

    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(DZMarketApp(scaffoldMessengerKey: messengerKey));
    await tester.pumpAndSettle();

    expect(find.text('Se connecter'), findsOneWidget);

    await AuthService.instance.signIn(
      TestEnv.testEmail!,
      TestEnv.testPassword!,
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);

    await AuthService.instance.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Se connecter'), findsOneWidget);
  }, skip: !TestEnv.hasAuthCreds);
}
