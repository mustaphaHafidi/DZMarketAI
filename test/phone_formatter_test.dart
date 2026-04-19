import 'package:dzmarket/src/services/phone_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeDzE164 converts local numbers to +213 format', () {
    expect(PhoneFormatter.normalizeDzE164('0555010203'), '+213555010203');
    expect(PhoneFormatter.normalizeDzE164('0612345678'), '+213612345678');
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
