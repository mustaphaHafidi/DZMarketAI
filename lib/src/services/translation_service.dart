import 'dart:convert';

import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/services.dart';

/// Loads translations from Supabase (table: translations) and serves them by key/locale.
/// Table shape: key text, locale text (e.g. 'fr', 'ar'), text text.
class TranslationService {
  TranslationService._();
  static final instance = TranslationService._();

  final Map<String, Map<String, String>> _cache = {};

  Future<void> load() async {
    _cache.clear();
    await _loadAssetLocale('fr');
    await _loadAssetLocale('ar');
    try {
      final rows = await RateLimiter.instance.run(
        'translations.select',
        () => supabase.from('translations').select(),
      );
      for (final row in rows) {
        final key = row['key'] as String? ?? '';
        final locale = row['locale'] as String? ?? '';
        final text = row['text'] as String? ?? '';
        if (key.isEmpty || locale.isEmpty || text.isEmpty) continue;
        _cache.putIfAbsent(locale, () => {})[key] = text;
      }
    } catch (_) {
      // Fail quietly; app will fall back to asset strings.
    }
  }

  Future<void> _loadAssetLocale(String locale) async {
    try {
      final raw = await rootBundle.loadString('assets/i18n/$locale.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final map = <String, String>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is String && value.isNotEmpty) {
          map[entry.key] = value;
        }
      }
      if (map.isNotEmpty) {
        _cache[locale] = map;
      }
    } catch (_) {
      // Ignore; assets might not be present in some test contexts.
    }
  }

  String? translate(String locale, String key) {
    return _cache[locale]?[key];
  }
}
