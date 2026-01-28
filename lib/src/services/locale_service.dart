import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton to propagate locale changes across the app and persist it locally.
class LocaleService {
  LocaleService._();
  static final instance = LocaleService._();

  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(const Locale('fr'));
  static const _key = 'preferred_locale_code';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) {
      locale.value = Locale(saved);
    }
  }

  Future<void> setLocale(String? code) async {
    if (code == null || code.isEmpty) return;
    locale.value = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);
  }
}
