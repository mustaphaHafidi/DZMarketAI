import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/chat/chat_room_page.dart';
import 'package:dzmarket/src/services/chat_room_service.dart';
import 'package:dzmarket/src/services/conversation_meta_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatHubPage extends StatefulWidget {
  const ChatHubPage({super.key});

  @override
  State<ChatHubPage> createState() => _ChatHubPageState();
}

class _ChatHubPageState extends State<ChatHubPage> {
  static final ChatRoomService _roomService = ChatRoomService();
  static final ConversationMetaService _metaService = ConversationMetaService();

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'Messages', 'Messages')),
      ),
      body: userId == null
          ? Center(
              child: Text(
                L10n.t(
                  context,
                  'Connectez-vous pour voir vos messages',
                  'Connectez-vous pour voir vos messages',
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: L10n.t(context, 'Rechercher', 'Rechercher'),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<ChatRoomSummary>>(
                    stream: _roomService.streamRoomsForUser(userId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            L10n.t(
                              context,
                              'Erreur de chargement',
                              'Erreur de chargement',
                            ),
                          ),
                        );
                      }
                      final rooms = snapshot.data ?? const [];
                      if (rooms.isEmpty) {
                        return Center(
                          child: Text(
                            L10n.t(
                              context,
                              'Aucune conversation',
                              'Aucune conversation',
                            ),
                          ),
                        );
                      }
                      return FutureBuilder<Map<String, ConversationMeta>>(
                        future: _metaService.fetchManyForRooms(rooms),
                        builder: (context, metaSnap) {
                          final metaMap = metaSnap.data ?? const {};
                          final items = _buildItems(
                            rooms: rooms,
                            metaMap: metaMap,
                            userId: userId,
                            query: _query,
                          );
                          if (items.isEmpty) {
                            return Center(
                              child: Text(
                                L10n.t(
                                  context,
                                  'Aucun resultat',
                                  'Aucun resultat',
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return Dismissible(
                                key: ValueKey(item.room.roomId),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  color: Theme.of(context).colorScheme.error,
                                  alignment: Alignment.centerRight,
                                  padding:
                                      const EdgeInsets.only(right: 20),
                                  child: const Icon(
                                    Icons.visibility_off_outlined,
                                    color: Colors.white,
                                  ),
                                ),
                                confirmDismiss: (_) async {
                                  return await _confirmHide(context);
                                },
                                onDismissed: (_) async {
                                  await _roomService
                                      .hideRoom(item.room.roomId);
                                },
                                child: _ConversationRow(
                                  item: item,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ChatRoomPage(
                                          roomId: item.room.roomId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  List<_ConversationItem> _buildItems({
    required List<ChatRoomSummary> rooms,
    required Map<String, ConversationMeta> metaMap,
    required String userId,
    required String query,
  }) {
    final items = <_ConversationItem>[];
    for (final room in rooms) {
      final meta = metaMap[room.roomId];
      final title = meta?.productTitle ?? 'Annonce';
      final sellerName = meta?.sellerName ?? 'Vendeur';
      if (query.isNotEmpty &&
          !title.toLowerCase().contains(query) &&
          !sellerName.toLowerCase().contains(query)) {
        continue;
      }
      items.add(_ConversationItem(room: room, meta: meta));
    }
    items.sort((a, b) {
      final aTime = a.room.lastMessageAt ??
          a.room.updatedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.room.lastMessageAt ??
          b.room.updatedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return items;
  }

  Future<bool> _confirmHide(BuildContext context) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.t(context, 'Supprimer la conversation', 'Supprimer la conversation')),
        content: Text(L10n.t(
            context,
            'Vous pouvez la retrouver en relancant le contact.',
            'Vous pouvez la retrouver en relancant le contact.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.t(context, 'Annuler', 'Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.t(context, 'Supprimer', 'Supprimer')),
          ),
        ],
      ),
    );
    return res ?? false;
  }
}

class _ConversationItem {
  const _ConversationItem({required this.room, required this.meta});

  final ChatRoomSummary room;
  final ConversationMeta? meta;

  int unreadCount(String userId) {
    if (room.buyerId == userId) return room.unreadByBuyer;
    if (room.sellerId == userId) return room.unreadBySeller;
    return 0;
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.item, required this.onTap});

  final _ConversationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = item.meta;
    final room = item.room;
    final userId = supabase.auth.currentUser?.id;
    final title = meta?.productTitle ?? 'Annonce';
    final sellerName = meta?.sellerName ?? 'Vendeur';
    final avatarUrl = InputSanitizer.safeUrl(meta?.sellerAvatar);
    final preview = InputSanitizer.safeUrl(meta?.productImage);
    final price = meta?.price;
    final unread = userId == null ? 0 : item.unreadCount(userId);
    final isUnread = unread > 0;
    final lastLine = room.lastMessageType == 'image'
        ? L10n.t(context, '[Photo]', '[Photo]')
        : (room.lastMessage ?? '');
    final timeText = _formatTime(room.lastMessageAt ?? room.updatedAt);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: preview == null
                      ? Container(
                          width: 54,
                          height: 54,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.image_outlined, size: 20),
                        )
                      : CachedNetworkImage(
                            imageUrl: preview,
                            width: 54,
                            height: 54,
                            fit: BoxFit.cover,
                            imageRenderMethodForWeb:
                                ImageRenderMethodForWeb.HtmlImage,
                            errorWidget: (_, __, ___) =>
                                const Icon(Icons.image_outlined),
                          ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor:
                        Theme.of(context).colorScheme.surface,
                    child: CircleAvatar(
                      radius: 10,
                        backgroundImage: avatarUrl != null
                            ? CachedNetworkImageProvider(
                                avatarUrl,
                                imageRenderMethodForWeb:
                                    ImageRenderMethodForWeb.HtmlImage,
                              )
                            : null,
                      child: avatarUrl == null
                          ? const Icon(Icons.person, size: 12)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sellerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastLine.isEmpty
                        ? L10n.t(context, 'Nouveau contact', 'Nouveau contact')
                        : lastLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeText,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 6),
                if (price != null)
                  Text(
                    'DA ${price.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                if (unread > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      unread.toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    final now = DateTime.now();
    if (now.year == local.year &&
        now.month == local.month &&
        now.day == local.day) {
      return DateFormat.Hm().format(local);
    }
    return DateFormat('dd/MM').format(local);
  }
}
