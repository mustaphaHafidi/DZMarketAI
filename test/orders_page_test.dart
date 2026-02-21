import 'package:dzmarket/src/features/orders/orders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        anonKey: 'test',
      );
    }
  });

  testWidgets('Orders page prompts sign-in when signed out', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OrdersPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connectez-vous'), findsOneWidget);
  });
}
