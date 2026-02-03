import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import 'package:dzmarket/src/services/app_logger.dart';

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  bool _enabled = false;

  bool get isEnabled => _enabled;

  void configure({required bool enabled}) {
    _enabled = enabled && !kDebugMode;
    if (_enabled) {
      AppLogger.info('Analytics enabled');
    }
  }

  FirebaseAnalyticsObserver? createObserver() {
    if (!_enabled) return null;
    return FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance);
  }

  Future<void> logEvent(
    String name, {
    Map<String, Object?>? parameters,
  }) async {
    if (!_enabled) return;
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters?.map(
          (key, value) => MapEntry(key, value ?? ''),
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.warn('Analytics event failed: $name',
          error: error, stackTrace: stackTrace);
    }
  }
}
