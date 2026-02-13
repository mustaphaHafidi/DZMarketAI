import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dzmarket/src/services/connectivity_service.dart';
import 'package:flutter/foundation.dart';

class NetworkPreferencesService {
  NetworkPreferencesService._();
  static final NetworkPreferencesService instance =
      NetworkPreferencesService._();

  static const String lowDataPreferenceKey = 'low_data_mode';

  final ValueNotifier<bool> lowDataMode = ValueNotifier<bool>(false);
  bool _initialized = false;
  ConnectivityService? _connectivityService;
  VoidCallback? _connectivityListener;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
  }

  Future<void> setLowDataMode(
    bool enabled, {
    bool persistLocally = true,
  }) async {
    // Kept for backward compatibility.
    // App behavior is automatic when bound to connectivity.
    if (_connectivityService != null) return;
    lowDataMode.value = enabled;
  }

  void bindToConnectivity(ConnectivityService connectivityService) {
    if (_connectivityService != null && _connectivityListener != null) {
      _connectivityService!.activeConnections.removeListener(
        _connectivityListener!,
      );
    }
    _connectivityService = connectivityService;
    _connectivityListener = () {
      _applyFromConnections(connectivityService.activeConnections.value);
    };
    connectivityService.activeConnections.addListener(_connectivityListener!);
    _applyFromConnections(connectivityService.activeConnections.value);
  }

  void _applyFromConnections(Set<ConnectivityResult> connections) {
    final nextValue = _computeLowDataMode(connections);
    if (lowDataMode.value != nextValue) {
      lowDataMode.value = nextValue;
    }
  }

  bool _computeLowDataMode(Set<ConnectivityResult> connections) {
    final onlineConnections = connections
        .where((item) => item != ConnectivityResult.none)
        .toSet();
    if (onlineConnections.isEmpty) return true;
    if (onlineConnections.contains(ConnectivityResult.wifi) ||
        onlineConnections.contains(ConnectivityResult.ethernet)) {
      return false;
    }
    // Mobile/VPN/Bluetooth/other: keep media lighter by default.
    return true;
  }

  Future<void> applyProfilePreferences(
    Map<String, dynamic>? preferences, {
    bool persistLocally = true,
  }) async {
    // Deprecated for manual setting.
    // Auto mode is driven by network condition only.
    return;
  }

  Map<String, dynamic> mergeIntoPreferences(Map<String, dynamic>? current) {
    return Map<String, dynamic>.from(current ?? const {});
  }

  int get listImageMemCacheWidth => lowDataMode.value ? 640 : 1600;
  int get listImageMemCacheHeight => lowDataMode.value ? 640 : 1600;
  int get detailImageMemCacheWidth => lowDataMode.value ? 900 : 2200;
  int get detailImageMemCacheHeight => lowDataMode.value ? 900 : 2200;
  Duration get imageFadeInDuration =>
      lowDataMode.value ? Duration.zero : const Duration(milliseconds: 180);
  Duration get imageFadeOutDuration =>
      lowDataMode.value ? Duration.zero : const Duration(milliseconds: 120);
}
