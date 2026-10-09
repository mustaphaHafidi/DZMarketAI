import 'package:dzmarket/src/features/listings/listings_page.dart';
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

  testWidgets(
    'Listings page: no "Selon vos interets" section for a signed-out visitor',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ListingsPage()));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // No saved searches / favorites signal is possible while signed out,
      // so the discovery section must stay hidden and default behavior
      // (guest browse banner) must still render exactly as before.
      expect(find.text('Selon vos intérêts'), findsNothing);
      expect(
        find.text('Parcourez librement. Connectez-vous pour agir.'),
        findsOneWidget,
      );
    },
  );
}
