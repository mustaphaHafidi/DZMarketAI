import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>> _loadJson(String path) async {
  final raw = await rootBundle.loadString(path);
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw StateError('Invalid JSON map in $path');
  }
  return decoded;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('i18n keys are mirrored between fr/ar', () async {
    final fr = await _loadJson('assets/i18n/fr.json');
    final ar = await _loadJson('assets/i18n/ar.json');

    final frKeys = fr.keys.toSet();
    final arKeys = ar.keys.toSet();

    final missingInAr = frKeys.difference(arKeys);
    final missingInFr = arKeys.difference(frKeys);

    expect(missingInAr, isEmpty,
        reason: 'Missing in ar.json: ${missingInAr.join(', ')}');
    expect(missingInFr, isEmpty,
        reason: 'Missing in fr.json: ${missingInFr.join(', ')}');

    for (final key in frKeys) {
      final frValue = fr[key];
      final arValue = ar[key];
      expect(frValue, isA<String>(), reason: 'Non-string fr value for $key');
      expect(arValue, isA<String>(), reason: 'Non-string ar value for $key');
      expect((frValue as String).isNotEmpty, isTrue,
          reason: 'Empty fr value for $key');
      expect((arValue as String).isNotEmpty, isTrue,
          reason: 'Empty ar value for $key');
    }
  });
}
