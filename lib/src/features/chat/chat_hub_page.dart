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
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) {
                  _searchDebounce?.cancel();
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
                              final seller = meta?.sellerName ?? '';
                              return title.toLowerCase().contains(_query) ||
                                  seller.toLowerCase().contains(_query);
                            }).toList();
                            final limited = filtered
                                .take(_maxConversations)
                                .toList();
                            if (limited.isEmpty) {
                              return Center(
                                child: Text(
                                  L10n.tr(context, 'chat.no_results'),
                                ),
                              );
                            }
                            return RefreshIndicator(
                              onRefresh: manualRefresh,
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
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      color: archivedList
                                          ? Colors.green
                                          : Theme.of(context).colorScheme.error,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 20),
                                      child: Icon(
                                        archivedList
                                            ? Icons.undo
                                            : Icons.visibility_off_outlined,
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
                                        await _repo.deleteConversation(conv.id);
                                      }
                                    },
                                    child: ListTile(
                                      leading: meta?.productImage != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: CachedNetworkImage(
                                                imageUrl: meta!.productImage!,
                                                width: 48,
                                                height: 48,
                                                fit: BoxFit.cover,
                                                memCacheWidth:
                                                    NetworkPreferencesService
                                                        .instance
                                                        .listImageMemCacheWidth,
                                                memCacheHeight:
                                                    NetworkPreferencesService
                                                        .instance
                                                        .listImageMemCacheHeight,
                                                fadeInDuration:
                                                    NetworkPreferencesService
                                                        .instance
                                                        .imageFadeInDuration,
                                                fadeOutDuration:
                                                    NetworkPreferencesService
                                                        .instance
                                                        .imageFadeOutDuration,
                                                placeholder: (context, _) =>
                                                    Container(
                                                      width: 48,
                                                      height: 48,
                                                      color:
                                                          Colors.grey.shade300,
                                                    ),
                                                errorWidget: (context, _, __) =>
                                                    Container(
                                                      width: 48,
                                                      height: 48,
                                                      color:
                                                          Colors.grey.shade300,
                                                      child: const Icon(
                                                        Icons
                                                            .image_not_supported,
                                                      ),
                                                    ),
                                              ),
                                            )
                                          : const Icon(
                                              Icons.chat_bubble_outline,
                                            ),
                                      title: Text(
                                        meta?.productTitle ??
                                            L10n.tr(
                                              context,
                                              'chat.fallback_title',
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (conv.lastMessageAt != null)
                                            Text(
                                              DateFormat.Hm().format(
                                                conv.lastMessageAt!.toLocal(),
                                              ),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelSmall,
                                            ),
                                          if (unread)
                                            const CircleAvatar(
                                              radius: 6,
                                              backgroundColor: Colors.red,
                                            ),
                                        ],
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
}
