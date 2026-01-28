import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

/// Loads translations from Supabase (table: translations) and serves them by key/locale.
/// Table shape: key text, locale text (e.g. 'fr', 'ar'), text text.
class TranslationService {
  TranslationService._();
  static final instance = TranslationService._();

  final Map<String, Map<String, String>> _cache = {};

  Future<void> load() async {
    try {
      final rows = await RateLimiter.instance.run(
        'translations.select',
        () => supabase.from('translations').select(),
      );
      _cache.clear();
      for (final row in rows) {
        final key = row['key'] as String? ?? '';
        final locale = row['locale'] as String? ?? '';
        final text = row['text'] as String? ?? '';
        if (key.isEmpty || locale.isEmpty) continue;
        _cache.putIfAbsent(locale, () => {})[key] = text;
      }
    } catch (_) {
      // Fail quietly; app will fall back to hardcoded strings.
    }
  }

  String? translate(String locale, String key) {
    return _cache[locale]?[key];
  }
}
