import 'dart:convert';
import 'dart:developer' as developer;

import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/test_env.dart';

Map<String, dynamic> _parseSelection(String raw) {
  dynamic current = raw.trim();
  for (var i = 0; i < 6; i++) {
    if (current is Map<String, dynamic>) return current;
    if (current is String) {
      final normalized = current.trim();
      try {
        final decoded = jsonDecode(normalized);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is String) {
          current = decoded;
          continue;
        }
      } catch (_) {}
      current = normalized;
      continue;
    }
    break;
  }
  throw StateError('TEST_SHIPMENT_SELECTION_JSON must be a JSON object');
}

bool _isZrExpress(Map<String, dynamic> selection) {
  final courierId = (selection['courierId'] ?? '').toString().toLowerCase();
  final courierName = (selection['courierName'] ?? '').toString().toLowerCase();
  return courierId.contains('zrexpress') ||
      courierId.contains('zr express') ||
      courierId.contains('zr-express') ||
      courierName.contains('zrexpress') ||
      courierName.contains('zr express') ||
      courierName.contains('zr-express');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ZR Express selection requires E.164 phone', (tester) async {
    final raw = TestEnv.testShipmentSelectionJson;
    if (raw == null || raw.isEmpty) {
      developer.log(
        'Skipping ZR Express selection test; missing TEST_SHIPMENT_SELECTION_JSON',
      );
      return;
    }
    final selection = _parseSelection(raw);
    if (!_isZrExpress(selection)) {
      developer.log('Skipping; TEST_SHIPMENT_SELECTION_JSON not ZR Express.');
      return;
    }
    final phoneE164 = selection['phone_e164']?.toString() ?? '';
    expect(phoneE164, isNotEmpty);
    expect(RegExp(r'^\+\d{8,15}$').hasMatch(phoneE164), isTrue);
  });
}
