import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';

class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.firebaseOptions,
    required this.analyticsEnabled,
    required this.crashlyticsEnabled,
  });

  final String flavor;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final FirebaseOptions? firebaseOptions;
  final bool analyticsEnabled;
  final bool crashlyticsEnabled;

  static const _envFlavor = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: 'dev',
  );

  static const _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _envSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const _envFirebaseApiKey =
      String.fromEnvironment('FIREBASE_API_KEY');
  static const _envFirebaseAppId =
      String.fromEnvironment('FIREBASE_APP_ID');
  static const _envFirebaseSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _envFirebaseProjectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _envFirebaseStorageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const _envFirebaseMeasurementId =
      String.fromEnvironment('FIREBASE_MEASUREMENT_ID');

  static bool _envBool(String key, {required bool defaultValue}) {
    const map = <String, String>{
      'ENABLE_ANALYTICS': String.fromEnvironment('ENABLE_ANALYTICS'),
      'ENABLE_CRASHLYTICS': String.fromEnvironment('ENABLE_CRASHLYTICS'),
    };
    final raw = map[key] ?? '';
    if (raw.isEmpty) return defaultValue;
    return raw.toLowerCase() == 'true';
  }

  static Future<AppConfig> load() async {
    var flavor = _envFlavor;
    var supabaseUrl = _envSupabaseUrl;
    var supabaseAnonKey = _envSupabaseAnonKey;

    var firebaseApiKey = _envFirebaseApiKey;
    var firebaseAppId = _envFirebaseAppId;
    var firebaseSenderId = _envFirebaseSenderId;
    var firebaseProjectId = _envFirebaseProjectId;
    var firebaseStorageBucket = _envFirebaseStorageBucket;
    var firebaseMeasurementId = _envFirebaseMeasurementId;

    if (kIsWeb) {
      final runtime = await _loadWebRuntimeConfig();
      flavor = runtime['appFlavor'] ?? flavor;
      supabaseUrl = runtime['supabaseUrl'] ?? supabaseUrl;
      supabaseAnonKey = runtime['supabaseAnonKey'] ?? supabaseAnonKey;
      firebaseApiKey = runtime['firebaseApiKey'] ?? firebaseApiKey;
      firebaseAppId = runtime['firebaseAppId'] ?? firebaseAppId;
      firebaseSenderId =
          runtime['firebaseMessagingSenderId'] ?? firebaseSenderId;
      firebaseProjectId = runtime['firebaseProjectId'] ?? firebaseProjectId;
      firebaseStorageBucket =
          runtime['firebaseStorageBucket'] ?? firebaseStorageBucket;
      firebaseMeasurementId =
          runtime['firebaseMeasurementId'] ?? firebaseMeasurementId;
    }

    final analyticsEnabled =
        _envBool('ENABLE_ANALYTICS', defaultValue: kReleaseMode);
    final crashlyticsEnabled =
        _envBool('ENABLE_CRASHLYTICS', defaultValue: kReleaseMode);

    final options = _firebaseOptionsFromValues(
      apiKey: firebaseApiKey,
      appId: firebaseAppId,
      messagingSenderId: firebaseSenderId,
      projectId: firebaseProjectId,
      storageBucket: firebaseStorageBucket,
      measurementId: firebaseMeasurementId,
    );

    return AppConfig(
      flavor: flavor,
      supabaseUrl: supabaseUrl.trim(),
      supabaseAnonKey: supabaseAnonKey.trim(),
      firebaseOptions: options,
      analyticsEnabled: analyticsEnabled,
      crashlyticsEnabled: crashlyticsEnabled,
    );
  }

  static FirebaseOptions? _firebaseOptionsFromValues({
    required String apiKey,
    required String appId,
    required String messagingSenderId,
    required String projectId,
    String? storageBucket,
    String? measurementId,
  }) {
    if (apiKey.isEmpty ||
        appId.isEmpty ||
        messagingSenderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: (storageBucket ?? '').isEmpty ? null : storageBucket,
      measurementId: (measurementId ?? '').isEmpty ? null : measurementId,
    );
  }
}

Future<Map<String, String>> _loadWebRuntimeConfig() async {
  try {
    final uri = Uri.base.resolve('config.json');
    final resp = await http.get(uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) return {};
    final data = jsonDecode(resp.body);
    if (data is! Map) return {};
    String? pick(String key) => data[key]?.toString().trim();
    return {
      if (pick('appFlavor') != null && pick('appFlavor')!.isNotEmpty)
        'appFlavor': pick('appFlavor')!,
      if (pick('supabaseUrl') != null && pick('supabaseUrl')!.isNotEmpty)
        'supabaseUrl': pick('supabaseUrl')!,
      if (pick('supabaseAnonKey') != null &&
          pick('supabaseAnonKey')!.isNotEmpty)
        'supabaseAnonKey': pick('supabaseAnonKey')!,
      if (pick('firebaseApiKey') != null && pick('firebaseApiKey')!.isNotEmpty)
        'firebaseApiKey': pick('firebaseApiKey')!,
      if (pick('firebaseAppId') != null && pick('firebaseAppId')!.isNotEmpty)
        'firebaseAppId': pick('firebaseAppId')!,
      if (pick('firebaseMessagingSenderId') != null &&
          pick('firebaseMessagingSenderId')!.isNotEmpty)
        'firebaseMessagingSenderId': pick('firebaseMessagingSenderId')!,
      if (pick('firebaseProjectId') != null &&
          pick('firebaseProjectId')!.isNotEmpty)
        'firebaseProjectId': pick('firebaseProjectId')!,
      if (pick('firebaseStorageBucket') != null &&
          pick('firebaseStorageBucket')!.isNotEmpty)
        'firebaseStorageBucket': pick('firebaseStorageBucket')!,
      if (pick('firebaseMeasurementId') != null &&
          pick('firebaseMeasurementId')!.isNotEmpty)
        'firebaseMeasurementId': pick('firebaseMeasurementId')!,
    };
  } catch (_) {
    return {};
  }
}
