import 'package:dzmarket/src/utils/public_storage_url_resolver.dart';

class Product {
  const Product({
    required this.id,
    required this.title,
    required this.price,
    required this.ownerId,
    this.costPrice,
    this.categoryId,
    this.description,
    this.imageUrl,
    this.imageUrls = const [],
    this.category,
    this.categorySlug,
    this.categoryNameFr,
    this.categoryNameAr,
    this.condition,
    this.brand,
    this.size,
    this.color,
    this.searchTags = const [],
    this.searchKeywords,
    this.locationWilaya,
    this.locationDaira,
    this.deliveryOptions = const [],
    this.isNegotiable = true,
    this.shippingFree = false,
    this.exchangeAfterDelivery = false,
    this.insuranceActive = false,
    this.declaredValue,
    this.weightKg,
    this.heightCm,
    this.widthCm,
    this.lengthCm,
    this.allowStopdesk = true,
    this.stockQuantity = 1,
    this.soldCount = 0,
    this.isArchived = false,
    this.moderationStatus,
    this.createdAt,
  });

  final String id;
  final String title;
  final double price;
  final String ownerId;
  final double? costPrice;
  final String? categoryId;
  final String? description;
  final String? imageUrl;
  final List<String> imageUrls;
  final String? category;
  final String? categorySlug;
  final String? categoryNameFr;
  final String? categoryNameAr;
  final String? condition;
  final String? brand;
  final String? size;
  final String? color;
  final List<String> searchTags;
  final String? searchKeywords;
  final String? locationWilaya;
  final String? locationDaira;
  final List<String> deliveryOptions;
  final bool isNegotiable;
  final bool shippingFree;
  final bool exchangeAfterDelivery;
  final bool insuranceActive;
  final double? declaredValue;
  final int? weightKg;
  final int? heightCm;
  final int? widthCm;
  final int? lengthCm;
  final bool allowStopdesk;
  final int stockQuantity;
  final int soldCount;
  final bool isArchived;
  final String? moderationStatus;
  final DateTime? createdAt;

  static bool isLikelyUnsupportedImageUrl(String? rawUrl) {
    final raw = (rawUrl ?? '').trim().toLowerCase();
    if (raw.isEmpty) return false;
    final uri = Uri.tryParse(raw);
    final path = (uri?.path ?? raw).toLowerCase();
    return path.endsWith('.heic') ||
        path.endsWith('.heif') ||
        raw.contains('format=heic') ||
        raw.contains('format=heif');
  }

  List<String> displayableImageUrls({String? fallback}) {
    final merged = <String>[];
    final seen = <String>{};

    void addIfNew(String? raw) {
      final value = normalizePublicStorageUrl(raw);
      if (value.isEmpty) return;
      if (seen.add(value)) {
        merged.add(value);
      }
    }

    for (final url in imageUrls) {
      addIfNew(url);
    }
    addIfNew(imageUrl);

    final supported = merged
        .where((url) => !isLikelyUnsupportedImageUrl(url))
        .toList();
    if (supported.isNotEmpty) return supported;
    if ((fallback ?? '').trim().isNotEmpty) {
      final fallbackValue = fallback!.trim();
      if (!merged.contains(fallbackValue)) return [fallbackValue];
    }
    if (merged.isNotEmpty) return merged;
    return const [];
  }

  String? firstDisplayableImageUrl({String? fallback}) {
    final items = displayableImageUrls(fallback: fallback);
    return items.isEmpty ? null : items.first;
  }

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id']?.toString() ?? '',
    title: json['title'] as String? ?? '',
    price: (json['price'] as num?)?.toDouble() ?? 0,
    ownerId: json['owner_id'] as String? ?? '',
    costPrice: (json['cost_price'] as num?)?.toDouble(),
    categoryId: json['category_id']?.toString(),
    description: json['description'] as String?,
    imageUrl: json['image_url'] as String?,
    imageUrls: ((json['image_urls'] as List?) ?? const [])
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(),
    category: json['category'] as String?,
    categorySlug: (json['categories']?['slug'] ?? json['category_slug'])
        ?.toString(),
    categoryNameFr: (json['categories']?['name_fr'] ?? json['category_name_fr'])
        ?.toString(),
    categoryNameAr: (json['categories']?['name_ar'] ?? json['category_name_ar'])
        ?.toString(),
    condition: json['condition'] as String?,
    brand: json['brand'] as String?,
    size: json['size'] as String?,
    color: json['color'] as String?,
    searchTags: ((json['search_tags'] as List?) ?? const [])
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(),
    searchKeywords: json['search_keywords'] as String?,
    locationWilaya: json['location_wilaya'] as String?,
    locationDaira: json['location_daira'] as String?,
    deliveryOptions: ((json['delivery_options'] as List?) ?? const [])
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(),
    isNegotiable: json['is_negotiable'] as bool? ?? true,
    shippingFree: json['shipping_free'] as bool? ?? false,
    exchangeAfterDelivery: json['exchange_after_delivery'] as bool? ?? false,
    insuranceActive: json['insurance_active'] as bool? ?? false,
    declaredValue: (json['declared_value'] as num?)?.toDouble(),
    weightKg: (json['weight_kg'] as num?)?.toInt(),
    heightCm: (json['height_cm'] as num?)?.toInt(),
    widthCm: (json['width_cm'] as num?)?.toInt(),
    lengthCm: (json['length_cm'] as num?)?.toInt(),
    allowStopdesk: json['allow_stopdesk'] as bool? ?? true,
    stockQuantity: (json['stock_quantity'] as num?)?.toInt() ?? 1,
    soldCount: (json['sold_count'] as num?)?.toInt() ?? 0,
    isArchived: json['is_archived'] as bool? ?? false,
    moderationStatus: json['moderation_status'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
  );
}
