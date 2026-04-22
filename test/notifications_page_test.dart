import 'dart:async';

import 'package:dzmarket/src/features/notifications/notifications_page.dart';
import 'package:dzmarket/src/models/app_notification.dart';
import 'package:dzmarket/src/services/notification_inbox_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNotificationInboxService extends NotificationInboxService {
  _FakeNotificationInboxService({
    required List<AppNotification> notifications,
    NotificationPreferences preferences = const NotificationPreferences(
      userId: 'user-1',
    ),
  }) : _notifications = notifications {
    _preferencesController.add(preferences);
    _latestPreferences = preferences;
  }

  final List<AppNotification> _notifications;
  final StreamController<NotificationPreferences> _preferencesController =
      StreamController<NotificationPreferences>.broadcast();
  late NotificationPreferences _latestPreferences;

  @override
  Stream<List<AppNotification>> watchNotifications({int limit = 150}) {
    return Stream.value(_notifications);
  }

  @override
  Stream<NotificationPreferences> watchPreferences() {
    return _preferencesController.stream;
  }

  @override
  Future<void> savePreferences(NotificationPreferences preferences) async {
    _latestPreferences = preferences;
    _preferencesController.add(preferences);
  }

  @override
  Future<void> muteFor(Duration duration) async {
    _latestPreferences = _latestPreferences.copyWith(
      muteUntil: DateTime.now().add(duration),
    );
    _preferencesController.add(_latestPreferences);
  }

  @override
  Future<void> clearMute() async {
    _latestPreferences = _latestPreferences.copyWith(clearMuteUntil: true);
    _preferencesController.add(_latestPreferences);
  }

  @override
  Future<int> markAllRead() async =>
      _notifications.where((n) => n.isUnread).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'notifications page keeps inbox simple and opens settings sheet',
    (tester) async {
      final service = _FakeNotificationInboxService(
        notifications: [
          AppNotification(
            id: 1,
            userId: 'user-1',
            category: AppNotificationCategory.order,
            titleI18n: 'notifications.order.title',
            bodyI18n: 'notifications.order.created_seller',
            payload: {'order_id': '44'},
            createdAt: DateTime.fromMillisecondsSinceEpoch(1713517200000),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          home: NotificationsPage(service: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Toutes'), findsOneWidget);
      expect(find.text('Non lues'), findsOneWidget);
      expect(find.text('Catégories'), findsNothing);
      expect(find.text('Préférences notifications'), findsNothing);

      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Préférences notifications'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Commandes'), findsOneWidget);
      expect(find.text('Silence 8h'), findsOneWidget);
    },
  );

  testWidgets(
    'notifications page interpolates system notification payload values',
    (tester) async {
      final service = _FakeNotificationInboxService(
        notifications: [
          AppNotification(
            id: 2,
            userId: 'user-1',
            category: AppNotificationCategory.system,
            titleI18n: 'notifications.system.title',
            bodyI18n: 'notifications.system.courier_credentials_invalid',
            payload: {'order_id': '146', 'courier_name': 'Yalidine Express'},
            createdAt: DateTime.fromMillisecondsSinceEpoch(1713517200000),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          home: NotificationsPage(service: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Yalidine Express'), findsOneWidget);
      expect(find.textContaining('commande #146'), findsOneWidget);
      expect(find.textContaining('{courier_name}'), findsNothing);
      expect(find.textContaining('{order_id}'), findsNothing);
    },
  );

  testWidgets(
    'notifications page interpolates legacy raw notification templates',
    (tester) async {
      final service = _FakeNotificationInboxService(
        notifications: [
          AppNotification(
            id: 3,
            userId: 'user-1',
            category: AppNotificationCategory.system,
            titleI18n: 'notifications.system.title',
            bodyI18n:
                "Le compte transporteur {courier_name} de la commande #{order_id} n'est plus valide.",
            payload: {'order_id': '146', 'courier_name': 'Yalidine Express'},
            createdAt: DateTime.fromMillisecondsSinceEpoch(1713517200000),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          home: NotificationsPage(service: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Yalidine Express'), findsOneWidget);
      expect(find.textContaining('commande #146'), findsOneWidget);
      expect(find.textContaining('{courier_name}'), findsNothing);
      expect(find.textContaining('{order_id}'), findsNothing);
    },
  );
}
