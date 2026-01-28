// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  final apiId = Platform.environment['YALIDINE_API_ID'] ?? '';
  final apiToken = Platform.environment['YALIDINE_API_TOKEN'] ?? '';
  final hasEnv = apiId.isNotEmpty && apiToken.isNotEmpty;
  final uri = Uri.parse('https://api.yalidine.app/v1/wilayas/');

  test('Yalidine API Request', () async {
    print('=== Testing Yalidine API Request ===\n');

    final response = await http
        .get(
          uri,
          headers: {
            'X-API-ID': apiId,
            'X-API-TOKEN': apiToken,
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 10));

    print('Status Code: ${response.statusCode}');
    print('Headers: ${response.headers}');
    print(
      'Body (first 500 chars): ${response.body.substring(0, (response.body.length > 500 ? 500 : response.body.length))}',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map;
      print('OK: parsed JSON');
      print('Response keys: ${data.keys.toList()}');
    }
  }, skip: !hasEnv);
}
