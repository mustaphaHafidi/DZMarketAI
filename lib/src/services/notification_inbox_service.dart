import 'dart:async';

import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/app_notification.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationInboxService {
  NotificationInboxService();

  SupabaseClient get _client => supabase;

  Stream<List<AppNotification>> watchNotifications({int limit = 150}) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return Stream.value(const <AppNotification>[]);
    return _client
        .from(SupabaseTables.notificationEvents)
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(AppNotification.fromJson).toList());
  }

  Stream<int> watchUnreadCount({int limit = 150}) {
    return watchNotifications(
      limit: limit,
    ).map((items) => items.where((n) => n.isUnread).length).distinct();
  }

  Future<void> markRead(int notificationId) async {
    if (notificationId <= 0) return;
    await _client.rpc(
      'mark_notification_read',
      params: {'p_notification_id': notificationId},
    );
  }

  Future<int> markAllRead() async {
    final result = await _client.rpc('mark_all_notifications_read');
    if (result is int) return result;
    if (result is num) return result.toInt();
    return 0;
  }

  Stream<NotificationPreferences> watchPreferences() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return Stream.value(
        const NotificationPreferences(userId: '', muteUntil: null),
      );
    }
    return _client
        .from(SupabaseTables.notificationPreferences)
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .limit(1)
        .map((rows) {
          if (rows.isEmpty) return NotificationPreferences(userId: userId);
          return NotificationPreferences.fromJson(rows.first);
        });
  }

  Future<void> savePreferences(NotificationPreferences preferences) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');
    await _client
        .from(SupabaseTables.notificationPreferences)
        .upsert(preferences.copyWith().toUpsertMap(), onConflict: 'user_id');
  }

  Future<void> muteFor(Duration duration) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');
    final until = DateTime.now().toUtc().add(duration);
    await _client.from(SupabaseTables.notificationPreferences).upsert({
      'user_id': userId,
      'mute_until': until.toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<void> clearMute() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');
    await _client.from(SupabaseTables.notificationPreferences).upsert({
      'user_id': userId,
      'mute_until': null,
    }, onConflict: 'user_id');
  }
}
