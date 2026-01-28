import 'package:dzmarket/src/services/translation_service.dart';
import 'package:flutter/widgets.dart';

/// Very small bilingual helper (fr/ar) for key UI strings, with DB translations.
class L10n {
  static const supportedLocales = [
    Locale('fr'),
    Locale('ar'),
  ];

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
    for (final unit in value.codeUnits) {
      if (unit <= 0x1F || (unit >= 0x80 && unit <= 0x9F)) {
        return true;
      }
    }
    return false;
  }
}
