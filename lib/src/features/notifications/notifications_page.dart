import 'package:dzmarket/src/features/chat/chat_room_page.dart';
import 'package:dzmarket/src/models/app_notification.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/notification_inbox_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.service});

  final NotificationInboxService? service;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final NotificationInboxService _service;
  bool _unreadOnly = false;
  bool _busy = false;
  static const Map<String, Map<String, String>> _notificationFallbacks = {
    'fr': {
      'notifications.title': 'Notifications',
      'notifications.empty': 'Aucune notification pour le moment.',
      'notifications.mark_all_read': 'Tout marquer comme lu',
      'notifications.mark_all_done':
          '{count} notifications marquees comme lues.',
      'notifications.filter_all': 'Toutes',
      'notifications.filter_unread': 'Non lues',
      'notifications.open_settings': 'Parametres notifications',
      'notifications.preferences_title': 'Preferences notifications',
      'notifications.pref_chat': 'Messages',
      'notifications.pref_offer': 'Offres',
      'notifications.pref_order': 'Commandes',
      'notifications.pref_system': 'Systeme',
      'notifications.mute_8h': 'Silence 8h',
      'notifications.unmute_now': 'Reactiver',
      'notifications.muted_now': 'Notifications en pause',
      'notifications.active_now': 'Notifications actives',
      'notifications.cat_all': 'Categories',
      'notifications.cat_chat': 'Messages',
      'notifications.cat_offer': 'Offres',
      'notifications.cat_order': 'Commandes',
      'notifications.cat_system': 'Systeme',
      'notifications.chat.title': 'Nouveau message',
      'notifications.chat.new_message': '{snippet}',
      'notifications.chat.system': 'Mise a jour dans une conversation',
      'notifications.offer.title': 'Offre',
      'notifications.offer.new': 'Nouvelle offre: DA {amount}',
      'notifications.offer.counter': 'Contre-offre: DA {amount}',
      'notifications.offer.accepted': 'Offre acceptee: DA {amount}',
      'notifications.offer.rejected': 'Offre refusee',
      'notifications.order.title': 'Commande',
      'notifications.order.created_buyer': 'Commande #{id} creee',
      'notifications.order.created_seller': 'Nouvelle commande #{id}',
      'notifications.order.status': 'Commande #{id}: {status}',
      'notifications.system.title': 'Systeme',
      'notifications.system.body': 'Nouvelle mise a jour systeme',
      'notifications.system.courier_credentials_invalid':
          'Le compte transporteur {courier_name} de la commande #{order_id} n\'est plus valide. Mettez a jour le token puis relancez la generation du bordereau.',
    },
    'ar': {
      'notifications.title':
          '\u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062a',
      'notifications.empty':
          '\u0644\u0627 \u062a\u0648\u062c\u062f \u0625\u0634\u0639\u0627\u0631\u0627\u062a \u062d\u0627\u0644\u064a\u0627\u064b.',
      'notifications.mark_all_read':
          '\u062a\u0639\u064a\u064a\u0646 \u0627\u0644\u0643\u0644 \u0643\u0645\u0642\u0631\u0648\u0621',
      'notifications.mark_all_done':
          '\u062a\u0645 \u062a\u0639\u064a\u064a\u0646 {count} \u0625\u0634\u0639\u0627\u0631 \u0643\u0645\u0642\u0631\u0648\u0621.',
      'notifications.filter_all': '\u0627\u0644\u0643\u0644',
      'notifications.filter_unread':
          '\u063a\u064a\u0631 \u0627\u0644\u0645\u0642\u0631\u0648\u0621\u0629',
      'notifications.open_settings':
          '\u0625\u0639\u062f\u0627\u062f\u0627\u062a \u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062a',
      'notifications.preferences_title':
          '\u062a\u0641\u0636\u064a\u0644\u0627\u062a \u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062a',
      'notifications.pref_chat': '\u0627\u0644\u0631\u0633\u0627\u0626\u0644',
      'notifications.pref_offer': '\u0627\u0644\u0639\u0631\u0648\u0636',
      'notifications.pref_order': '\u0627\u0644\u0637\u0644\u0628\u0627\u062a',
      'notifications.pref_system': '\u0627\u0644\u0646\u0638\u0627\u0645',
      'notifications.mute_8h':
          '\u0643\u062a\u0645 8 \u0633\u0627\u0639\u0627\u062a',
      'notifications.unmute_now':
          '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u062a\u0641\u0639\u064a\u0644',
      'notifications.muted_now':
          '\u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062a \u0645\u062a\u0648\u0642\u0641\u0629 \u0645\u0624\u0642\u062a\u0627\u064b',
      'notifications.active_now':
          '\u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062a \u0645\u0641\u0639\u0644\u0629',
      'notifications.cat_all': '\u0627\u0644\u0641\u0626\u0627\u062a',
      'notifications.cat_chat': '\u0631\u0633\u0627\u0626\u0644',
      'notifications.cat_offer': '\u0639\u0631\u0648\u0636',
      'notifications.cat_order': '\u0637\u0644\u0628\u0627\u062a',
      'notifications.cat_system': '\u0646\u0638\u0627\u0645',
      'notifications.chat.title':
          '\u0631\u0633\u0627\u0644\u0629 \u062c\u062f\u064a\u062f\u0629',
      'notifications.chat.new_message': '{snippet}',
      'notifications.chat.system':
          '\u062a\u062d\u062f\u064a\u062b \u0641\u064a \u0645\u062d\u0627\u062f\u062b\u0629',
      'notifications.offer.title': '\u0639\u0631\u0636',
      'notifications.offer.new':
          '\u0639\u0631\u0636 \u062c\u062f\u064a\u062f: {amount} \u062f\u062c',
      'notifications.offer.counter':
          '\u0639\u0631\u0636 \u0645\u0642\u0627\u0628\u0644: {amount} \u062f\u062c',
      'notifications.offer.accepted':
          '\u062a\u0645 \u0642\u0628\u0648\u0644 \u0627\u0644\u0639\u0631\u0636: {amount} \u062f\u062c',
      'notifications.offer.rejected':
          '\u062a\u0645 \u0631\u0641\u0636 \u0627\u0644\u0639\u0631\u0636',
      'notifications.order.title': '\u0637\u0644\u0628',
      'notifications.order.created_buyer':
          '\u062a\u0645 \u0625\u0646\u0634\u0627\u0621 \u0627\u0644\u0637\u0644\u0628 #{id}',
      'notifications.order.created_seller':
          '\u0637\u0644\u0628 \u062c\u062f\u064a\u062f #{id}',
      'notifications.order.status':
          '\u0627\u0644\u0637\u0644\u0628 #{id}: {status}',
      'notifications.system.title': '\u0627\u0644\u0646\u0638\u0627\u0645',
      'notifications.system.body':
          '\u062a\u062d\u062f\u064a\u062b \u0646\u0638\u0627\u0645 \u062c\u062f\u064a\u062f',
      'notifications.system.courier_credentials_invalid':
          '\u0644\u0645 \u062a\u0639\u062f \u0628\u064a\u0627\u0646\u0627\u062a \u0634\u0631\u0643\u0629 \u0627\u0644\u0634\u062d\u0646 {courier_name} \u0644\u0644\u0637\u0644\u0628 #{order_id} \u0635\u0627\u0644\u062d\u0629. \u062d\u062f\u0651\u062b \u0627\u0644\u0631\u0645\u0632 \u062b\u0645 \u0623\u0639\u062f \u0625\u0646\u0634\u0627\u0621 \u0627\u0644\u0628\u0648\u0644\u064a\u0635\u0629.',
    },
  };

  String _applyParams(String text, Map<String, String>? params) {
    if (params == null || params.isEmpty) return text;
    var value = text;
    params.forEach((k, v) {
      value = value.replaceAll('{$k}', v);
    });
    return value;
  }

  bool _looksCorrupt(String value) {
    if (value.isEmpty) return true;
    if (value.contains('\uFFFD')) return true;
    if (value.contains('\u00C3') ||
        value.contains('\u00D8') ||
        value.contains('\u00D9')) {
      return true;
    }
    if (RegExp(r'[A-Za-z]\?[A-Za-z]').hasMatch(value)) return true;
    if (RegExp(r'^\?{3,}$').hasMatch(value.replaceAll(' ', ''))) return true;
    return false;
  }

  String _fallbackTranslation(
    String key, {
    Map<String, String>? params,
    String? fallback,
  }) {
    final locale = Localizations.localeOf(context).languageCode;
    final byLocale =
        _notificationFallbacks[locale] ?? _notificationFallbacks['fr']!;
    final text =
        byLocale[key] ?? _notificationFallbacks['fr']?[key] ?? fallback ?? key;
    return _applyParams(text, params);
  }

  String _tr(String key, {Map<String, String>? params, String? fallback}) {
    final raw = L10n.tr(context, key, params: params, fallback: fallback);
    final locale = Localizations.localeOf(context).languageCode;
    if (raw == key) {
      return _fallbackTranslation(key, params: params, fallback: fallback);
    }
    // If Arabic is selected but we still got the French fallback string,
    // force the local Arabic fallback to avoid mixed-language UI.
    if (locale == 'ar') {
      final frText = _notificationFallbacks['fr']?[key];
      if (frText != null && raw == frText) {
        return _fallbackTranslation(key, params: params, fallback: fallback);
      }
    }
    if (!_looksCorrupt(raw)) return raw;
    return _fallbackTranslation(key, params: params, fallback: fallback);
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NotificationInboxService();
  }

  Future<void> _markAllRead() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final changed = await _service.markAllRead();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr('notifications.mark_all_done', params: {'count': '$changed'}),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.tr(context, 'common.error'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updatePrefs(NotificationPreferences prefs) async {
    try {
      await _service.savePreferences(prefs);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.tr(context, 'common.error'))));
    }
  }

  Future<void> _openPreferencesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: StreamBuilder<NotificationPreferences>(
            stream: _service.watchPreferences(),
            builder: (context, snap) {
              final prefs =
                  snap.data ?? const NotificationPreferences(userId: '');
              final statusText = prefs.isMutedNow
                  ? _tr('notifications.muted_now')
                  : _tr('notifications.active_now');
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _tr('notifications.preferences_title'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusText,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_tr('notifications.pref_chat')),
                      value: prefs.enableChat,
                      onChanged: (v) =>
                          _updatePrefs(prefs.copyWith(enableChat: v)),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_tr('notifications.pref_offer')),
                      value: prefs.enableOffer,
                      onChanged: (v) =>
                          _updatePrefs(prefs.copyWith(enableOffer: v)),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_tr('notifications.pref_order')),
                      value: prefs.enableOrder,
                      onChanged: (v) =>
                          _updatePrefs(prefs.copyWith(enableOrder: v)),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_tr('notifications.pref_system')),
                      value: prefs.enableSystem,
                      onChanged: (v) =>
                          _updatePrefs(prefs.copyWith(enableSystem: v)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () =>
                              _service.muteFor(const Duration(hours: 8)),
                          icon: const Icon(Icons.bedtime_outlined),
                          label: Text(_tr('notifications.mute_8h')),
                        ),
                        if (prefs.isMutedNow)
                          TextButton(
                            onPressed: _service.clearMute,
                            child: Text(_tr('notifications.unmute_now')),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('notifications.title')),
        actions: [
          IconButton(
            onPressed: _openPreferencesSheet,
            icon: const Icon(Icons.tune_outlined),
            tooltip: _tr('notifications.open_settings'),
          ),
          IconButton(
            onPressed: _busy ? null : _markAllRead,
            icon: const Icon(Icons.done_all_outlined),
            tooltip: _tr('notifications.mark_all_read'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(_tr('notifications.filter_all')),
                  selected: !_unreadOnly,
                  onSelected: (_) => setState(() => _unreadOnly = false),
                ),
                ChoiceChip(
                  label: Text(_tr('notifications.filter_unread')),
                  selected: _unreadOnly,
                  onSelected: (_) => setState(() => _unreadOnly = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AppNotification>>(
              stream: _service.watchNotifications(),
              builder: (context, snapshot) {
                final all = snapshot.data ?? const <AppNotification>[];
                final filtered = all.where((n) {
                  if (_unreadOnly && !n.isUnread) return false;
                  return true;
                }).toList();
                if (filtered.isEmpty) {
                  return Center(child: Text(_tr('notifications.empty')));
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final n = filtered[index];
                    final title = _tr(n.titleI18n, fallback: n.titleI18n);
                    final body = _buildBodyText(context, n);
                    final time = DateFormat(
                      'dd/MM HH:mm',
                    ).format(n.createdAt.toLocal());
                    return ListTile(
                      onTap: () async {
                        final conversationId = n.payload['conversation_id']
                            ?.toString();
                        final productId = n.payload['product_id']?.toString();
                        final navigator = Navigator.of(context);
                        if (n.isUnread) {
                          await _service.markRead(n.id);
                        }
                        if (!mounted) return;
                        if (conversationId != null &&
                            conversationId.isNotEmpty) {
                          await navigator.push(
                            MaterialPageRoute(
                              builder: (_) => ChatRoomPage(
                                conversationId: conversationId,
                                productId: productId,
                              ),
                            ),
                          );
                        }
                      },
                      leading: Icon(_categoryIcon(n.category)),
                      title: Text(
                        title,
                        style: TextStyle(
                          fontWeight: n.isUnread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(body),
                          const SizedBox(height: 4),
                          Text(
                            '$time - ${_categoryLabel(context, n.category)}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      trailing: n.isUnread
                          ? Icon(
                              Icons.circle,
                              size: 10,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(
    BuildContext context,
    AppNotificationCategory category,
  ) {
    switch (category) {
      case AppNotificationCategory.chat:
        return _tr('notifications.cat_chat');
      case AppNotificationCategory.offer:
        return _tr('notifications.cat_offer');
      case AppNotificationCategory.order:
        return _tr('notifications.cat_order');
      case AppNotificationCategory.system:
        return _tr('notifications.cat_system');
    }
  }

  IconData _categoryIcon(AppNotificationCategory category) {
    switch (category) {
      case AppNotificationCategory.chat:
        return Icons.chat_bubble_outline;
      case AppNotificationCategory.offer:
        return Icons.local_offer_outlined;
      case AppNotificationCategory.order:
        return Icons.receipt_long_outlined;
      case AppNotificationCategory.system:
        return Icons.notifications_active_outlined;
    }
  }

  String _buildBodyText(BuildContext context, AppNotification n) {
    final payload = n.payload;
    final statusKey = payload['status_i18n']?.toString();
    final statusText = statusKey == null
        ? (payload['status']?.toString() ?? '')
        : _tr(statusKey, fallback: payload['status']?.toString());
    final amountRaw = payload['amount'];
    final amountNum = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw?.toString() ?? '');
    final amount = amountNum == null ? '0' : amountNum.toStringAsFixed(0);
    final orderId = payload['order_id']?.toString() ?? '';
    final snippet = payload['snippet']?.toString() ?? '';
    final params = n.interpolationParams()
      ..addAll({
        'amount': amount,
        'id': orderId,
        'status': statusText,
        'snippet': snippet,
      });
    final result = _tr(
      n.bodyI18n,
      fallback: n.bodyI18n,
      params: params,
    );
    if (result == n.bodyI18n && snippet.isNotEmpty) {
      return snippet;
    }
    return _applyParams(result, params);
  }
}
