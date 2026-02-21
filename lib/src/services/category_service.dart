import 'dart:convert';

import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CategoryService {
  static const Duration _cacheTtl = Duration(hours: 12);
  static const _cacheKey = 'cache.categories.v4';
  static List<Map<String, String>>? _cache;

  Future<List<Map<String, String>>> fetchCategories() async {
    if (_cache != null) return _cache!;
    final cached = await _readCache();
    if (cached != null) {
      _cache = cached;
      return cached;
    }
    try {
      final rows = await RateLimiter.instance.run(
        'categories.select',
        () => supabase
            .from(SupabaseTables.categories)
            .select(
              'id, slug, name_fr, name_ar, icon, parent_id, sort_order, is_active',
            )
            .eq('is_active', true)
            .order('sort_order')
            .order('name_fr'),
      );
      final items = rows
          .map(
            (r) => {
              'id': r['id']?.toString() ?? '',
              'slug': r['slug']?.toString() ?? '',
              'name_fr': _normalizeName(r['name_fr']?.toString()),
              'name_ar': _normalizeName(r['name_ar']?.toString()),
              'icon': r['icon']?.toString() ?? '',
              'parent_id': r['parent_id']?.toString() ?? '',
              'sort_order': r['sort_order']?.toString() ?? '',
            },
          )
          .where((r) => r['id']!.isNotEmpty && r['name_fr']!.isNotEmpty)
          .toList();
      _cache = items;
      await _writeCache(items);
      return items;
    } catch (_) {
      return _cache ?? const [];
    }
  }

  Future<List<Map<String, String>>?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final ts = DateTime.tryParse(decoded['ts'] as String? ?? '');
      if (ts == null || DateTime.now().difference(ts) > _cacheTtl) return null;
      final items = (decoded['items'] as List)
          .whereType<Map>()
          .map(
            (e) => e.map(
              (k, v) => MapEntry(
                k.toString(),
                k.toString().startsWith('name_')
                    ? _normalizeName(v?.toString())
                    : (v?.toString() ?? ''),
              ),
            ),
          )
          .toList();
      return items;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(List<Map<String, String>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'ts': DateTime.now().toIso8601String(),
        'items': items,
      });
      await prefs.setString(_cacheKey, payload);
    } catch (_) {}
  }

  bool _looksMojibake(String value) {
    if (value.isEmpty) return false;
    if (value.contains('\uFFFD')) return true;
    // Common UTF-8 -> Latin-1 mojibake markers.
    if (value.contains('\u00C3') || value.contains('\u00C2')) return true;
    if (value.contains('\u00E2\u20AC\u2122') ||
        value.contains('\u00E2\u20AC\u201C') ||
        value.contains('\u00E2\u20AC\u201D')) {
      return true;
    }
    return false;
  }

  String _normalizeName(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty || !_looksMojibake(input)) return input;
    try {
      final decoded = utf8.decode(latin1.encode(input));
      final normalized = decoded.trim();
      if (normalized.isNotEmpty && !_looksMojibake(normalized)) {
        return normalized;
      }
    } catch (_) {}
    return input;
  }
}
