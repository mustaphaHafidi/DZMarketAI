import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton to propagate locale changes across the app and persist it locally.
class LocaleService {
  LocaleService._();
  static final instance = LocaleService._();

  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(
    const Locale('fr'),
  );
  static const _key = 'preferred_locale_code';
  static const _supported = {'fr', 'ar'};

  String _normalizeCode(String code) {
    var normalized = code.trim();
    if (normalized.length >= 2 &&
        ((normalized.startsWith('"') && normalized.endsWith('"')) ||
            (normalized.startsWith("'") && normalized.endsWith("'")))) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    normalized = normalized.toLowerCase();
    if (normalized == 'ar' ||
        normalized.startsWith('ar_') ||
        normalized.startsWith('ar-')) {
      return 'ar';
    }
    if (normalized == 'fr' ||
        normalized.startsWith('fr_') ||
        normalized.startsWith('fr-')) {
      return 'fr';
    }
    return 'fr';
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) {
      final normalized = _normalizeCode(saved);
      if (_supported.contains(normalized)) {
        locale.value = Locale(normalized);
      } else {
        locale.value = const Locale('fr');
        await prefs.setString(_key, 'fr');
      }
    }
  }

  Future<void> setLocale(String? code) async {
    if (code == null || code.isEmpty) return;
    final normalized = _normalizeCode(code);
    if (!_supported.contains(normalized)) return;
    locale.value = Locale(normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, normalized);
  }
}
