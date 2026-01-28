import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class FavoriteService {
  Stream<Set<String>> streamFavorites(String userId) {
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
    return RateLimiter.instance.stream(
      'favorites.stream',
      () => supabase
          .from(SupabaseTables.favorites)
          .stream(primaryKey: ['user_id', 'product_id'])
          .eq('user_id', safeUserId)
          .map((rows) => rows.map((r) => r['product_id'].toString()).toSet()),
    );
  }

  Future<void> toggleFavorite({
    required String productId,
    required bool isFav,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');
    final safeProductId = InputSanitizer.sanitizeId(productId, maxLength: 64);
    final pid = int.tryParse(safeProductId) ?? safeProductId;

    if (isFav) {
      await RateLimiter.instance.run(
        'favorites.delete',
        () => supabase.from(SupabaseTables.favorites).delete().match({
          'user_id': userId,
          'product_id': pid,
        }),
      );
    } else {
      await RateLimiter.instance.run(
        'favorites.upsert',
        () => supabase.from(SupabaseTables.favorites).upsert({
          'user_id': userId,
          'product_id': pid,
        }),
      );
    }
  }
}
