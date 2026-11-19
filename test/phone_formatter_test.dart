import 'package:dzmarket/src/services/phone_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeDzE164 converts local numbers to +213 format', () {
    expect(PhoneFormatter.normalizeDzE164('0555010203'), '+213555010203');
    expect(PhoneFormatter.normalizeDzE164('0612345678'), '+213612345678');
  });

  test('normalizeDzMobileE164 accepts only Algerian mobile formats', () {
    expect(
      PhoneFormatter.normalizeDzMobileE164('0555 010 203'),
      '+213555010203',
    );
    expect(
      PhoneFormatter.normalizeDzMobileE164('+213 667 854 321'),
      '+213667854321',
    );
    expect(PhoneFormatter.normalizeDzMobileE164('0211234567'), isEmpty);
    expect(PhoneFormatter.normalizeDzMobileE164('061234567'), isEmpty);
    expect(PhoneFormatter.normalizeDzMobileE164('+33612345678'), isEmpty);
  });

  test('normalizeDzE164 cleans +2130 prefix', () {
    expect(PhoneFormatter.normalizeDzE164('+2130555010203'), '+213555010203');
  });

  test('normalizeDzE164 returns empty on invalid input', () {
    expect(PhoneFormatter.normalizeDzE164(''), '');
    expect(PhoneFormatter.normalizeDzE164('123'), '');
  });

  test('normalizeDzE164ForZr accepts 05/06 and rejects 07 numbers', () {
    expect(PhoneFormatter.normalizeDzE164ForZr('0555010203'), '+213555010203');
    expect(PhoneFormatter.normalizeDzE164ForZr('0612345678'), '+213612345678');
    expect(PhoneFormatter.normalizeDzE164ForZr('0755298469'), '');
  });
}
