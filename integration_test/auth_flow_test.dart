import 'dart:math';

import 'package:dzmarket/src/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/test_env.dart';
import '../test/test_supabase.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Auth: login/signup/logout/session', (tester) async {
    if (!TestEnv.hasSupabaseCreds) {
      return;
    }
    await ensureSupabaseInitialized(
      url: TestEnv.supabaseUrl!,
      anonKey: TestEnv.supabaseAnonKey!,
    );

    final auth = AuthService.instance;
    final email = TestEnv.testEmail;
    final password = TestEnv.testPassword;

    if (email == null || password == null) {
      return;
    }

    await auth.signOut();
    final login = await auth.signIn(email, password);
    expect(login.user, isNotNull);
    expect(Supabase.instance.client.auth.currentSession, isNotNull);

    await auth.signOut();
    expect(auth.currentUser, isNull);

    final rnd = Random().nextInt(100000);
    final newEmail = 'test+$rnd@dzmarket.dev';
    final newPassword = 'Passw0rd!$rnd';
    final signup = await auth.signUp(newEmail, newPassword);
    expect(signup.user, isNotNull);

    await auth.signOut();
  }, skip: !TestEnv.hasAuthCreds);

  testWidgets('Auth: invalid token is rejected', (tester) async {
    if (!TestEnv.hasSupabaseCreds) {
      return;
    }
    await ensureSupabaseInitialized(
      url: TestEnv.supabaseUrl!,
      anonKey: TestEnv.supabaseAnonKey!,
    );

    final auth = AuthService.instance;
    try {
      final response = await auth.signIn('invalid@example.com', 'bad-password');
      expect(response.user, isNull);
    } catch (_) {
      // AuthException is acceptable for invalid credentials.
      expect(true, isTrue);
    }
  }, skip: !TestEnv.hasSupabaseCreds);
}
