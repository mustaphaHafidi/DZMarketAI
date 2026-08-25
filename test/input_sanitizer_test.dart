import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InputSanitizer.normalizeEmailForSignUp', () {
    test('keeps non-Gmail addresses unchanged apart from trim/lowercase', () {
      expect(
        InputSanitizer.normalizeEmailForSignUp(' User.Name@Example.COM '),
        'user.name@example.com',
      );
    });

    test('normalizes Gmail dot and plus aliases to one signup email', () {
      expect(
        InputSanitizer.normalizeEmailForSignUp('te.st+seller@Gmail.com'),
        'test@gmail.com',
      );
      expect(
        InputSanitizer.normalizeEmailForSignUp('test@googlemail.com'),
        'test@gmail.com',
      );
    });
  });
}
