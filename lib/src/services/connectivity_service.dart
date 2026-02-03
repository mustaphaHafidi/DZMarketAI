import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:dzmarket/src/services/app_logger.dart';

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  StreamSubscription<dynamic>? _subscription;

  Future<void> start() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      isOnline.value = _isOnlineFromResult(initial);
      _subscription = Connectivity()
          .onConnectivityChanged
          .listen((event) => isOnline.value = _isOnlineFromResult(event));
    } catch (error, stackTrace) {
      AppLogger.warn('Connectivity init failed', error: error, stackTrace: stackTrace);
      isOnline.value = true;
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  bool _isOnlineFromResult(dynamic result) {
    if (result is ConnectivityResult) {
      return result != ConnectivityResult.none;
    }
    if (result is List<ConnectivityResult>) {
      return result.any((r) => r != ConnectivityResult.none);
    }
    return true;
  }
}
