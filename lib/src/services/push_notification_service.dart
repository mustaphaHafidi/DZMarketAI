import 'dart:async';

import 'package:dzmarket/src/services/app_logger.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    if (PushNotificationService.isDzMarketEventPush(message)) return;
    await PushNotificationService.showRemoteMessage(message);
  } catch (_) {
    // Ignore background notification errors.
  }
}

class PushNotificationService with WidgetsBindingObserver {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _staticLocalReady = false;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;
  Timer? _tokenSyncTimer;
  Timer? _tokenRetryTimer;
  int _tokenRetryAttempts = 0;
  bool _started = false;

  Future<void> start() async {
    if (_started || kIsWeb) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    await _initLocalNotifications();
    await _requestPermissions();
    await _configureForegroundPresentation();
    await _syncCurrentToken();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) {
      unawaited(_upsertToken(token));
    });
    FirebaseMessaging.onMessage.listen((message) {
      if (!_shouldMirrorForegroundMessageLocally(message)) return;
      unawaited(showRemoteMessage(message));
    });
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      unawaited(_syncCurrentToken());
    });
    _tokenSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_syncCurrentToken());
    });
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _tokenSyncTimer?.cancel();
    _tokenRetryTimer?.cancel();
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncCurrentToken());
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    try {
      await _localNotifications.initialize(settings);
      _staticLocalReady = true;
    } catch (error, stackTrace) {
      AppLogger.warn(
        'Push local notification init failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _requestPermissions() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    AppLogger.info('Push permission: ${settings.authorizationStatus}');
  }

  Future<void> _configureForegroundPresentation() async {
    try {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
    } catch (error, stackTrace) {
      AppLogger.warn(
        'Push foreground presentation setup failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _syncCurrentToken() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _resetTokenRetry();
      return;
    }
    try {
      final token = await _currentFcmToken();
      if (token == null || token.isEmpty) {
        _scheduleTokenSyncRetry();
        return;
      }
      await _upsertToken(token);
      _resetTokenRetry();
    } catch (error, stackTrace) {
      AppLogger.warn(
        'Push token sync failed',
        error: error,
        stackTrace: stackTrace,
      );
      _scheduleTokenSyncRetry();
    }
  }

  Future<String?> _currentFcmToken() async {
    if (requiresApnsTokenBeforeFcm(defaultTargetPlatform)) {
      final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      if (apnsToken == null || apnsToken.isEmpty) {
        AppLogger.info('APNs token unavailable; retrying push token sync.');
        return null;
      }
    }
    return FirebaseMessaging.instance.getToken();
  }

  void _scheduleTokenSyncRetry() {
    if (Supabase.instance.client.auth.currentUser == null) return;
    if (_tokenRetryTimer?.isActive ?? false) return;
    final delay = tokenSyncRetryDelay(_tokenRetryAttempts);
    _tokenRetryAttempts += 1;
    _tokenRetryTimer = Timer(delay, () {
      unawaited(_syncCurrentToken());
    });
  }

  void _resetTokenRetry() {
    _tokenRetryTimer?.cancel();
    _tokenRetryTimer = null;
    _tokenRetryAttempts = 0;
  }

  Future<void> _upsertToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || token.isEmpty) return;
    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'unknown',
    };
    await Supabase.instance.client.rpc(
      'register_device_token',
      params: {'p_token': token, 'p_platform': platform, 'p_locale': locale},
    );
  }

  static Future<void> showRemoteMessage(RemoteMessage message) async {
    final title =
        message.notification?.title ??
        _resolveDataValue(message.data['title']) ??
        _resolveDataValue(message.data['title_key']) ??
        'DZMarket';
    final body =
        message.notification?.body ??
        _resolveDataValue(message.data['body']) ??
        _resolveBodyFromData(message.data);
    if (body.trim().isEmpty) return;
    if (!_isReadyForDisplay()) return;
    if (!_staticLocalReady) {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const darwinSettings = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );
      await _localNotifications.initialize(settings);
      _staticLocalReady = true;
    }

    const android = AndroidNotificationDetails(
      'dzmarket_push',
      'DZMarket push',
      channelDescription: 'Push DZMarket',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
    final id = DateTime.now().millisecondsSinceEpoch % 2147483647;
    await _localNotifications.show(id, title, body, details);
  }

  @visibleForTesting
  static bool shouldMirrorForegroundMessageLocally({
    required TargetPlatform platform,
    required bool hasNotificationPayload,
  }) {
    final isAppleForegroundPlatform =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    if (!isAppleForegroundPlatform) return true;
    // On Apple platforms, the OS already presents foreground alerts when the
    // remote message carries a native notification payload.
    return !hasNotificationPayload;
  }

  @visibleForTesting
  static bool requiresApnsTokenBeforeFcm(TargetPlatform platform) {
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }

  @visibleForTesting
  static Duration tokenSyncRetryDelay(int attempt) {
    const delays = [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
    ];
    if (attempt < 0) return delays.first;
    if (attempt >= delays.length) return delays.last;
    return delays[attempt];
  }

  static bool _shouldMirrorForegroundMessageLocally(RemoteMessage message) {
    return shouldMirrorForegroundMessageLocally(
      platform: defaultTargetPlatform,
      hasNotificationPayload: message.notification != null,
    );
  }

  static bool _isReadyForDisplay() => !kIsWeb;

  static bool isDzMarketEventPush(RemoteMessage message) {
    final id = _resolveDataValue(message.data['notification_id']);
    return id != null;
  }

  static String? _resolveDataValue(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static String _resolveBodyFromData(Map<String, dynamic> data) {
    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    final key = _resolveDataValue(data['body_key']);
    if (key == null) return '';
    return L10n.trLocale(
      locale,
      key,
      fallback: key,
      params: data.map((k, v) => MapEntry(k, v == null ? '' : v.toString())),
    );
  }
}
