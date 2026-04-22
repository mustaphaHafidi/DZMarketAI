enum AppNotificationCategory { chat, offer, order, system }

AppNotificationCategory appNotificationCategoryFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'chat':
      return AppNotificationCategory.chat;
    case 'offer':
      return AppNotificationCategory.offer;
    case 'order':
      return AppNotificationCategory.order;
    default:
      return AppNotificationCategory.system;
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.category,
    required this.titleI18n,
    required this.bodyI18n,
    required this.payload,
    required this.createdAt,
    this.readAt,
  });

  final int id;
  final String userId;
  final AppNotificationCategory category;
  final String titleI18n;
  final String bodyI18n;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  Map<String, String> interpolationParams() {
    final params = <String, String>{};
    payload.forEach((key, value) {
      if (value == null) return;
      if (value is Map || value is List) return;
      params[key] = value.toString();
    });
    return params;
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final payloadRaw = json['payload'];
    final payload = payloadRaw is Map<String, dynamic>
        ? payloadRaw
        : <String, dynamic>{};
    return AppNotification(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: json['user_id']?.toString() ?? '',
      category: appNotificationCategoryFromString(json['category']?.toString()),
      titleI18n: json['title_i18n']?.toString() ?? 'notifications.system.title',
      bodyI18n: json['body_i18n']?.toString() ?? 'notifications.system.body',
      payload: payload,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      readAt: DateTime.tryParse(json['read_at']?.toString() ?? ''),
    );
  }
}

class NotificationPreferences {
  const NotificationPreferences({
    required this.userId,
    this.enableChat = true,
    this.enableOffer = true,
    this.enableOrder = true,
    this.enableSystem = true,
    this.muteUntil,
  });

  final String userId;
  final bool enableChat;
  final bool enableOffer;
  final bool enableOrder;
  final bool enableSystem;
  final DateTime? muteUntil;

  bool get isMutedNow =>
      muteUntil != null && muteUntil!.isAfter(DateTime.now());

  NotificationPreferences copyWith({
    bool? enableChat,
    bool? enableOffer,
    bool? enableOrder,
    bool? enableSystem,
    DateTime? muteUntil,
    bool clearMuteUntil = false,
  }) {
    return NotificationPreferences(
      userId: userId,
      enableChat: enableChat ?? this.enableChat,
      enableOffer: enableOffer ?? this.enableOffer,
      enableOrder: enableOrder ?? this.enableOrder,
      enableSystem: enableSystem ?? this.enableSystem,
      muteUntil: clearMuteUntil ? null : (muteUntil ?? this.muteUntil),
    );
  }

  Map<String, dynamic> toUpsertMap() {
    return {
      'user_id': userId,
      'enable_chat': enableChat,
      'enable_offer': enableOffer,
      'enable_order': enableOrder,
      'enable_system': enableSystem,
      'mute_until': muteUntil?.toUtc().toIso8601String(),
    };
  }

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      userId: json['user_id']?.toString() ?? '',
      enableChat: json['enable_chat'] as bool? ?? true,
      enableOffer: json['enable_offer'] as bool? ?? true,
      enableOrder: json['enable_order'] as bool? ?? true,
      enableSystem: json['enable_system'] as bool? ?? true,
      muteUntil: DateTime.tryParse(json['mute_until']?.toString() ?? ''),
    );
  }
}
