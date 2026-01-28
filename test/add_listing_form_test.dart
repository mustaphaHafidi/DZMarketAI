import 'package:dzmarket/src/features/listings/add_listing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Add listing: continue disabled when required fields missing',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AddListingPage()));
    await tester.pumpAndSettle();

    final continueButtons = find.widgetWithText(FilledButton, 'Continuer');
    expect(continueButtons, findsWidgets);

    final buttons = tester.widgetList<FilledButton>(continueButtons).toList();
    expect(buttons.any((button) => button.onPressed == null), isTrue);
  });
}
