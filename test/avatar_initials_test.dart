import 'package:dzmarket/src/utils/avatar_initials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses first and last initials when full name is available', () {
    expect(userInitials(fullName: 'Mustapha Hafidi'), 'MH');
  });

  test('uses first two letters for a single name', () {
    expect(userInitials(fullName: 'Mustapha'), 'MU');
  });

  test('falls back to email local part when full name is empty', () {
    expect(userInitials(email: 'hafmustapha1@gmail.com'), 'HA');
  });

  test('keeps Arabic initials readable', () {
    expect(userInitials(fullName: 'محمد علي'), 'مع');
  });

  test('returns question mark when no user label is available', () {
    expect(userInitials(), '?');
  });
}
