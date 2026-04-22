import 'dart:async';

import 'package:dzmarket/src/models/app_notification.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/notification_inbox_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<NotificationPreferences>? _prefsSub;
  GlobalKey<ScaffoldMessengerState>? _messengerKey;
  final Set<int> _shownNotificationIds = <int>{};
  final NotificationInboxService _inboxService = NotificationInboxService();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  NotificationPreferences _prefs = const NotificationPreferences(userId: '');
  bool _localNotificationsReady = false;
  bool _started = false;

  void start(GlobalKey<ScaffoldMessengerState> messengerKey) {
    _messengerKey = messengerKey;
    if (_started) return;
    _started = true;
    unawaited(_initLocalNotifications());
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      _subscribe();
    });
    _subscribe();
  }

  Future<void> _initLocalNotifications() async {
    if (kIsWeb) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    try {
      await _localNotifications.initialize(settings);
      await _requestPermissions();
      _localNotificationsReady = true;
    } catch (_) {
      _localNotificationsReady = false;
    }
  }

  Future<void> _requestPermissions() async {
    final androidImpl = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();

    final iosImpl = _localNotifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

    final macImpl = _localNotifications
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    await macImpl?.requestPermissions(alert: true, badge: true, sound: true);
  }

  void _subscribe() {
    _channel?.unsubscribe();
    _channel = null;
    _prefsSub?.cancel();
    _shownNotificationIds.clear();
    _prefs = const NotificationPreferences(userId: '');

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _prefsSub = _inboxService.watchPreferences().listen((prefs) {
      _prefs = prefs;
    });

    _channel = Supabase.instance.client
        .channel('public:notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notification_events',
          callback: (payload) {
            _handleNotificationInsert(payload, userId);
          },
        )
        .subscribe();
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _prefsSub?.cancel();
    await _channel?.unsubscribe();
  }

  void notifyLocal(String title, String body) {
    _showSnack(title, body);
    final id = DateTime.now().millisecondsSinceEpoch % 2147483647;
    unawaited(_showLocalNotification(id: id, title: title, body: body));
  }

  void _showSnack(String title, String body) {
    if (title.trim().isEmpty && body.trim().isEmpty) return;
    _messengerKey?.currentState?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(body),
          ],
        ),
      ),
    );
  }

  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_localNotificationsReady || kIsWeb) return;
    final android = AndroidNotificationDetails(
      'dzmarket_events',
      'DZMarket notifications',
      channelDescription: 'Messages, offres et commandes',
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
    await _localNotifications.show(
      id,
      title,
      body,
      details,
      payload: 'notification_event',
    );
  }

  bool _isCategoryEnabled(AppNotificationCategory category) {
    if (_prefs.isMutedNow) return false;
    switch (category) {
      case AppNotificationCategory.chat:
        return _prefs.enableChat;
      case AppNotificationCategory.offer:
        return _prefs.enableOffer;
      case AppNotificationCategory.order:
        return _prefs.enableOrder;
      case AppNotificationCategory.system:
        return _prefs.enableSystem;
    }
  }

  void _handleNotificationInsert(PostgresChangePayload payload, String userId) {
    final newRow = payload.newRecord;
    if (newRow['user_id']?.toString() != userId) return;

    final notification = AppNotification.fromJson(newRow);
    if (_shownNotificationIds.contains(notification.id)) return;
    _shownNotificationIds.add(notification.id);
    if (!_isCategoryEnabled(notification.category)) return;

    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    final title = L10n.trLocale(
      locale,
      notification.titleI18n,
      fallback: 'Notification',
    );
    final body = _bodyText(notification, locale);
    _showSnack(title, body);
    unawaited(
      _showLocalNotification(id: notification.id, title: title, body: body),
    );
  }

  String _bodyText(AppNotification notification, String locale) {
    final payload = notification.payload;
    final amountText = _amountText(payload['amount']);
    final orderId = payload['order_id']?.toString();
    final statusKey = payload['status_i18n']?.toString();
    final statusText = statusKey == null
        ? (payload['status']?.toString() ?? '')
        : L10n.trLocale(
            locale,
            statusKey,
            fallback: payload['status']?.toString(),
          );
    final snippet = payload['snippet']?.toString();
    final params = notification.interpolationParams()
      ..addAll({
        'amount': amountText,
        'id': orderId ?? '',
        'status': statusText,
        'snippet': snippet ?? '',
      });
    final raw = L10n.trLocale(
      locale,
      notification.bodyI18n,
      fallback: notification.bodyI18n,
      params: params,
    );
    var text = raw;
    params.forEach((key, value) {
      text = text.replaceAll('{$key}', value);
    });
    return text;
  }

  String _amountText(Object? amountRaw) {
    if (amountRaw == null) return '0';
    final amountNum = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw.toString());
    if (amountNum == null) return amountRaw.toString();
    return amountNum.toStringAsFixed(0);
  }
}
