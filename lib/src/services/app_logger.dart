import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class AppLogger {
  static void info(String message, {Object? error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      debugPrint(message);
    }
    developer.log(message, name: 'DZMarket', error: error, stackTrace: stackTrace);
  }

  static void warn(String message, {Object? error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      debugPrint('WARN: $message');
    }
    developer.log(
      message,
      name: 'DZMarket',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
