import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FirebaseWebConfigLoader {
  static const _env = String.fromEnvironment('APP_ENV', defaultValue: 'prod');

  static Future<FirebaseOptions?> load() async {
    if (!kIsWeb) return null;
    try {
      final raw = await rootBundle.loadString('web/config.json');
      final data = jsonDecode(raw);
      if (data is! Map) return null;

      final envMap = data[_env] ?? data['prod'];
      if (envMap is! Map) return null;

      String? pick(String key) => envMap[key]?.toString();
      final placeholder = envMap['__PLACEHOLDER__'] == true;
      if (placeholder) return null;

      final apiKey = pick('apiKey') ?? '';
      final appId = pick('appId') ?? '';
      final senderId = pick('messagingSenderId') ?? '';
      final projectId = pick('projectId') ?? '';

      if (apiKey.isEmpty ||
          appId.isEmpty ||
          senderId.isEmpty ||
          projectId.isEmpty) {
        return null;
      }

      return FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: projectId,
        authDomain: pick('authDomain'),
        storageBucket: pick('storageBucket'),
        measurementId: pick('measurementId'),
      );
    } catch (_) {
      return null;
    }
  }
}
