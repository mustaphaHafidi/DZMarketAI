import 'dart:convert';

import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/services.dart';

/// Loads translations from Supabase (table: translations) and serves them by key/locale.
/// Table shape: key text, locale text (e.g. 'fr', 'ar'), text text.
class TranslationService {
  TranslationService._();
  static final instance = TranslationService._();
  static const Set<String> _assetAuthoritativeKeys = {
    'courier_settings.web_notice',
    'profile.account_deletion',
    'profile.account_deletion_hint',
    'profile.account_deletion_in_progress',
    'profile.account_deletion_last_request',
    'profile.account_deletion_requested_at',
    'profile.account_deletion_processed_at',
    'profile.account_deletion_admin_note',
    'profile.account_deletion_open_hint',
    'profile.delete_account',
    'profile.delete_account_confirm_title',
    'profile.delete_account_cta',
  };

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
        final locale = _normalizeLocaleCode(row['locale'] as String? ?? '');
        final text = row['text'] as String? ?? '';
        if (key.isEmpty || locale.isEmpty || text.isEmpty) continue;
        if (_looksCorrupt(locale, text) || _looksPlaceholderText(key, text)) {
          continue;
        }
        if (_assetAuthoritativeKeys.contains(key) &&
            (_cache[locale]?[key]?.isNotEmpty ?? false)) {
          continue;
        }
        _cache.putIfAbsent(locale, () => {})[key] = text;
      }
    } catch (_) {
      // Fail quietly; app will fall back to asset strings.
    }
  }

  Future<void> _loadAssetLocale(String locale) async {
    final assetPaths = [
      'assets/i18n/$locale.json',
      'assets/assets/i18n/$locale.json',
    ];
    for (final path in assetPaths) {
      try {
        final raw = await rootBundle.loadString(path);
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
          return;
        }
      } catch (_) {
        // Try the next asset path.
      }
    }
  }

  String? translate(String locale, String key) {
    final normalized = _normalizeLocaleCode(locale);
    if (normalized == 'fr' ||
        normalized.startsWith('fr_') ||
        normalized.startsWith('fr-')) {
      return _cache['fr']?[key];
    }
    if (normalized == 'ar' ||
        normalized.startsWith('ar_') ||
        normalized.startsWith('ar-')) {
      return _cache['ar']?[key];
    }
    return _cache['fr']?[key] ?? _cache[normalized]?[key];
  }

  String _normalizeLocaleCode(String locale) {
    final normalized = locale.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    if (normalized == 'fr' ||
        normalized.startsWith('fr_') ||
        normalized.startsWith('fr-')) {
      return 'fr';
    }
    if (normalized == 'ar' ||
        normalized.startsWith('ar_') ||
        normalized.startsWith('ar-')) {
      return 'ar';
    }
    return normalized;
  }

  bool _looksCorrupt(String locale, String text) {
    if (locale == 'ar' && _looksCorruptArabic(text)) return true;
    if (text.contains('\uFFFD') ||
        text.contains('\u00C3') ||
        text.contains('\u00D8') ||
        text.contains('\u00D9')) {
      return true;
    }
    if (RegExp(r'[A-Za-z]\?[A-Za-z]').hasMatch(text)) {
      return true;
    }
    return false;
  }

  bool _looksCorruptArabic(String text) {
    if (text.isEmpty) return true;
    final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
    if (hasArabic) return false;
    return true;
  }

  bool _looksPlaceholderText(String key, String text) {
    final normalizedKey = _normalizePlaceholderCandidate(key);
    final normalizedText = _normalizePlaceholderCandidate(text);
    if (normalizedText.isEmpty || normalizedText == normalizedKey) return true;
    final collapsedText = normalizedText
        .replaceAll(RegExp(r'[\u00A0\u2007\u202F]'), ' ')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp("[\"'`«»“”]"), '');
    if (collapsedText == normalizedKey) return true;
    // Some DB rows contain hidden bidi/zero-width chars around values that are
    // effectively i18n keys (e.g. "listing.add.title_label"). Treat all such
    // key-like values as placeholders so assets stay authoritative.
    if (_looksDottedPlaceholder(collapsedText) ||
        _looksDottedPlaceholder(normalizedText)) {
      return true;
    }
    final dots = '.'.allMatches(collapsedText).length;
    if (dots >= 2 &&
        !collapsedText.contains(' ') &&
        collapsedText.length <= normalizedKey.length + 8 &&
        collapsedText.startsWith(normalizedKey.split('.').first)) {
      return true;
    }
    return false;
  }

  bool _looksDottedPlaceholder(String value) {
    return RegExp(r'^[a-z0-9_-]+(?:\.[a-z0-9_-]+)+$').hasMatch(value);
  }

  String _normalizePlaceholderCandidate(String input) {
    return input
        .replaceAll(
          RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'),
          '',
        )
        .trim()
        .toLowerCase();
  }
}
