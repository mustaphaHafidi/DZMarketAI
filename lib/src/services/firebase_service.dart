import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:dzmarket/src/config/app_config.dart';
import 'package:dzmarket/src/services/app_logger.dart';
import 'package:dzmarket/src/services/analytics_service.dart';
import 'package:dzmarket/src/services/crashlytics_service.dart';

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  bool _initialized = false;
  bool _enabled = false;

  bool get isInitialized => _initialized;
  bool get isEnabled => _enabled;

  Future<void> init(AppConfig config) async {
    if (_initialized) return;
    try {
      if (Firebase.apps.isEmpty) {
        if (kIsWeb) {
          if (config.firebaseOptions == null) {
            AppLogger.warn('Firebase options missing for web; skipping init.');
            _initialized = true;
            _enabled = false;
            return;
          }
          await Firebase.initializeApp(options: config.firebaseOptions);
        } else {
          await Firebase.initializeApp();
        }
      }
      _initialized = true;
      _enabled = Firebase.apps.isNotEmpty;
    } catch (error, stackTrace) {
      AppLogger.warn('Firebase init failed', error: error, stackTrace: stackTrace);
      _initialized = true;
      _enabled = false;
      return;
    }

    AnalyticsService.instance.configure(enabled: config.analyticsEnabled);
    CrashlyticsService.instance.configure(enabled: config.crashlyticsEnabled);
  }
}
