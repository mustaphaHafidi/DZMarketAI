import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'package:dzmarket/src/services/app_logger.dart';

class CrashlyticsService {
  CrashlyticsService._();
  static final CrashlyticsService instance = CrashlyticsService._();

  bool _enabled = false;

  bool get isEnabled => _enabled;

  void configure({required bool enabled}) {
    _enabled = enabled && !kDebugMode && !kIsWeb;
    if (_enabled) {
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      AppLogger.info('Crashlytics enabled');
    } else {
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
    }
  }

  void recordFlutterError(FlutterErrorDetails details) {
    if (!_enabled) return;
    FirebaseCrashlytics.instance.recordFlutterError(details);
  }

  Future<void> recordError(Object error, StackTrace stack, {bool fatal = false}) async {
    if (!_enabled) return;
    await FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
  }
}
