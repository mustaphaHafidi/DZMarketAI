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

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) {
      final normalized = saved.toLowerCase();
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
    final normalized = code.toLowerCase();
    if (!_supported.contains(normalized)) return;
    locale.value = Locale(normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, normalized);
  }
}
