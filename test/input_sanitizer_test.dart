import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InputSanitizer.sanitizeText newlines', () {
    test('allowNewlines: true preserves line breaks', () {
      expect(
        InputSanitizer.sanitizeText(
          'Chari y3ayt, message manripondich.\n0549241946\n0561646134',
          maxLength: 1200,
          allowNewlines: true,
        ),
        'Chari y3ayt, message manripondich.\n0549241946\n0561646134',
      );
    });

    test('allowNewlines: true still strips other control chars', () {
      expect(
        InputSanitizer.sanitizeText(
          'a\u0000b\tc\n d',
          maxLength: 1200,
          allowNewlines: true,
        ),
        'abc\n d',
      );
    });

    test('allowNewlines: false (default) strips line breaks', () {
      expect(
        InputSanitizer.sanitizeText('line1\nline2', maxLength: 200),
        'line1line2',
      );
    });

    test('sanitizeOptionalText with allowNewlines: true preserves breaks', () {
      expect(
        InputSanitizer.sanitizeOptionalText(
          'a\nb\nc',
          maxLength: 1200,
          allowNewlines: true,
        ),
        'a\nb\nc',
      );
    });

    test('maxLength truncation still applies with newlines preserved', () {
      final result = InputSanitizer.sanitizeText(
        'abcdefghij\nklmnop',
        maxLength: 11,
        allowNewlines: true,
      );
      expect(result.length, 11);
      expect(result, 'abcdefghij\n');
    });
  });
}
