import 'package:dzmarket/src/utils/declared_value_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('declared value follows price while untouched', () {
    final next = nextDeclaredValueFromPrice(
      priceText: '12000',
      currentDeclaredValueText: '',
      manuallyEdited: false,
    );

    expect(next, '12000');
  });

  test('declared value keeps manual override', () {
    final next = nextDeclaredValueFromPrice(
      priceText: '12000',
      currentDeclaredValueText: '9000',
      manuallyEdited: true,
    );

    expect(next, '9000');
  });

  test('manual override is disabled when declared value matches price', () {
    expect(
      isDeclaredValueManualOverride(
        priceText: '12 000',
        declaredValueText: '12000',
      ),
      isFalse,
    );
  });

  test(
    'manual override is detected when declared value differs from price',
    () {
      expect(
        isDeclaredValueManualOverride(
          priceText: '12000',
          declaredValueText: '9000',
        ),
        isTrue,
      );
    },
  );
}
