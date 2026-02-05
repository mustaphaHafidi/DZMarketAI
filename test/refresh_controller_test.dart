import 'package:dzmarket/src/widgets/refresh_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RefreshController prevents concurrent refresh and resets state',
      (tester) async {
    final controller = RefreshController(timeout: const Duration(milliseconds: 50));
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => controller.run(context, () async {
              calls++;
              await Future.delayed(const Duration(milliseconds: 30));
            }),
            child: const Text('refresh'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('refresh'));
    await tester.tap(find.text('refresh')); // should be ignored while running
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(calls, 1);
    expect(controller.refreshing, false);
  });

  testWidgets('RefreshController handles timeout', (tester) async {
    final controller = RefreshController(timeout: const Duration(milliseconds: 10));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => controller.run(context, () async {
                  await Future.delayed(const Duration(milliseconds: 30));
                }),
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(controller.refreshing, false);
  });
}
