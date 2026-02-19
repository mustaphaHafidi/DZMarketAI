import 'package:dzmarket/src/services/translation_service.dart';
import 'package:flutter/widgets.dart';

/// Very small bilingual helper (fr/ar) for key UI strings, with DB translations.
class L10n {
  static const supportedLocales = [Locale('fr'), Locale('ar')];

  /// Translate using JSON assets (and optional DB override).
  static String tr(
    BuildContext context,
    String key, {
    String? fallback,
    Map<String, String>? params,
  }) {
    final locale = Localizations.localeOf(context).languageCode;
    return trLocale(locale, key, fallback: fallback, params: params);
  }

  /// Translate without a BuildContext (e.g., services).
  static String trLocale(
    String locale,
    String key, {
    String? fallback,
    Map<String, String>? params,
  }) {
    final normalizedLocale = _normalizeLocale(locale);
    var text =
        TranslationService.instance.translate(normalizedLocale, key) ??
        TranslationService.instance.translate('fr', key) ??
        fallback ??
        key;

    if (_looksCorrupt(text)) {
      if (fallback != null && !_looksCorrupt(fallback)) {
        text = fallback;
      } else {
        final frValue = TranslationService.instance.translate('fr', key);
        if (frValue != null && !_looksCorrupt(frValue)) {
          text = frValue;
        }
      }
    }
    if (params != null && params.isNotEmpty) {
      params.forEach((k, v) {
        text = text.replaceAll('{$k}', v);
      });
    }
    return text;
  }

  static String _normalizeLocale(String locale) {
    final normalized = locale.toLowerCase();
    if (normalized == 'fr' || normalized.startsWith('fr_')) return 'fr';
    if (normalized == 'ar' || normalized.startsWith('ar_')) return 'ar';
    return 'fr';
  }

  /// [key] defaults to the French text; override to use a stable key from DB.
  static String t(BuildContext context, String fr, String ar, {String? key}) {
    final locale = Localizations.localeOf(context);
    final code = locale.languageCode;
    final k = key ?? fr;
    final db = TranslationService.instance.translate(code, k);
    if (db != null && db.isNotEmpty && !_looksCorrupt(db)) return db;
    if (code == 'ar') {
      return _looksCorrupt(ar) ? fr : ar;
    }
    return fr;
  }

  static bool _looksCorrupt(String value) {
    if (value.isEmpty) return true;
    if (value.contains('\uFFFD') ||
        value.contains('\u00C3') ||
        value.contains('\u00D8') ||
        value.contains('\u00D9')) {
      return true;
    }
    if (RegExp(r'[A-Za-z]\?[A-Za-z]').hasMatch(value)) {
      return true;
    }
    final questionMarks = '?'.allMatches(value).length;
    if (questionMarks >= 3 && questionMarks * 3 >= value.length) {
      return true;
    }
    for (final unit in value.codeUnits) {
      if (unit <= 0x1F || (unit >= 0x80 && unit <= 0x9F)) {
        return true;
      }
    }
    return false;
  }
}
