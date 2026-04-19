import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/translation_service.dart';
import 'package:flutter_test/flutter_test.dart';

bool _looksLikeRawKey(String value) {
  final normalized = value
      .replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'),
        '',
      )
      .trim()
      .toLowerCase();
  return RegExp(r'^[a-z0-9_-]+(?:\.[a-z0-9_-]+)+$').hasMatch(normalized);
}

bool _looksCorruptText(String value) {
  if (value.trim().isEmpty) return true;
  if (value.contains('\uFFFD') || value.contains('�')) return true;
  if (value.contains('Ã') || value.contains('Â')) return true;
  if (RegExp(r'[A-Za-z]\?[A-Za-z]').hasMatch(value)) return true;
  return false;
}

void _expectLocalizedValue({required String locale, required String key}) {
  final value = L10n.trLocale(locale, key, fallback: '__missing__');
  expect(
    value,
    isNot('__missing__'),
    reason: 'Missing runtime translation for [$locale] $key',
  );
  expect(
    value,
    isNot(key),
    reason: 'Raw key leaked for [$locale] $key => "$value"',
  );
  expect(
    _looksLikeRawKey(value),
    isFalse,
    reason: 'Key-like placeholder leaked for [$locale] $key => "$value"',
  );
  expect(
    _looksCorruptText(value),
    isFalse,
    reason: 'Corrupt text detected for [$locale] $key => "$value"',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TranslationService.instance.load();
  });

  const criticalKeys = <String>[
    'auth.sign_in.cta',
    'auth.sign_up.cta',
    'auth.forgot_password',
    'auth.reset_password.title',
    'auth.reset_password.send',
    'listing.sell',
    'listing.search_hint',
    'listing.filters.all_filters',
    'listing.filters.all_categories',
    'listing.filters.price_quick',
    'listing.add.title',
    'listing.add.step_photos',
    'listing.add.category_label',
    'listing.add.title_label',
    'listing.add.description_label',
    'listing.add.step_price',
    'listing.add.select_wilaya',
    'listing.add.delivery_toggle',
    'listing.add.step_preview',
    'notifications.title',
    'notifications.open_settings',
    'notifications.preferences_title',
    'notifications.filter_all',
    'notifications.filter_unread',
    'notifications.cat_chat',
    'notifications.cat_offer',
    'notifications.chat.title',
    'notifications.offer.title',
    'chat.title',
    'chat.tab_messages',
    'chat.tab_archived',
    'seller_orders.title',
    'seller_orders.generate_label',
    'seller_orders.open_label',
    'seller_orders.returns_dzmarket_title',
    'seller_orders.returns_scope_note',
    'seller_dashboard.title',
    'seller_dashboard.section_overview',
    'shipments.title',
    'shipments.open_label',
    'shipments.label_retention_note',
    'profile.title',
    'profile.dashboard',
    'profile.my_listings',
    'profile.shipments_board',
    'profile.courier_settings',
  ];

  test('critical FR translations are readable at runtime', () {
    for (final key in criticalKeys) {
      _expectLocalizedValue(locale: 'fr', key: key);
    }
  });

  test('critical AR translations are readable at runtime', () {
    for (final key in criticalKeys) {
      _expectLocalizedValue(locale: 'ar', key: key);
    }
  });
}
