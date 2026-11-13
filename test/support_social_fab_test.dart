import 'package:dzmarket/src/widgets/support_social_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject({Future<void> Function(Uri uri)? onOpen}) {
    return MaterialApp(
      home: Scaffold(body: SupportSocialFab(onOpen: onOpen)),
    );
  }

  testWidgets('keeps destinations hidden until help is opened', (tester) async {
    await tester.pumpWidget(subject());

    expect(find.byTooltip('Aide et réseaux'), findsOneWidget);
    expect(find.byTooltip('Facebook'), findsNothing);

    await tester.tap(find.byTooltip('Aide et réseaux'));
    await tester.pump();

    expect(find.byTooltip('Contacter DZMarket'), findsOneWidget);
    expect(find.byTooltip('Facebook'), findsOneWidget);
    expect(find.byTooltip('Instagram'), findsOneWidget);
    expect(find.byTooltip('TikTok'), findsNothing);
    expect(find.byTooltip('YouTube'), findsOneWidget);
  });

  testWidgets('opens the official Facebook destination and closes the menu', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(subject(onOpen: (uri) async => opened = uri));

    await tester.tap(find.byTooltip('Aide et réseaux'));
    await tester.pump();
    await tester.tap(find.byTooltip('Facebook'));
    await tester.pump();

    expect(opened, Uri.parse('https://www.facebook.com/DZMarketpro'));
    expect(find.byTooltip('Facebook'), findsNothing);
  });
}
