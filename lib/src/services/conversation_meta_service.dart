import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/services/chat_room_service.dart';
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
    return ConversationMeta(
      roomId: roomId,
      productId: parts[1],
      buyerId: parts[2],
      sellerId: parts[3],
      productTitle: 'Produit',
      productImage: null,
      price: null,
      sellerName: 'Vendeur',
      buyerName: 'Acheteur',
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
          .select('id,title,image_url,price,owner_id')
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

    for (final base in parsed) {
      final product = productMap[base.productId];
      final sellerProfile = profileMap[base.sellerId];
      final buyerProfile = profileMap[base.buyerId];
      final sellerName =
          (sellerProfile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? sellerProfile!['full_name'] as String
              : (sellerProfile?['email'] as String? ?? 'Vendeur');
      final buyerName =
          (buyerProfile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? buyerProfile!['full_name'] as String
              : (buyerProfile?['email'] as String? ?? 'Acheteur');
      final meta = ConversationMeta(
        roomId: base.roomId,
        productId: base.productId,
        buyerId: base.buyerId,
        sellerId: base.sellerId,
        productTitle: product?['title']?.toString() ?? 'Produit',
        productImage: product?['image_url']?.toString(),
        price: (product?['price'] as num?)?.toDouble(),
        sellerName: sellerName,
        buyerName: buyerName,
        sellerAvatar: sellerProfile?['avatar_url']?.toString(),
        buyerAvatar: buyerProfile?['avatar_url']?.toString(),
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
          .select('id,title,image_url,price,owner_id')
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

    for (final room in filtered) {
      final product = productMap[room.productId];
      final sellerProfile = profileMap[room.sellerId];
      final buyerProfile = profileMap[room.buyerId];
      final sellerName =
          (sellerProfile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? sellerProfile!['full_name'] as String
              : (sellerProfile?['email'] as String? ?? 'Vendeur');
      final buyerName =
          (buyerProfile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? buyerProfile!['full_name'] as String
              : (buyerProfile?['email'] as String? ?? 'Acheteur');
      final meta = ConversationMeta(
        roomId: room.roomId,
        productId: room.productId!,
        buyerId: room.buyerId,
        sellerId: room.sellerId,
        productTitle: product?['title']?.toString() ?? 'Produit',
        productImage: product?['image_url']?.toString(),
        price: (product?['price'] as num?)?.toDouble(),
        sellerName: sellerName,
        buyerName: buyerName,
        sellerAvatar: sellerProfile?['avatar_url']?.toString(),
        buyerAvatar: buyerProfile?['avatar_url']?.toString(),
      );
      metas[room.roomId] = meta;
      _cache[room.roomId] = meta;
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
