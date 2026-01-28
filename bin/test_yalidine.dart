// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main() async {
  final apiId = Platform.environment['YALIDINE_API_ID'] ?? '';
  final apiToken = Platform.environment['YALIDINE_API_TOKEN'] ?? '';
  final uri = Uri.parse('https://api.yalidine.app/v1/wilayas/');

  print('=== Testing Yalidine API Request ===\n');
  if (apiId.isEmpty || apiToken.isEmpty) {
    print('Missing YALIDINE_API_ID or YALIDINE_API_TOKEN in environment.');
    return;
  }

  // Test 1: Basic request with headers
  print('Test 1: Basic GET request');
  try {
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
    print('Response Headers: ${response.headers}');
    print('Body length: ${response.body.length}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      print('✓ Request succeeded');
      try {
        final data = jsonDecode(response.body);
        print('Response type: ${data.runtimeType}');
        if (data is Map) {
          print('Response keys: ${data.keys.toList()}');
        }
        print(
          'First 200 chars: ${response.body.substring(0, (response.body.length > 200 ? 200 : response.body.length))}',
        );
      } catch (e) {
        print('Could not parse as JSON: $e');
      }
    } else {
      print('✗ Request failed with status ${response.statusCode}');
      print('Body: ${response.body}');
    }
  } catch (e) {
    print('✗ Exception: $e');
  }
}
