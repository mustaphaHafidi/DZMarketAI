import 'dart:convert';

import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationDataService {
  LocationDataService._();
  static final instance = LocationDataService._();

  static const _wilayasCacheKey = 'cache.wilayas.v2';
  static const _communesCachePrefix = 'cache.communes.v2.';
  static const Duration _cacheTtl = Duration(hours: 12);

  List<Map<String, String>>? _wilayasCache;
  final Map<String, List<Map<String, String>>> _communesCache = {};

  Future<List<Map<String, String>>> fetchWilayas() async {
    if (_wilayasCache != null) return _wilayasCache!;
    final cached = await _readCache(_wilayasCacheKey);
    if (cached != null) {
      _wilayasCache = cached;
      return cached;
    }
    try {
      final rows = await RateLimiter.instance.run(
        'wilayas.select',
        () => supabase
            .from(SupabaseTables.wilayas)
            .select('code, name_fr, name_ar')
            .order('code'),
      );
      final items = rows
          .map(
            (r) => {
              'code': r['code']?.toString() ?? '',
              'name_fr': r['name_fr']?.toString() ?? '',
              'name_ar': r['name_ar']?.toString() ?? '',
            },
          )
          .where((r) => r['code']!.isNotEmpty && r['name_fr']!.isNotEmpty)
          .toList();
      _wilayasCache = items;
      await _writeCache(_wilayasCacheKey, items);
      return items;
    } catch (_) {
      return _wilayasCache ?? const [];
    }
  }

  Future<List<Map<String, String>>> fetchCommunes(String wilayaCode) async {
    final key = wilayaCode.trim();
    if (key.isEmpty) return const [];
    if (_communesCache.containsKey(key)) return _communesCache[key]!;
    final cached = await _readCache('$_communesCachePrefix$key');
    if (cached != null) {
      _communesCache[key] = cached;
      return cached;
    }
    try {
      final rows = await RateLimiter.instance.run(
        'communes.select.$key',
        () => supabase
            .from(SupabaseTables.communes)
            .select('id, name_fr, name_ar, wilaya_code')
            .eq('wilaya_code', key)
            .order('name_fr'),
      );
      final items = rows
          .map(
            (r) => {
              'id': r['id']?.toString() ?? '',
              'name_fr': r['name_fr']?.toString() ?? '',
              'name_ar': r['name_ar']?.toString() ?? '',
            },
          )
          .where((r) => r['id']!.isNotEmpty && r['name_fr']!.isNotEmpty)
          .toList();
      _communesCache[key] = items;
      await _writeCache('$_communesCachePrefix$key', items);
      return items;
    } catch (_) {
      return _communesCache[key] ?? const [];
    }
  }

  Future<List<Map<String, String>>?> _readCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final ts = DateTime.tryParse(decoded['ts'] as String? ?? '');
      if (ts == null ||
          DateTime.now().difference(ts) > _cacheTtl ||
          decoded['items'] is! List) {
        return null;
      }
      final items = (decoded['items'] as List)
          .whereType<Map>()
          .map(
            (e) => e.map(
              (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
            ),
          )
          .toList();
      return items;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, List<Map<String, String>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'ts': DateTime.now().toIso8601String(),
        'items': items,
      });
      await prefs.setString(key, payload);
    } catch (_) {}
  }
}
