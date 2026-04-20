import 'package:dzmarket/src/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('user avatar renders initials when photo is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserAvatar(fullName: 'Mustapha Hafidi', radius: 24),
        ),
      ),
    );

    expect(find.text('MH'), findsOneWidget);
  });

  testWidgets('user avatar falls back to icon when no name is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UserAvatar(radius: 24))),
    );

    expect(find.byIcon(Icons.person), findsOneWidget);
  });
}
