import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductService {
  static final Map<String, _ProductCacheEntry> _cache = {};
  static const Duration _cacheTtl = Duration(seconds: 20);
  static const int _maxOwnerProducts = 30;

  Stream<List<Product>> streamProducts() {
    final userId = supabase.auth.currentUser?.id;
    final base = RateLimiter.instance.stream(
      'products.stream',
      () => supabase
          .from(SupabaseTables.products)
          .stream(primaryKey: ['id'])
          .eq('moderation_status', 'approved')
          .order('created_at'),
    );
    if (userId == null) {
      return base
          .map((rows) => rows.map(Product.fromJson).toList())
          .map(
            (list) => list
                .where((p) => !p.isArchived && p.stockQuantity > 0)
                .toList(),
          );
    }
    // Filter out own products client-side if filter helper isn't available.
    return base
        .map((rows) => rows.map(Product.fromJson).toList())
        .map(
          (list) => list
              .where(
                (p) =>
                    p.ownerId != userId && !p.isArchived && p.stockQuantity > 0,
              )
              .toList(),
        );
  }

  Stream<List<Product>> streamProductsForOwner(String ownerId) {
    final safeOwnerId = InputSanitizer.sanitizeId(ownerId, maxLength: 64);
    return RateLimiter.instance.stream(
      'products.owner.stream',
      () => supabase
          .from(SupabaseTables.products)
          .stream(primaryKey: ['id'])
          .eq('owner_id', safeOwnerId)
          .order('created_at', ascending: false)
          .limit(_maxOwnerProducts)
          .map((rows) => rows.map(Product.fromJson).toList()),
    );
  }

  Future<List<Product>> fetchProducts({
    String? search,
    String? categoryId,
    String? condition,
    double? minPrice,
    double? maxPrice,
    String? brand,
    String? size,
    String? color,
    String? nearbyWilaya,
    String sort = 'newest',
    int limit = 30,
    int offset = 0,
    bool excludeOwner = true,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    final q = InputSanitizer.sanitizeSearchQuery(search ?? '').toLowerCase();
    final safeCategoryId = InputSanitizer.sanitizeOptionalText(
      categoryId,
      maxLength: 20,
    );
    final safeCondition = InputSanitizer.sanitizeOptionalText(
      condition,
      maxLength: 20,
    );
    final safeBrand = InputSanitizer.sanitizeOptionalText(brand, maxLength: 40);
    final safeSize = InputSanitizer.sanitizeOptionalText(size, maxLength: 40);
    final safeColor = InputSanitizer.sanitizeOptionalText(color, maxLength: 40);
    final safeNearbyWilaya = InputSanitizer.sanitizeOptionalText(
      nearbyWilaya,
      maxLength: 60,
    );
    final key = [
      'q=$q',
      'cat=${safeCategoryId ?? ''}',
      'cond=${safeCondition ?? ''}',
      'min=${minPrice ?? ''}',
      'max=${maxPrice ?? ''}',
      'brand=${safeBrand ?? ''}',
      'size=${safeSize ?? ''}',
      'color=${safeColor ?? ''}',
      'near=${safeNearbyWilaya ?? ''}',
      'sort=$sort',
      'limit=$limit',
      'offset=$offset',
      'user=${userId ?? ''}',
      'exclude=$excludeOwner',
    ].join('|');

    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) < _cacheTtl) {
      return cached.items;
    }

    final query = supabase
        .from(SupabaseTables.products)
        .select('*, categories(name_fr, name_ar, slug)');
    var filtered = query;
    filtered = filtered.eq('is_archived', false);
    filtered = filtered.gt('stock_quantity', 0);
    filtered = filtered.eq('moderation_status', 'approved');
    if (excludeOwner && userId != null) {
      filtered = filtered.neq('owner_id', userId);
    }
    if (q.isNotEmpty) {
      filtered = filtered.or('title.ilike.%$q%,description.ilike.%$q%');
    }
    final cat = (safeCategoryId ?? '').trim();
    if (cat.isNotEmpty && cat != 'any') {
      final parsed = int.tryParse(cat);
      filtered = filtered.eq('category_id', parsed ?? cat);
    }
    final cond = (safeCondition ?? '').trim().toLowerCase();
    if (cond.isNotEmpty && cond != 'any') {
      filtered = filtered.eq('condition', cond);
    }
    if (minPrice != null) {
      filtered = filtered.gte('price', minPrice);
    }
    if (maxPrice != null) {
      filtered = filtered.lte('price', maxPrice);
    }
    if (safeBrand != null && safeBrand.trim().isNotEmpty) {
      filtered = filtered.ilike('brand', '%${safeBrand.trim()}%');
    }
    if (safeSize != null && safeSize.trim().isNotEmpty) {
      filtered = filtered.ilike('size', '%${safeSize.trim()}%');
    }
    if (safeColor != null && safeColor.trim().isNotEmpty) {
      filtered = filtered.ilike('color', '%${safeColor.trim()}%');
    }
    if (safeNearbyWilaya != null && safeNearbyWilaya.trim().isNotEmpty) {
      filtered = filtered.eq('location_wilaya', safeNearbyWilaya.trim());
    }

    final ordered = switch (sort) {
      'price_low' => filtered.order('price', ascending: true),
      'price_high' => filtered.order('price', ascending: false),
      _ => filtered.order('created_at', ascending: false),
    };

    final data = await RateLimiter.instance.run(
      'products.fetch',
      () => ordered.range(offset, offset + limit - 1),
    );
    final items = (data as List<dynamic>)
        .map((row) => Product.fromJson(row as Map<String, dynamic>))
        .toList();

    _cache[key] = _ProductCacheEntry(DateTime.now(), items);
    return items;
  }

  Future<void> createProduct({
    required String title,
    required double price,
    String? description,
    String? imageUrl,
    List<String> imageUrls = const [],
    String? categoryId,
    String? categoryName,
    String? condition,
    String? brand,
    String? size,
    String? color,
    String? locationWilaya,
    String? locationDaira,
    List<String> deliveryOptions = const [],
    bool shippingFree = false,
    bool exchangeAfterDelivery = false,
    bool insuranceActive = false,
    double? declaredValue,
    int? weightKg,
    int? heightCm,
    int? widthCm,
    int? lengthCm,
    bool allowStopdesk = true,
    int stockQuantity = 1,
    double? costPrice,
    String moderationStatus = 'approved',
    String? moderationReason,
    List<String>? moderationLabels,
    double? moderationScore,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError(
        L10n.trLocale(
          LocaleService.instance.locale.value?.languageCode ?? 'fr',
          'profile.login_required',
        ),
      );
    }
    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    final safeTitle = InputSanitizer.sanitizeText(title, maxLength: 80);
    if (safeTitle.isEmpty) {
      throw FormatException(
        L10n.trLocale(locale, 'listing.add.error_add_title'),
      );
    }
    final safeDescription = InputSanitizer.sanitizeOptionalText(
      description,
      maxLength: 1200,
      allowNewlines: true,
    );
    final safeImageUrl = InputSanitizer.sanitizeUrl(imageUrl);
    final safeImageUrls = InputSanitizer.sanitizeUrlList(
      imageUrls,
      maxItems: 5,
    );
    final safeCategoryId = InputSanitizer.sanitizeOptionalText(
      categoryId,
      maxLength: 20,
    );
    final safeCondition = InputSanitizer.sanitizeOptionalText(
      condition,
      maxLength: 20,
    );
    final safeBrand = InputSanitizer.sanitizeOptionalText(brand, maxLength: 40);
    final safeSize = InputSanitizer.sanitizeOptionalText(size, maxLength: 40);
    final safeColor = InputSanitizer.sanitizeOptionalText(color, maxLength: 40);
    final safeWilaya = InputSanitizer.sanitizeOptionalText(
      locationWilaya,
      maxLength: 60,
    );
    final safeDaira = InputSanitizer.sanitizeOptionalText(
      locationDaira,
      maxLength: 60,
    );
    final safeCostPrice = costPrice;
    if (safeCostPrice != null && safeCostPrice < 0) {
      throw FormatException(
        L10n.trLocale(locale, 'listing.add.error_invalid_cost'),
      );
    }
    if (stockQuantity < 0) {
      throw FormatException(
        L10n.trLocale(locale, 'listing.add.error_invalid_stock'),
      );
    }
    final safeDelivery = deliveryOptions
        .map((opt) => InputSanitizer.sanitizeText(opt, maxLength: 20))
        .where((opt) => opt.isNotEmpty)
        .toList();
    final safeDeclaredValue = declaredValue;
    final safeWeight = weightKg;
    final safeHeight = heightCm;
    final safeWidth = widthCm;
    final safeLength = lengthCm;
    final safeAllowStopdesk = allowStopdesk;
    final safeModerationStatus = InputSanitizer.sanitizeText(
      moderationStatus,
      maxLength: 20,
    );
    final safeModerationReason = InputSanitizer.sanitizeOptionalText(
      moderationReason,
      maxLength: 300,
    );
    final safeModerationLabels = (moderationLabels ?? const [])
        .map((e) => InputSanitizer.sanitizeText(e, maxLength: 60))
        .where((e) => e.isNotEmpty)
        .toList();

    final payload = <String, dynamic>{
      'title': safeTitle,
      'price': price,
      'description': safeDescription,
      'image_url': safeImageUrl,
      'image_urls': safeImageUrls,
      'category_id': safeCategoryId != null
          ? int.tryParse(safeCategoryId) ?? safeCategoryId
          : null,
      'condition': safeCondition,
      'brand': safeBrand,
      'size': safeSize,
      'color': safeColor,
      'location_wilaya': safeWilaya,
      'location_daira': safeDaira,
      'delivery_options': safeDelivery,
      'shipping_free': shippingFree,
      'exchange_after_delivery': exchangeAfterDelivery,
      'insurance_active': insuranceActive,
      'declared_value': safeDeclaredValue,
      'weight_kg': safeWeight,
      'height_cm': safeHeight,
      'width_cm': safeWidth,
      'length_cm': safeLength,
      'allow_stopdesk': safeAllowStopdesk,
      'owner_id': userId,
      'stock_quantity': stockQuantity,
      'cost_price': safeCostPrice,
      'moderation_status': safeModerationStatus,
      if (safeModerationReason != null)
        'moderation_reason': safeModerationReason,
      if (safeModerationLabels.isNotEmpty)
        'moderation_labels': safeModerationLabels,
      if (moderationScore != null) 'moderation_score': moderationScore,
      'moderation_updated_at': DateTime.now().toIso8601String(),
    };

    await _insertProductWithSchemaFallback(payload);
  }

  Future<void> _insertProductWithSchemaFallback(
    Map<String, dynamic> payload,
  ) async {
    final mutable = Map<String, dynamic>.from(payload);
    while (true) {
      try {
        await RateLimiter.instance.run(
          'products.insert',
          () => supabase.from(SupabaseTables.products).insert(mutable),
        );
        return;
      } on PostgrestException catch (e) {
        if (e.code != '42703') rethrow;
        final missing = _extractMissingColumn(e.message);
        if (missing == null || !mutable.containsKey(missing)) rethrow;
        mutable.remove(missing);
      }
    }
  }

  String? _extractMissingColumn(String message) {
    final match = RegExp(r'column \"([^\"]+)\"').firstMatch(message);
    return match?.group(1);
  }

  Future<void> updateProduct({
    required String id,
    String? title,
    double? price,
    String? description,
    String? imageUrl,
    List<String>? imageUrls,
    String? categoryId,
    String? categoryName,
    String? condition,
    String? brand,
    String? size,
    String? color,
    String? locationWilaya,
    String? locationDaira,
    List<String>? deliveryOptions,
    bool? shippingFree,
    bool? exchangeAfterDelivery,
    bool? insuranceActive,
    double? declaredValue,
    int? weightKg,
    int? heightCm,
    int? widthCm,
    int? lengthCm,
    bool? allowStopdesk,
    int? stockQuantity,
    double? costPrice,
    bool? isArchived,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError(
        L10n.trLocale(
          LocaleService.instance.locale.value?.languageCode ?? 'fr',
          'profile.login_required',
        ),
      );
    }
    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    final safeId = InputSanitizer.sanitizeId(id, maxLength: 64);
    final payload = <String, dynamic>{};
    final safeTitle = InputSanitizer.sanitizeOptionalText(title, maxLength: 80);
    final safeDesc = InputSanitizer.sanitizeOptionalText(
      description,
      maxLength: 1200,
      allowNewlines: true,
    );
    final safeImageUrl = InputSanitizer.sanitizeUrl(imageUrl);
    final safeCategoryId = InputSanitizer.sanitizeOptionalText(
      categoryId,
      maxLength: 20,
    );
    final safeCondition = InputSanitizer.sanitizeOptionalText(
      condition,
      maxLength: 20,
    );
    final safeBrand = InputSanitizer.sanitizeOptionalText(brand, maxLength: 40);
    final safeSize = InputSanitizer.sanitizeOptionalText(size, maxLength: 40);
    final safeColor = InputSanitizer.sanitizeOptionalText(color, maxLength: 40);
    final safeWilaya = InputSanitizer.sanitizeOptionalText(
      locationWilaya,
      maxLength: 60,
    );
    final safeDaira = InputSanitizer.sanitizeOptionalText(
      locationDaira,
      maxLength: 60,
    );
    if (stockQuantity != null && stockQuantity < 0) {
      throw FormatException(
        L10n.trLocale(locale, 'listing.add.error_invalid_stock'),
      );
    }
    if (costPrice != null && costPrice < 0) {
      throw FormatException(
        L10n.trLocale(locale, 'listing.add.error_invalid_cost'),
      );
    }
    if (safeTitle != null) payload['title'] = safeTitle;
    if (price != null) payload['price'] = price;
    if (safeDesc != null) payload['description'] = safeDesc;
    if (safeImageUrl != null) payload['image_url'] = safeImageUrl;
    if (imageUrls != null) {
      payload['image_urls'] = InputSanitizer.sanitizeUrlList(
        imageUrls,
        maxItems: 5,
      );
    }
    if (safeCategoryId != null) {
      payload['category_id'] = int.tryParse(safeCategoryId) ?? safeCategoryId;
    }
    if (safeCondition != null) payload['condition'] = safeCondition;
    if (safeBrand != null) payload['brand'] = safeBrand;
    if (safeSize != null) payload['size'] = safeSize;
    if (safeColor != null) payload['color'] = safeColor;
    if (safeWilaya != null) payload['location_wilaya'] = safeWilaya;
    if (safeDaira != null) payload['location_daira'] = safeDaira;
    if (deliveryOptions != null) {
      payload['delivery_options'] = deliveryOptions
          .map((opt) => InputSanitizer.sanitizeText(opt, maxLength: 20))
          .where((opt) => opt.isNotEmpty)
          .toList();
    }
    if (shippingFree != null) payload['shipping_free'] = shippingFree;
    if (exchangeAfterDelivery != null) {
      payload['exchange_after_delivery'] = exchangeAfterDelivery;
    }
    if (insuranceActive != null) payload['insurance_active'] = insuranceActive;
    if (declaredValue != null) payload['declared_value'] = declaredValue;
    if (weightKg != null) payload['weight_kg'] = weightKg;
    if (heightCm != null) payload['height_cm'] = heightCm;
    if (widthCm != null) payload['width_cm'] = widthCm;
    if (lengthCm != null) payload['length_cm'] = lengthCm;
    if (allowStopdesk != null) {
      payload['allow_stopdesk'] = allowStopdesk;
    }
    if (stockQuantity != null) payload['stock_quantity'] = stockQuantity;
    if (costPrice != null) payload['cost_price'] = costPrice;
    if (isArchived != null) payload['is_archived'] = isArchived;
    if (payload.isEmpty) return;
    await RateLimiter.instance.run(
      'products.update',
      () => supabase
          .from(SupabaseTables.products)
          .update(payload)
          .eq('id', safeId)
          .eq('owner_id', userId),
    );
  }

  Future<void> deleteProduct(dynamic id) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('User must be signed in to delete products.');
    }
    final safeId = InputSanitizer.sanitizeId(id.toString(), maxLength: 64);
    final dynamic productId = id is int ? id : int.tryParse(safeId) ?? safeId;
    await RateLimiter.instance.run(
      'products.delete',
      () => supabase
          .from(SupabaseTables.products)
          .delete()
          .eq('id', productId)
          .eq('owner_id', userId),
    );
  }
}

class _ProductCacheEntry {
  const _ProductCacheEntry(this.timestamp, this.items);
  final DateTime timestamp;
  final List<Product> items;
}
