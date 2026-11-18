import 'package:dzmarket/src/utils/bidi_text_direction.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectTextDirection', () {
    test('null or empty defaults to ltr', () {
      expect(detectTextDirection(null), TextDirection.ltr);
      expect(detectTextDirection(''), TextDirection.ltr);
    });

    test('pure French text is ltr', () {
      expect(
        detectTextDirection('Voiture en bon etat, entretien suivi.'),
        TextDirection.ltr,
      );
    });

    test('pure Arabic text is rtl', () {
      expect(detectTextDirection('سيارة بحالة جيدة'), TextDirection.rtl);
    });

    test('mixed text starting with Arabic is rtl', () {
      expect(detectTextDirection('سيارة Clio 4 موديل 2015'), TextDirection.rtl);
    });

    test('mixed text starting with French is ltr', () {
      expect(detectTextDirection('Clio 4 سيارة بحالة جيدة'), TextDirection.ltr);
    });

    test('leading digits/punctuation are skipped, not decisive', () {
      expect(detectTextDirection('2015 Clio 4, diesel'), TextDirection.ltr);
      expect(detectTextDirection('2015 سيارة كلیو'), TextDirection.rtl);
    });

    test('digits-only or punctuation-only text defaults to ltr', () {
      expect(detectTextDirection('1 800 000 DA - 120 000 km'), TextDirection.ltr);
    });
  });
}
