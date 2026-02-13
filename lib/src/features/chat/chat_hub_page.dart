import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dzmarket/src/features/chat/chat_room_page.dart';
import 'package:dzmarket/src/models/chat_message.dart';
import 'package:dzmarket/src/models/conversation.dart';
import 'package:dzmarket/src/services/app_error_service.dart';
import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:dzmarket/src/services/connectivity_service.dart';
import 'package:dzmarket/src/services/conversation_meta_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/network_preferences_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/widgets/refresh_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatHubPage extends StatefulWidget {
  const ChatHubPage({super.key});

  @override
  State<ChatHubPage> createState() => _ChatHubPageState();
}

class _ChatHubPageState extends State<ChatHubPage> {
  final ChatRepository _repo = ChatRepository();
  final ConversationMetaService _metaService = ConversationMetaService();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _searchDebounce;
  final RefreshController _refreshController = RefreshController();
  static const int _maxConversations = 30;
  Future<Map<String, ConversationMeta>>? _metaFuture;
  String _metaKey = '';
  String? _lastLoggedLoadError;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.tr(context, 'chat.title'))),
        body: Center(child: Text(L10n.tr(context, 'chat.login_required'))),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.tr(context, 'chat.title')),
          bottom: TabBar(
            tabs: [
              Tab(text: L10n.tr(context, 'chat.tab_messages')),
              Tab(text: L10n.tr(context, 'chat.tab_archived')),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: L10n.tr(context, 'chat.search'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: L10n.tr(
                            context,
                            'common.clear',
                            fallback: 'Effacer',
                          ),
                          onPressed: () {
                            _searchDebounce?.cancel();
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) {
                  _searchDebounce?.cancel();
                  setState(() {});
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      if (!mounted) return;
                      setState(() => _query = v.trim().toLowerCase());
                    },
                  );
                },
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: ConnectivityService.instance.isOnline,
              builder: (context, isOnline, _) {
                if (isOnline) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            L10n.tr(
                              context,
                              'common.offline_chip',
                              fallback: 'Hors ligne',
                            ),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: StreamBuilder<List<Conversation>>(
                stream: _repo.watchConversations(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    _logLoadError(snapshot.error, snapshot.stackTrace);
                    final offline =
                        !ConnectivityService.instance.isOnline.value ||
                        _looksOffline(snapshot.error);
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              offline
                                  ? Icons.wifi_off_rounded
                                  : Icons.error_outline,
                              size: 28,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              L10n.tr(
                                context,
                                offline
                                    ? 'chat.offline_reconnecting'
                                    : 'chat.load_error_friendly',
                                fallback: L10n.tr(context, 'chat.load_error'),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => setState(() {
                                _metaFuture = null;
                                _metaKey = '';
                              }),
                              child: Text(L10n.tr(context, 'common.retry')),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final conversations = snapshot.data ?? const [];
                  if (conversations.isEmpty) {
                    return Center(child: Text(L10n.tr(context, 'chat.empty')));
                  }

                  return StreamBuilder<Map<String, ReadState>>(
                    stream: _repo.watchReadStates(),
                    builder: (context, readSnap) {
                      final readMap = readSnap.data ?? const {};
                      final nextKey = conversations
                          .map((c) => c.id)
                          .toList()
                          .join(',');
                      if (_metaFuture == null || _metaKey != nextKey) {
                        _metaFuture = _metaService.fetchManyForConversations(
                          conversations,
                        );
                        _metaKey = nextKey;
                      }
                      return FutureBuilder<Map<String, ConversationMeta>>(
                        future: _metaFuture,
                        builder: (context, metaSnap) {
                          final metaMap = metaSnap.data ?? const {};
                          final visible = conversations
                              .where((c) => !c.isHiddenForUser(userId))
                              .toList();
                          final archived = conversations
                              .where((c) => c.isHiddenForUser(userId))
                              .toList();

                          Future<void> manualRefresh() async {
                            await _refreshController.run(context, () async {
                              // force fetch conversations snapshot to resync stream/metas
                              await supabase
                                  .from('conversations')
                                  .select('id,last_message_at')
                                  .limit(50);
                              _metaService.fetchManyForConversations(
                                conversations,
                              );
                              setState(() {});
                            });
                          }

                          Widget buildList(
                            List<Conversation> list, {
                            required bool archivedList,
                          }) {
                            final filtered = list.where((c) {
                              if (_query.isEmpty) return true;
                              final meta = metaMap[c.id];
                              final title = meta?.productTitle ?? '';
                              final participant =
                                  meta?.otherName(userId) ??
                                  meta?.sellerName ??
                                  '';
                              final preview =
                                  c.lastMessageText ?? meta?.productTitle ?? '';
                              return title.toLowerCase().contains(_query) ||
                                  participant.toLowerCase().contains(_query) ||
                                  preview.toLowerCase().contains(_query);
                            }).toList();
                            final limited = filtered
                                .take(_maxConversations)
                                .toList();
                            if (limited.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.forum_outlined,
                                        size: 28,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        L10n.tr(context, 'chat.no_results'),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            final unreadCount = limited.where((conv) {
                              if (archivedList || conv.lastMessageAt == null) {
                                return false;
                              }
                              final read = readMap[conv.id];
                              return read?.lastReadAt == null ||
                                  conv.lastMessageAt!.isAfter(
                                    read!.lastReadAt!,
                                  );
                            }).length;
                            return RefreshIndicator(
                              onRefresh: manualRefresh,
                              child: Column(
                                children: [
                                  if (!archivedList)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        2,
                                        16,
                                        8,
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            L10n.tr(
                                              context,
                                              'chat.tab_messages',
                                            ),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelLarge,
                                          ),
                                          const Spacer(),
                                          if (unreadCount > 0)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                '$unreadCount',
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onPrimaryContainer,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: limited.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final conv = limited[index];
                                        final meta = metaMap[conv.id];
                                        final read = readMap[conv.id];
                                        final unread =
                                            !archivedList &&
                                            conv.lastMessageAt != null &&
                                            (read?.lastReadAt == null ||
                                                conv.lastMessageAt!.isAfter(
                                                  read!.lastReadAt!,
                                                ));
                                        final rawSubtitle =
                                            conv.lastMessageText ??
                                            meta?.productTitle ??
                                            '';
                                        final subtitle = rawSubtitle.isEmpty
                                            ? ''
                                            : L10n.tr(
                                                context,
                                                rawSubtitle,
                                                fallback: rawSubtitle,
                                              );
                                        return Dismissible(
                                          key: ValueKey(conv.id),
                                          direction:
                                              DismissDirection.endToStart,
                                          background: Container(
                                            color: archivedList
                                                ? Colors.green
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                            alignment: Alignment.centerRight,
                                            padding: const EdgeInsets.only(
                                              right: 20,
                                            ),
                                            child: Icon(
                                              archivedList
                                                  ? Icons.undo
                                                  : Icons
                                                        .visibility_off_outlined,
                                              color: Colors.white,
                                            ),
                                          ),
                                          confirmDismiss: (_) async => true,
                                          onDismissed: (_) async {
                                            if (archivedList) {
                                              await _repo.restoreConversation(
                                                conv.id,
                                              );
                                            } else {
                                              await _repo.deleteConversation(
                                                conv.id,
                                              );
                                            }
                                          },
                                          child: _ConversationListItem(
                                            title:
                                                meta?.productTitle ??
                                                L10n.tr(
                                                  context,
                                                  'chat.fallback_title',
                                                ),
                                            subtitle: subtitle,
                                            participantName:
                                                meta?.otherName(userId) ??
                                                meta?.sellerName ??
                                                '',
                                            productImage: meta?.productImage,
                                            participantAvatar: meta
                                                ?.otherAvatar(userId),
                                            unread: unread,
                                            archived: archivedList,
                                            timeLabel: _formatConversationTime(
                                              context,
                                              conv.lastMessageAt,
                                            ),
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => ChatRoomPage(
                                                    conversationId: conv.id,
                                                    productId: conv.productId,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return TabBarView(
                            children: [
                              buildList(visible, archivedList: false),
                              buildList(archived, archivedList: true),
                            ],
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
      ),
    );
  }

  void _logLoadError(Object? error, StackTrace? stack) {
    if (error == null) return;
    final text = error.toString();
    if (_lastLoggedLoadError == text) return;
    _lastLoggedLoadError = text;
    unawaited(
      AppErrorService.instance.logError(
        error,
        stack,
        context: 'chat_hub.watch_conversations',
      ),
    );
  }

  bool _looksOffline(Object? error) {
    final e = error?.toString().toLowerCase() ?? '';
    return e.contains('socketexception') ||
        e.contains('failed host lookup') ||
        e.contains('no address associated with hostname') ||
        e.contains('network is unreachable') ||
        e.contains('websocketchannelexception');
  }

  String _formatConversationTime(BuildContext context, DateTime? dateTime) {
    if (dateTime == null) return '';
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) {
      return DateFormat.Hm().format(local);
    }
    return DateFormat('dd/MM').format(local);
  }
}

class _ConversationListItem extends StatelessWidget {
  const _ConversationListItem({
    required this.title,
    required this.subtitle,
    required this.participantName,
    required this.productImage,
    required this.participantAvatar,
    required this.unread,
    required this.archived,
    required this.timeLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String participantName;
  final String? productImage;
  final String? participantAvatar;
  final bool unread;
  final bool archived;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _ConversationThumb(productImage: productImage),
                ),
                if (unread)
                  Positioned(
                    top: -1,
                    right: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                if (participantAvatar != null && participantAvatar!.isNotEmpty)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: participantAvatar!,
                          width: 18,
                          height: 18,
                          fit: BoxFit.cover,
                          memCacheWidth: NetworkPreferencesService
                              .instance
                              .listImageMemCacheWidth,
                          memCacheHeight: NetworkPreferencesService
                              .instance
                              .listImageMemCacheHeight,
                          fadeInDuration: NetworkPreferencesService
                              .instance
                              .imageFadeInDuration,
                          fadeOutDuration: NetworkPreferencesService
                              .instance
                              .imageFadeOutDuration,
                          errorWidget: (_, __, ___) =>
                              const Icon(Icons.person, size: 12),
                        ),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (timeLabel.isNotEmpty)
                        Text(
                          timeLabel,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    participantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: unread
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                        ),
                      ),
                      if (archived) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.visibility_off_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationThumb extends StatelessWidget {
  const _ConversationThumb({required this.productImage});

  final String? productImage;

  @override
  Widget build(BuildContext context) {
    if (productImage != null && productImage!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: productImage!,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        memCacheWidth:
            NetworkPreferencesService.instance.listImageMemCacheWidth,
        memCacheHeight:
            NetworkPreferencesService.instance.listImageMemCacheHeight,
        fadeInDuration: NetworkPreferencesService.instance.imageFadeInDuration,
        fadeOutDuration:
            NetworkPreferencesService.instance.imageFadeOutDuration,
        placeholder: (context, _) =>
            Container(width: 56, height: 56, color: Colors.grey.shade300),
        errorWidget: (context, _, __) => Container(
          width: 56,
          height: 56,
          color: Colors.grey.shade300,
          child: const Icon(Icons.image_not_supported),
        ),
      );
    }
    return Container(
      width: 56,
      height: 56,
      color: Colors.grey.shade200,
      child: const Icon(Icons.chat_bubble_outline),
    );
  }
}
