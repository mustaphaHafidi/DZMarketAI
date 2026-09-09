import 'package:dzmarket/src/utils/ecotrack_base_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the current Ecotrack host when no URL is supplied', () {
    expect(normalizeEcotrackBaseUrl(null), defaultEcotrackBaseUrl);
  });

  test('normalizes an approved HTTPS-style provider URL', () {
    expect(
      normalizeEcotrackBaseUrl('https://partner.ecotrack.dz/'),
      'https://partner.ecotrack.dz',
    );
  });

  test('rejects unsafe or ambiguous provider URLs', () {
    expect(normalizeEcotrackBaseUrl('http://partner.ecotrack.dz'), isNull);
    expect(normalizeEcotrackBaseUrl('https://partner.ecotrack.dz/api'), isNull);
    expect(
      normalizeEcotrackBaseUrl('https://user:pass@partner.ecotrack.dz'),
      isNull,
    );
  });
}
