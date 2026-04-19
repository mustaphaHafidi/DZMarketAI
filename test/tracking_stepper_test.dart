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
}
