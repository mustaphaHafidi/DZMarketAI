// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main() async {
  // Vos vraies clés de la photo
  final apiId = Platform.environment['YALIDINE_API_ID'] ?? '';
  final apiToken = Platform.environment['YALIDINE_API_TOKEN'] ?? '';

  print('=== Test validation Yalidine ===\n');
  if (apiId.isEmpty || apiToken.isEmpty) {
    print('Missing YALIDINE_API_ID or YALIDINE_API_TOKEN in environment.');
    return;
  }
  print('API ID: $apiId');
  print('Token: ${apiToken.substring(0, 20)}...\n');

  final uri = Uri.parse('https://api.yalidine.app/v1/wilayas/');

  try {
    final resp = await http
        .get(
          uri,
          headers: {
            'X-API-ID': apiId,
            'X-API-TOKEN': apiToken,
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 8));

    print('Status: ${resp.statusCode}');

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      print('❌ ERREUR: Clés invalides (auth failed)');
      return;
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      print('❌ ERREUR: HTTP ${resp.statusCode}');
      print('Body: ${resp.body}');
      return;
    }

    try {
      final data = jsonDecode(resp.body);
      // Yalidine API returns {has_more, total_data, data, links}
      if (data is Map && data.containsKey('data')) {
        print('✓ Validation réussie!');
        print('Response structure:');
        print('  - has_more: ${data['has_more']}');
        print('  - total_data: ${data['total_data']}');
        print('  - data: ${(data['data'] as List).length} wilayas');
        print('  - Sample: ${(data['data'] as List).first}');
      } else {
        print('❌ ERREUR: Structure inattendue');
        print('Keys: ${(data as Map).keys.toList()}');
      }
    } catch (e) {
      print('❌ ERREUR: JSON decode failed - $e');
    }
  } catch (e) {
    print('❌ ERREUR: Exception - $e');
  }
}
