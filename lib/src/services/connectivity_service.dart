import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:dzmarket/src/services/app_logger.dart';

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  final ValueNotifier<Set<ConnectivityResult>> activeConnections =
      ValueNotifier<Set<ConnectivityResult>>({
        ConnectivityResult.none,
      });
  StreamSubscription<dynamic>? _subscription;

  Future<void> start() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      final initialResults = _resultsFromEvent(initial);
      activeConnections.value = initialResults;
      isOnline.value = _isOnlineFromResults(initialResults);
      _subscription = Connectivity().onConnectivityChanged.listen((event) {
        final results = _resultsFromEvent(event);
        activeConnections.value = results;
        isOnline.value = _isOnlineFromResults(results);
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'Connectivity init failed',
        error: error,
        stackTrace: stackTrace,
      );
      isOnline.value = true;
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  Set<ConnectivityResult> _resultsFromEvent(dynamic result) {
    if (result is ConnectivityResult) {
      return {result};
    }
    if (result is List<ConnectivityResult>) {
      if (result.isEmpty) return {ConnectivityResult.none};
      return result.toSet();
    }
    return {ConnectivityResult.none};
  }

  bool _isOnlineFromResults(Set<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }
}
