import 'package:dzmarket/src/models/tracking_progress.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/widgets/tracking_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildApp({
  required Locale locale,
  required TrackingPresentation presentation,
  bool compact = false,
  bool showAlert = true,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('fr'), Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: TrackingStepper(
        presentation: presentation,
        compact: compact,
        showAlert: showAlert,
      ),
    ),
  );
}

void main() {
  test('order delay messages stay neutral in French and Arabic', () {
    expect(
      L10n.trLocale('fr', 'order.system.label_reminder'),
      'Expedition en attente : le bordereau n\'a pas encore ete genere.',
    );
    expect(
      L10n.trLocale('fr', 'order.system.carrier_scan_reminder'),
      'Retard d\'expedition : le bordereau est genere mais aucun mouvement transporteur n\'a encore ete detecte.',
    );
    expect(
      L10n.trLocale('ar', 'order.system.label_reminder'),
      'الشحن قيد الانتظار: لم يتم إنشاء البوليصة بعد.',
    );
    expect(
      L10n.trLocale('ar', 'order.system.carrier_scan_reminder'),
      'تأخر في الشحن: تم إنشاء البوليصة لكن لم يتم رصد أي حركة من شركة النقل بعد.',
    );
  });

  testWidgets('tracking stepper renders French labels and reminder alert', (
    tester,
  ) async {
    final presentation = TrackingPresentation.fromData(
      status: 'pending',
      createdAt: DateTime.now().subtract(const Duration(hours: 50)),
    );

    await tester.pumpWidget(
      _buildApp(locale: const Locale('fr'), presentation: presentation),
    );

    expect(find.text(L10n.trLocale('fr', 'tracking.step.ordered')), findsOne);
    expect(
      find.text(L10n.trLocale('fr', 'tracking.step.label_ready')),
      findsOne,
    );
    expect(
      find.text(L10n.trLocale('fr', 'tracking.alert.label_reminder')),
      findsOne,
    );
    expect(
      find.text('Expedition en attente : le bordereau n\'a pas encore ete genere.'),
      findsOne,
    );
  });

  testWidgets('tracking stepper renders Arabic labels for out for delivery', (
    tester,
  ) async {
    final presentation = TrackingPresentation.fromData(
      status: 'out_for_delivery',
      trackingNumber: 'TRK123',
      labelUrl: 'https://example.com/label.pdf',
      createdAt: DateTime.now().subtract(const Duration(hours: 24)),
    );

    await tester.pumpWidget(
      _buildApp(locale: const Locale('ar'), presentation: presentation),
    );

    expect(
      find.text(L10n.trLocale('ar', 'tracking.step.out_for_delivery')),
      findsOne,
    );
    expect(find.text(L10n.trLocale('ar', 'tracking.step.delivered')), findsOne);
  });

  testWidgets('tracking stepper can hide alert banner', (tester) async {
    final presentation = TrackingPresentation.fromData(
      status: 'pending',
      createdAt: DateTime.now().subtract(const Duration(hours: 73)),
    );

    await tester.pumpWidget(
      _buildApp(
        locale: const Locale('fr'),
        presentation: presentation,
        compact: true,
        showAlert: false,
      ),
    );

    expect(
      find.text(L10n.trLocale('fr', 'tracking.alert.auto_cancel_soon')),
      findsNothing,
    );
  });

  testWidgets('tracking stepper renders Arabic neutral overdue alert', (
    tester,
  ) async {
    final presentation = TrackingPresentation.fromData(
      status: 'shipped',
      trackingNumber: 'TRK123',
      labelUrl: 'https://example.com/label.pdf',
      createdAt: DateTime.now().subtract(const Duration(hours: 97)),
    );

    await tester.pumpWidget(
      _buildApp(locale: const Locale('ar'), presentation: presentation),
    );

    expect(
      find.text(
        L10n.trLocale('ar', 'tracking.alert.dropoff_overdue'),
      ),
      findsOne,
    );
  });
}
