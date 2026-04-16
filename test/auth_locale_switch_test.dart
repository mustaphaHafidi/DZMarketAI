import 'package:dzmarket/src/features/auth/sign_in_page.dart';
import 'package:dzmarket/src/features/auth/sign_up_page.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpRoute(
  WidgetTester tester, {
  required String initialLocation,
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInPage(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpPage(),
      ),
      GoRoute(path: '/', builder: (context, state) => const SizedBox.shrink()),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/legal/privacy',
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/legal/terms',
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/legal/imprint',
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      locale: LocaleService.instance.locale.value,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await TranslationService.instance.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleService.instance.locale.value = const Locale('fr');
  });

  test('LocaleService init accepts quoted web locale values', () async {
    SharedPreferences.setMockInitialValues({'preferred_locale_code': '"ar"'});
    LocaleService.instance.locale.value = const Locale('fr');

    await LocaleService.instance.init();

    expect(LocaleService.instance.locale.value?.languageCode, 'ar');
  });

  testWidgets('Sign-in page switches from FR to AR', (tester) async {
    await _pumpRoute(tester, initialLocation: '/sign-in');

    expect(find.text('Connecte-toi pour acheter et vendre'), findsOneWidget);
    expect(find.text('Français'), findsOneWidget);

    await tester.tap(find.text('Arabe (Algérie)'));
    await tester.pumpAndSettle();

    expect(find.text('سجّل الدخول للشراء والبيع'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
  });

  testWidgets('Sign-up page switches from FR to AR', (tester) async {
    await _pumpRoute(tester, initialLocation: '/sign-up');

    expect(find.text('Crée ton compte pour acheter et vendre'), findsOneWidget);
    expect(find.text('Français'), findsOneWidget);

    await tester.tap(find.text('Arabe (Algérie)'));
    await tester.pumpAndSettle();

    expect(find.text('أنشئ حسابك للشراء والبيع'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
  });
}
