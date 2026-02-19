import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.name,
    this.query,
    this.filters = const {},
  });

  final String id;
  final String name;
  final String? query;
  final Map<String, dynamic> filters;

  factory SavedSearch.fromJson(Map<String, dynamic> json) => SavedSearch(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    query: json['query'] as String?,
    filters: (json['filters'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}

class SavedSearchService {
  Future<List<SavedSearch>> fetchSavedSearches(String userId) async {
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
    final rows = await RateLimiter.instance.run(
      'saved_searches.fetch',
      () => supabase
          .from('saved_searches')
          .select()
          .eq('user_id', safeUserId)
          .order('created_at'),
    );
    return (rows as List<dynamic>)
        .map((e) => SavedSearch.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Stream<List<SavedSearch>> streamSavedSearches(String userId) {
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
    return RateLimiter.instance.stream(
      'saved_searches.stream',
      () => supabase
          .from('saved_searches')
          .stream(primaryKey: ['id'])
          .eq('user_id', safeUserId)
          .order('created_at')
          .map((rows) => rows.map(SavedSearch.fromJson).toList()),
    );
  }

  Future<void> saveSearch({
    required String name,
    String? query,
    Map<String, dynamic>? filters,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');
    final safeName = InputSanitizer.sanitizeText(name, maxLength: 60);
    final safeQuery = InputSanitizer.sanitizeSearchQuery(query ?? '');
    final safeFilters = _sanitizeFilters(filters);

    await RateLimiter.instance.run(
      'saved_searches.insert',
      () => supabase.from('saved_searches').insert({
        'user_id': userId,
        'name': safeName,
        'query': safeQuery.isEmpty ? null : safeQuery,
        'filters': safeFilters,
      }),
    );
  }

  Future<void> deleteSearch(String id) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');
    final safeId = InputSanitizer.sanitizeId(id, maxLength: 64);
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);

    await RateLimiter.instance.run(
      'saved_searches.delete',
      () => supabase
          .from('saved_searches')
          .delete()
          .eq('id', safeId)
          .eq('user_id', safeUserId),
    );
  }

  Map<String, dynamic>? _sanitizeFilters(Map<String, dynamic>? filters) {
    if (filters == null) return null;
    final cleaned = <String, dynamic>{};
    filters.forEach((key, value) {
      if (value is String) {
        cleaned[key] = InputSanitizer.sanitizeText(value, maxLength: 80);
        return;
      }
      cleaned[key] = value;
    });
    return cleaned;
  }
}
