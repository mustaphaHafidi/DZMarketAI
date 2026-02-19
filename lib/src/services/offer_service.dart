import 'package:dzmarket/src/models/offer.dart';
import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:rxdart/rxdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OfferService {
  bool _isMissingRpc(PostgrestException e, String fnName) {
    return e.code == 'PGRST202' ||
        e.code == '42883' ||
        e.message.contains(fnName);
  }

  bool _isMissingColumns(PostgrestException e, List<String> columns) {
    if (e.code == 'PGRST204' || e.code == '42703') return true;
    final haystack = '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'
        .toLowerCase();
    for (final column in columns) {
      if (haystack.contains(column.toLowerCase())) return true;
    }
    return false;
  }

  int _parseRequiredInt(String raw, {required String field}) {
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw FormatException('Invalid $field');
    }
    return parsed;
  }

  Future<void> _ensureOfferAllowedLegacy({
    required String productId,
    required String buyerId,
    required double amount,
  }) async {
    final product = await RateLimiter.instance.run(
      'offers.product.legacy_guard',
      () => supabase
          .from('products')
          .select(
            'id,owner_id,status,is_archived,stock_quantity,price,is_negotiable',
          )
          .eq('id', productId)
          .maybeSingle(),
    );
    if (product == null) {
      throw StateError('product_missing');
    }
    if (product['owner_id']?.toString() == buyerId) {
      throw StateError('cannot_offer_own_product');
    }
    final isNegotiable = product['is_negotiable'] as bool? ?? true;
    if (!isNegotiable) {
      throw StateError('offer_not_negotiable');
    }
    final isArchived = product['is_archived'] as bool? ?? false;
    final status = product['status']?.toString() ?? 'active';
    final stock = (product['stock_quantity'] as num?)?.toInt() ?? 0;
    if (isArchived || status != 'active' || stock <= 0) {
      throw StateError('product_unavailable');
    }
    final minAmount = InputSanitizer.offerMinAmountFromBasePrice(
      (product['price'] as num?)?.toDouble(),
    );
    if (amount < minAmount) {
      throw StateError('offer_below_min_ratio');
    }
  }

  Future<void> _postLegacyOfferMessage({
    required String productId,
    required String buyerId,
    required String sellerId,
    required String event,
    required String offerId,
    double? amount,
    String? dedupeKey,
  }) async {
    try {
      final repo = ChatRepository();
      final conv = await repo.ensureConversation(
        productId: productId,
        buyerId: buyerId,
        sellerId: sellerId,
      );
      String text;
      switch (event) {
        case 'created':
          text = 'Nouvelle offre: DA ${amount?.toStringAsFixed(0) ?? '0'}';
          break;
        case 'counter':
          text = 'Contre-offre: DA ${amount?.toStringAsFixed(0) ?? '0'}';
          break;
        case 'accepted':
          text = 'Offre acceptee: DA ${amount?.toStringAsFixed(0) ?? '0'}';
          break;
        case 'rejected':
          text = 'Offre refusee';
          break;
        default:
          text = 'Mise a jour offre';
      }
      await repo.sendMessage(
        conv.id,
        text,
        type: 'system',
        payload: {
          'i18n_key': 'offer.system.$event',
          'offer_id': offerId,
          'event': event,
          if (amount != null) 'amount': amount,
        },
        dedupeKey: dedupeKey,
      );
    } catch (_) {
      // Best effort only on legacy fallback path.
    }
  }

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
    final safeMessage = InputSanitizer.sanitizeOptionalText(
      message,
      maxLength: 240,
    );
    try {
      final inserted = await RateLimiter.instance.run(
        'offers.insert.rpc',
        () => supabase.rpc(
          'make_offer',
          params: {
            'p_product_id': _parseRequiredInt(
              safeProductId,
              field: 'product_id',
            ),
            'p_amount': amount,
            if (safeMessage != null && safeMessage.isNotEmpty)
              'p_message': safeMessage,
          },
        ),
      );
      if (inserted == null) throw StateError('make_offer returned null');
      return Offer.fromJson((inserted as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (!_isMissingRpc(e, 'make_offer')) rethrow;
      await _ensureOfferAllowedLegacy(
        productId: safeProductId,
        buyerId: buyerId,
        amount: amount,
      );
      final inserted = await RateLimiter.instance.run(
        'offers.insert.legacy',
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
      await _postLegacyOfferMessage(
        productId: safeProductId,
        buyerId: buyerId,
        sellerId: safeSellerId,
        event: 'created',
        offerId: inserted['id'].toString(),
        amount: amount,
        dedupeKey: 'offer:${inserted['id']}:created',
      );
      return Offer.fromJson(inserted);
    }
  }

  Future<Offer?> fetchOfferById(String offerId) async {
    final safeOfferId = InputSanitizer.sanitizeId(offerId, maxLength: 64);
    final row = await RateLimiter.instance.run(
      'offers.select.one',
      () => supabase
          .from('offers')
          .select('*')
          .eq('id', safeOfferId)
          .maybeSingle(),
    );
    if (row == null) return null;
    return Offer.fromJson(row);
  }

  Future<Offer> updateStatus(String offerId, OfferStatus status) async {
    if (status == OfferStatus.rejected) {
      return rejectOffer(offerId: offerId);
    }
    final safeOfferId = InputSanitizer.sanitizeId(offerId, maxLength: 64);
    final updated = await RateLimiter.instance.run(
      'offers.update.status',
      () => supabase
          .from('offers')
          .update({
            'status': status.name,
            'responded_at': DateTime.now().toIso8601String(),
          })
          .eq('id', safeOfferId)
          .select()
          .single(),
    );
    return Offer.fromJson(updated);
  }

  Future<Offer> rejectOffer({required String offerId, String? message}) async {
    final safeOfferId = InputSanitizer.sanitizeId(offerId, maxLength: 64);
    final safeMessage = InputSanitizer.sanitizeOptionalText(
      message,
      maxLength: 240,
    );
    try {
      final updated = await RateLimiter.instance.run(
        'offers.update.reject.rpc',
        () => supabase.rpc(
          'respond_offer',
          params: {
            'p_offer_id': _parseRequiredInt(safeOfferId, field: 'offer_id'),
            'p_action': 'reject',
            if (safeMessage != null && safeMessage.isNotEmpty)
              'p_message': safeMessage,
          },
        ),
      );
      if (updated == null) throw StateError('respond_offer returned null');
      return Offer.fromJson((updated as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (!_isMissingRpc(e, 'respond_offer')) rethrow;
      final current = await RateLimiter.instance.run(
        'offers.select.reject.legacy',
        () => supabase
            .from('offers')
            .select('id,product_id,buyer_id,seller_id,amount')
            .eq('id', safeOfferId)
            .single(),
      );
      final updated = await RateLimiter.instance.run(
        'offers.update.reject.legacy',
        () => supabase
            .from('offers')
            .update({
              'status': 'rejected',
              'responded_at': DateTime.now().toIso8601String(),
              if (safeMessage != null && safeMessage.isNotEmpty)
                'message': safeMessage,
            })
            .eq('id', safeOfferId)
            .select()
            .single(),
      );
      await _postLegacyOfferMessage(
        productId: current['product_id'].toString(),
        buyerId: current['buyer_id'].toString(),
        sellerId: current['seller_id'].toString(),
        event: 'rejected',
        offerId: current['id'].toString(),
        dedupeKey: 'offer:${current['id']}:rejected',
      );
      return Offer.fromJson(updated);
    }
  }

  Future<Offer> counterOffer({
    required String offerId,
    required double counterAmount,
    String? message,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');
    final safeOfferId = InputSanitizer.sanitizeId(offerId, maxLength: 64);
    final safeMessage = InputSanitizer.sanitizeOptionalText(
      message,
      maxLength: 240,
    );
    try {
      final updated = await RateLimiter.instance.run(
        'offers.update.counter.rpc',
        () => supabase.rpc(
          'respond_offer',
          params: {
            'p_offer_id': _parseRequiredInt(safeOfferId, field: 'offer_id'),
            'p_action': 'counter',
            'p_amount': counterAmount,
            if (safeMessage != null && safeMessage.isNotEmpty)
              'p_message': safeMessage,
          },
        ),
      );
      if (updated == null) throw StateError('respond_offer returned null');
      return Offer.fromJson((updated as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (!_isMissingRpc(e, 'respond_offer')) rethrow;
      final current = await RateLimiter.instance.run(
        'offers.select.counter.legacy',
        () => supabase
            .from('offers')
            .select('id,product_id,buyer_id,seller_id')
            .eq('id', safeOfferId)
            .single(),
      );
      final nowIso = DateTime.now().toIso8601String();
      late final Map<String, dynamic> updated;
      try {
        updated = await RateLimiter.instance.run(
          'offers.update.counter.legacy',
          () => supabase
              .from('offers')
              .update({
                'status': 'pending',
                'counter_amount': counterAmount,
                'counter_by': userId,
                'responded_at': nowIso,
                if (safeMessage != null && safeMessage.isNotEmpty)
                  'message': safeMessage,
              })
              .eq('id', safeOfferId)
              .select()
              .single(),
        );
      } on PostgrestException catch (inner) {
        if (!_isMissingColumns(inner, ['counter_amount', 'counter_by'])) {
          rethrow;
        }
        // Legacy deployments may not have counter columns yet.
        // Keep flow working by storing the negotiated amount in `amount`.
        updated = await RateLimiter.instance.run(
          'offers.update.counter.legacy.compat',
          () => supabase
              .from('offers')
              .update({
                'status': 'pending',
                'amount': counterAmount,
                'responded_at': nowIso,
                if (safeMessage != null && safeMessage.isNotEmpty)
                  'message': safeMessage,
              })
              .eq('id', safeOfferId)
              .select()
              .single(),
        );
      }
      await _postLegacyOfferMessage(
        productId: current['product_id'].toString(),
        buyerId: current['buyer_id'].toString(),
        sellerId: current['seller_id'].toString(),
        event: 'counter',
        offerId: current['id'].toString(),
        amount: counterAmount,
      );
      return Offer.fromJson(updated);
    }
  }

  Future<Offer> acceptOffer({
    required String offerId,
    required double agreedAmount,
    String? message,
  }) async {
    final safeOfferId = InputSanitizer.sanitizeId(offerId, maxLength: 64);
    final safeMessage = InputSanitizer.sanitizeOptionalText(
      message,
      maxLength: 240,
    );
    try {
      final updated = await RateLimiter.instance.run(
        'offers.update.accept.rpc',
        () => supabase.rpc(
          'respond_offer',
          params: {
            'p_offer_id': _parseRequiredInt(safeOfferId, field: 'offer_id'),
            'p_action': 'accept',
            'p_amount': agreedAmount,
            if (safeMessage != null && safeMessage.isNotEmpty)
              'p_message': safeMessage,
          },
        ),
      );
      if (updated == null) throw StateError('respond_offer returned null');
      return Offer.fromJson((updated as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (!_isMissingRpc(e, 'respond_offer')) rethrow;
      final current = await RateLimiter.instance.run(
        'offers.select.accept.legacy',
        () => supabase
            .from('offers')
            .select('id,product_id,buyer_id,seller_id')
            .eq('id', safeOfferId)
            .single(),
      );
      final nowIso = DateTime.now().toIso8601String();
      late final Map<String, dynamic> updated;
      try {
        updated = await RateLimiter.instance.run(
          'offers.update.accept.legacy',
          () => supabase
              .from('offers')
              .update({
                'status': 'accepted',
                'agreed_amount': agreedAmount,
                'responded_at': nowIso,
                if (safeMessage != null && safeMessage.isNotEmpty)
                  'message': safeMessage,
              })
              .eq('id', safeOfferId)
              .select()
              .single(),
        );
      } on PostgrestException catch (inner) {
        if (!_isMissingColumns(inner, ['agreed_amount'])) rethrow;
        // Legacy deployments may not have agreed_amount yet.
        updated = await RateLimiter.instance.run(
          'offers.update.accept.legacy.compat',
          () => supabase
              .from('offers')
              .update({
                'status': 'accepted',
                'amount': agreedAmount,
                'responded_at': nowIso,
                if (safeMessage != null && safeMessage.isNotEmpty)
                  'message': safeMessage,
              })
              .eq('id', safeOfferId)
              .select()
              .single(),
        );
      }
      await RateLimiter.instance.run(
        'offers.update.accept.legacy.others',
        () => supabase
            .from('offers')
            .update({'status': 'rejected', 'responded_at': nowIso})
            .eq('product_id', current['product_id'])
            .neq('id', safeOfferId)
            .eq('status', 'pending'),
      );
      await _postLegacyOfferMessage(
        productId: current['product_id'].toString(),
        buyerId: current['buyer_id'].toString(),
        sellerId: current['seller_id'].toString(),
        event: 'accepted',
        offerId: current['id'].toString(),
        amount: agreedAmount,
        dedupeKey: 'offer:${current['id']}:accepted',
      );
      return Offer.fromJson(updated);
    }
  }
}
