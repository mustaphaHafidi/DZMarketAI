import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/review.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class ReviewService {
  Stream<List<Review>> streamReviewsForUser(String userId) {
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
    return RateLimiter.instance.stream(
      'reviews.stream',
      () => supabase
          .from('reviews')
          .stream(primaryKey: ['id'])
          .eq('user_id', safeUserId)
          .order('created_at', ascending: false)
          .map((rows) => rows.map(Review.fromJson).toList()),
    );
  }

  Future<double?> fetchAverageRating(String userId) async {
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
    final resp = await RateLimiter.instance.run(
      'reviews.rating.select',
      () => supabase.from('reviews').select('rating').eq('user_id', safeUserId),
    );
    if (resp.isEmpty) return null;
    final nums = resp.map((r) => (r['rating'] as num?)?.toDouble() ?? 0).toList();
    if (nums.isEmpty) return null;
    final avg = nums.reduce((a, b) => a + b) / nums.length;
    return double.parse(avg.toStringAsFixed(1));
  }

  Future<bool> hasReviewForOrder(String orderId, String reviewerId) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeReviewerId = InputSanitizer.sanitizeId(reviewerId, maxLength: 64);
    final existing = await RateLimiter.instance.run(
      'reviews.exists',
      () => supabase
          .from('reviews')
          .select('id')
          .eq('order_id', safeOrderId)
          .eq('reviewer_id', safeReviewerId)
          .maybeSingle(),
    );
    return existing != null;
  }

  Future<void> submitReview({
    required String orderId,
    required String reviewerId,
    required String userId,
    required int rating,
    String? comment,
  }) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeReviewerId = InputSanitizer.sanitizeId(reviewerId, maxLength: 64);
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
    final safeComment =
        InputSanitizer.sanitizeOptionalText(comment, maxLength: 400);
    await RateLimiter.instance.run(
      'reviews.upsert',
      () => supabase.from(SupabaseTables.reviews).upsert({
        'order_id': safeOrderId,
        'reviewer_id': safeReviewerId,
        'user_id': safeUserId,
        'rating': rating,
        'comment': safeComment,
      }, onConflict: 'order_id,reviewer_id'),
    );
  }
}
