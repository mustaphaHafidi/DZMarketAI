import 'dart:ui';

import 'package:dzmarket/src/utils/detail_layout_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldUseWideDetailLayout', () {
    test('always enables wide layout on web', () {
      expect(
        shouldUseWideDetailLayout(
          screenSize: const Size(390, 844),
          isWeb: true,
        ),
        isTrue,
      );
    });

    test('keeps phone layout on narrow Android devices', () {
      expect(
        shouldUseWideDetailLayout(
          screenSize: const Size(411, 915),
          isWeb: false,
        ),
        isFalse,
      );
    });

    test('enables wide layout on tablet portrait devices', () {
      expect(
        shouldUseWideDetailLayout(
          screenSize: const Size(800, 1280),
          isWeb: false,
        ),
        isTrue,
      );
    });

    test('enables wide layout on tablet landscape devices', () {
      expect(
        shouldUseWideDetailLayout(
          screenSize: const Size(1280, 800),
          isWeb: false,
        ),
        isTrue,
      );
    });
  });
}
