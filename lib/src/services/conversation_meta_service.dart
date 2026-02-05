import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/conversation.dart';
import 'package:dzmarket/src/services/chat_room_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class ConversationMeta {
  const ConversationMeta({
    required this.roomId,
    required this.productId,
    required this.buyerId,
    required this.sellerId,
    required this.productTitle,
    required this.productImage,
    required this.price,
    required this.status,
    required this.sellerName,
    required this.buyerName,
    required this.sellerAvatar,
    required this.buyerAvatar,
  });

  final String roomId;
  final String productId;
  final String buyerId;
  final String sellerId;
  final String productTitle;
  final String? productImage;
  final double? price;
  final String? status;
  final String sellerName;
  final String buyerName;
  final String? sellerAvatar;
  final String? buyerAvatar;

  String otherName(String? currentUserId) {
    if (currentUserId == null) return sellerName;
    return currentUserId == sellerId ? buyerName : sellerName;
  }

  String? otherAvatar(String? currentUserId) {
    if (currentUserId == null) return sellerAvatar;
    return currentUserId == sellerId ? buyerAvatar : sellerAvatar;
  }
}

class ConversationMetaService {
  static final Map<String, ConversationMeta> _cache = {};

  ConversationMeta? fromRoomId(String roomId) {
    if (!roomId.startsWith('product:')) return null;
    final parts = roomId.split(':');
    if (parts.length < 4) return null;
    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    final productFallback = L10n.trLocale(
      locale,
      'orders.product_fallback',
      params: {'id': parts[1]},
    );
    final sellerFallback = L10n.trLocale(locale, 'seller.fallback');
    final buyerFallback = L10n.trLocale(locale, 'buyer.fallback');
    return ConversationMeta(
      roomId: roomId,
      productId: parts[1],
      buyerId: parts[2],
      sellerId: parts[3],
      productTitle: productFallback,
      productImage: null,
      price: null,
      status: null,
      sellerName: sellerFallback,
      buyerName: buyerFallback,
      sellerAvatar: null,
      buyerAvatar: null,
    );
  }

  Future<Map<String, ConversationMeta>> fetchMany(List<String> roomIds) async {
    final metas = <String, ConversationMeta>{};
    final productRooms = roomIds.where((r) => r.startsWith('product:')).toList();
    if (productRooms.isEmpty) return metas;

    final parsed = productRooms
        .map(fromRoomId)
        .whereType<ConversationMeta>()
        .toList();
    final productIds = parsed.map((m) => m.productId).toSet().toList();
    if (productIds.isEmpty) return metas;
    final userIds = <String>{};
    for (final m in parsed) {
      userIds.add(m.buyerId);
      userIds.add(m.sellerId);
    }

    final products = await RateLimiter.instance.run(
      'conversation.products',
      () => supabase
          .from(SupabaseTables.products)
          .select('id,title,image_url,price,owner_id,status')
          .filter('id', 'in', _inList(productIds)),
    );
    final profiles = await RateLimiter.instance.run(
      'conversation.profiles',
      () => supabase
          .from(SupabaseTables.profiles)
          .select('id,full_name,email,avatar_url')
          .filter('id', 'in', _inList(userIds.toList())),
    );

    final productMap = <String, Map<String, dynamic>>{};
    for (final row in products) {
      productMap[row['id'].toString()] = row;
    }
    final profileMap = <String, Map<String, dynamic>>{};
    for (final row in profiles) {
      profileMap[row['id'].toString()] = row;
    }
    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    final sellerFallback = L10n.trLocale(locale, 'seller.fallback');
    final buyerFallback = L10n.trLocale(locale, 'buyer.fallback');

    for (final base in parsed) {
      final product = productMap[base.productId];
      final sellerProfile = profileMap[base.sellerId];
      final buyerProfile = profileMap[base.buyerId];
      final sellerName =
          (sellerProfile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? sellerProfile!['full_name'] as String
              : (sellerProfile?['email'] as String? ?? sellerFallback);
      final buyerName =
          (buyerProfile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? buyerProfile!['full_name'] as String
              : (buyerProfile?['email'] as String? ?? buyerFallback);
      final meta = ConversationMeta(
        roomId: base.roomId,
        productId: base.productId,
        buyerId: base.buyerId,
        sellerId: base.sellerId,
        productTitle: product?['title']?.toString() ??
            L10n.trLocale(
              locale,
              'orders.product_fallback',
              params: {'id': base.productId},
            ),
        productImage: product?['image_url']?.toString(),
        price: (product?['price'] as num?)?.toDouble(),
        sellerName: sellerName,
        buyerName: buyerName,
        sellerAvatar: sellerProfile?['avatar_url']?.toString(),
        buyerAvatar: buyerProfile?['avatar_url']?.toString(),
        status: product?['status']?.toString(),
      );
      metas[base.roomId] = meta;
      _cache[base.roomId] = meta;
    }
    return metas;
  }

  Future<Map<String, ConversationMeta>> fetchManyForRooms(
    List<ChatRoomSummary> rooms,
  ) async {
    final metas = <String, ConversationMeta>{};
    final filtered = rooms
        .where((room) => room.productId != null && room.productId!.isNotEmpty)
        .toList();
    if (filtered.isEmpty) return metas;

    final productIds =
        filtered.map((room) => room.productId!).toSet().toList();
    final userIds = <String>{};
    for (final room in filtered) {
      userIds.add(room.buyerId);
      userIds.add(room.sellerId);
    }

    final products = await RateLimiter.instance.run(
      'conversation.products',
      () => supabase
          .from(SupabaseTables.products)
          .select('id,title,image_url,price,owner_id,status')
          .filter('id', 'in', _inList(productIds)),
    );
    final profiles = await RateLimiter.instance.run(
      'conversation.profiles',
      () => supabase
          .from(SupabaseTables.profiles)
          .select('id,full_name,email,avatar_url')
          .filter('id', 'in', _inList(userIds.toList())),
    );

    final productMap = <String, Map<String, dynamic>>{};
    for (final row in products) {
      productMap[row['id'].toString()] = row;
    }
    final profileMap = <String, Map<String, dynamic>>{};
    for (final row in profiles) {
      profileMap[row['id'].toString()] = row;
    }
    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    final sellerFallback = L10n.trLocale(locale, 'seller.fallback');
    final buyerFallback = L10n.trLocale(locale, 'buyer.fallback');

    for (final room in filtered) {
      final product = productMap[room.productId];
      final sellerProfile = profileMap[room.sellerId];
      final buyerProfile = profileMap[room.buyerId];
      final sellerName =
          (sellerProfile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? sellerProfile!['full_name'] as String
              : (sellerProfile?['email'] as String? ?? sellerFallback);
      final buyerName =
          (buyerProfile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? buyerProfile!['full_name'] as String
              : (buyerProfile?['email'] as String? ?? buyerFallback);
      final meta = ConversationMeta(
        roomId: room.roomId,
        productId: room.productId!,
        buyerId: room.buyerId,
        sellerId: room.sellerId,
        productTitle: product?['title']?.toString() ??
            L10n.trLocale(
              locale,
              'orders.product_fallback',
              params: {'id': room.productId ?? ''},
            ),
        productImage: product?['image_url']?.toString(),
        price: (product?['price'] as num?)?.toDouble(),
        sellerName: sellerName,
        buyerName: buyerName,
        sellerAvatar: sellerProfile?['avatar_url']?.toString(),
        buyerAvatar: buyerProfile?['avatar_url']?.toString(),
        status: product?['status']?.toString(),
      );
      metas[room.roomId] = meta;
      _cache[room.roomId] = meta;
    }

    return metas;
  }

  Future<Map<String, ConversationMeta>> fetchManyForConversations(
    List<Conversation> conversations,
  ) async {
    final metas = <String, ConversationMeta>{};
    final filtered = conversations
        .where((c) => c.productId != null && c.productId!.isNotEmpty)
        .toList();
    if (filtered.isEmpty) return metas;

    final productIds = filtered.map((c) => c.productId!).toSet().toList();
    final userIds = <String>{};
    for (final c in filtered) {
      if (c.buyerId != null) userIds.add(c.buyerId!);
      if (c.sellerId != null) userIds.add(c.sellerId!);
    }

    final products = await RateLimiter.instance.run(
      'conversation.products',
      () => supabase
          .from(SupabaseTables.products)
          .select('id,title,image_url,price,owner_id,status')
          .filter('id', 'in', _inList(productIds)),
    );
    final profiles = await RateLimiter.instance.run(
      'conversation.profiles',
      () => supabase
          .from(SupabaseTables.profiles)
          .select('id,full_name,email,avatar_url')
          .filter('id', 'in', _inList(userIds.toList())),
    );

    final productMap = <String, Map<String, dynamic>>{};
    for (final row in products) {
      productMap[row['id'].toString()] = row;
    }
    final profileMap = <String, Map<String, dynamic>>{};
    for (final row in profiles) {
      profileMap[row['id'].toString()] = row;
    }
    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    final sellerFallback = L10n.trLocale(locale, 'seller.fallback');
    final buyerFallback = L10n.trLocale(locale, 'buyer.fallback');

    for (final conv in filtered) {
      final product = productMap[conv.productId];
      final sellerProfile = conv.sellerId != null
          ? profileMap[conv.sellerId]
          : null;
      final buyerProfile =
          conv.buyerId != null ? profileMap[conv.buyerId] : null;
      final sellerName =
          (sellerProfile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? sellerProfile!['full_name'] as String
              : (sellerProfile?['email'] as String? ?? sellerFallback);
      final buyerName =
          (buyerProfile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? buyerProfile!['full_name'] as String
              : (buyerProfile?['email'] as String? ?? buyerFallback);
      final meta = ConversationMeta(
        roomId: conv.id,
        productId: conv.productId!,
        buyerId: conv.buyerId ?? '',
        sellerId: conv.sellerId ?? '',
        productTitle: product?['title']?.toString() ??
            L10n.trLocale(
              locale,
              'orders.product_fallback',
              params: {'id': conv.productId ?? ''},
            ),
        productImage: product?['image_url']?.toString(),
        price: (product?['price'] as num?)?.toDouble(),
        sellerName: sellerName,
        buyerName: buyerName,
        sellerAvatar: sellerProfile?['avatar_url']?.toString(),
        buyerAvatar: buyerProfile?['avatar_url']?.toString(),
        status: product?['status']?.toString(),
      );
      metas[conv.id] = meta;
      _cache[conv.id] = meta;
    }
    return metas;
  }

  Future<ConversationMeta?> fetch(String roomId) async {
    if (_cache.containsKey(roomId)) return _cache[roomId];
    final base = fromRoomId(roomId);
    if (base == null) return null;
    final metas = await fetchMany([roomId]);
    return metas[roomId] ?? base;
  }

  String _inList(List<String> ids) {
    final cleaned = ids.where((id) => id.trim().isNotEmpty).toList();
    final quoted = cleaned.map((id) => '"$id"').join(',');
    return '($quoted)';
  }
}
