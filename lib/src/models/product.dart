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
    this.locationWilaya,
    this.locationDaira,
    this.deliveryOptions = const [],
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
  final String? locationWilaya;
  final String? locationDaira;
  final List<String> deliveryOptions;
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
    locationWilaya: json['location_wilaya'] as String?,
    locationDaira: json['location_daira'] as String?,
    deliveryOptions: ((json['delivery_options'] as List?) ?? const [])
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(),
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
