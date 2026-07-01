import 'dart:async';

import 'package:dzmarket/src/services/app_logger.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    await PushNotificationService.showRemoteMessage(message);
  } catch (_) {
    // Ignore background notification errors.
  }
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _staticLocalReady = false;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _started = false;

  Future<void> start() async {
    if (_started || kIsWeb) return;
    _started = true;
    await _initLocalNotifications();
    await _requestPermissions();
    await _syncCurrentToken();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) {
      unawaited(_upsertToken(token));
    });
    FirebaseMessaging.onMessage.listen((message) {
      unawaited(showRemoteMessage(message));
    });
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      unawaited(_syncCurrentToken());
    });
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
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

  Future<void> _syncCurrentToken() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _upsertToken(token);
    } catch (error, stackTrace) {
      AppLogger.warn(
        'Push token sync failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
    await Supabase.instance.client.from('device_tokens').upsert({
      'user_id': user.id,
      'token': token,
      'platform': platform,
      'locale': locale,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
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

    final android = AndroidNotificationDetails(
      'dzmarket_push',
      'DZMarket push',
      channelDescription: 'Push DZMarket',
      importance: Importance.max,
      priority: Priority.high,
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

  static bool _isReadyForDisplay() => !kIsWeb;

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
