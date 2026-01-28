import 'package:dzmarket/src/models/offer.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:rxdart/rxdart.dart';

class OfferService {
  Stream<List<Offer>> streamOffersForProduct(String productId) {
    final safeProductId = InputSanitizer.sanitizeId(productId, maxLength: 64);
    return RateLimiter.instance.stream(
      'offers.product.stream',
      () => supabase
          .from('offers')
          .stream(primaryKey: ['id'])
          .eq('product_id', safeProductId)
          .order('created_at')
          .map((rows) => rows.map(Offer.fromJson).toList()),
    );
  }

  Stream<List<Offer>> streamOffersForUser(String userId) {
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
    final buyerStream = RateLimiter.instance.stream(
      'offers.buyer.stream',
      () => supabase
          .from('offers')
          .stream(primaryKey: ['id'])
          .eq('buyer_id', safeUserId)
          .order('created_at'),
    );
    final sellerStream = RateLimiter.instance.stream(
      'offers.seller.stream',
      () => supabase
          .from('offers')
          .stream(primaryKey: ['id'])
          .eq('seller_id', safeUserId)
          .order('created_at'),
    );

    return Rx.combineLatest2<
      List<Map<String, dynamic>>,
      List<Map<String, dynamic>>,
      List<Offer>
    >(buyerStream, sellerStream, (buyer, seller) {
      final merged = <String, Map<String, dynamic>>{};
      for (final row in buyer) {
        merged[row['id'].toString()] = row;
      }
      for (final row in seller) {
        merged[row['id'].toString()] = row;
      }
      final list = merged.values.map(Offer.fromJson).toList();
      list.sort(
        (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
          a.createdAt ?? DateTime.now(),
        ),
      );
      return list;
    });
  }

  Future<Offer> makeOffer({
    required String productId,
    required String sellerId,
    required double amount,
    String? message,
  }) async {
    final buyerId = supabase.auth.currentUser?.id;
    if (buyerId == null) throw StateError('Sign in to make offers');
    final safeProductId = InputSanitizer.sanitizeId(productId, maxLength: 64);
    final safeSellerId = InputSanitizer.sanitizeId(sellerId, maxLength: 64);
    final safeMessage =
        InputSanitizer.sanitizeOptionalText(message, maxLength: 240);

    final inserted = await RateLimiter.instance.run(
      'offers.insert',
      () => supabase
          .from('offers')
          .insert({
            'product_id': safeProductId,
            'buyer_id': buyerId,
            'seller_id': safeSellerId,
            'amount': amount,
            'message': safeMessage,
          })
          .select()
          .single(),
    );
    return Offer.fromJson(inserted);
  }

  Future<void> updateStatus(String offerId, OfferStatus status) async {
    final safeOfferId = InputSanitizer.sanitizeId(offerId, maxLength: 64);
    await RateLimiter.instance.run(
      'offers.update.status',
      () => supabase
          .from('offers')
          .update({
            'status': status.name,
            'responded_at': DateTime.now().toIso8601String(),
          })
          .eq('id', safeOfferId),
    );
  }

  Future<void> counterOffer({
    required String offerId,
    required double counterAmount,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');
    final safeOfferId = InputSanitizer.sanitizeId(offerId, maxLength: 64);
    await RateLimiter.instance.run(
      'offers.update.counter',
      () => supabase.from('offers').update({
        'status': 'pending',
        'counter_amount': counterAmount,
        'counter_by': userId,
        'responded_at': DateTime.now().toIso8601String(),
      }).eq('id', safeOfferId),
    );
  }

  Future<void> acceptOffer({
    required String offerId,
    required double agreedAmount,
  }) async {
    final safeOfferId = InputSanitizer.sanitizeId(offerId, maxLength: 64);
    await RateLimiter.instance.run(
      'offers.update.accept',
      () => supabase.from('offers').update({
        'status': 'accepted',
        'agreed_amount': agreedAmount,
        'responded_at': DateTime.now().toIso8601String(),
      }).eq('id', safeOfferId),
    );
  }
}
