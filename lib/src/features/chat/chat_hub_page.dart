import 'package:dzmarket/src/features/chat/chat_room_page.dart';
import 'package:dzmarket/src/models/chat_message.dart';
import 'package:dzmarket/src/models/conversation.dart';
import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:dzmarket/src/services/conversation_meta_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
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
  final RefreshController _refreshController = RefreshController();
  static const int _maxConversations = 30;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.tr(context, 'chat.title'))),
        body: Center(
          child: Text(L10n.tr(context, 'chat.login_required')),
        ),
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
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '${L10n.tr(context, 'chat.load_error')}\n${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final conversations = snapshot.data ?? const [];
                  if (conversations.isEmpty) {
                    return Center(
                      child: Text(L10n.tr(context, 'chat.empty')),
                    );
                  }

                  return StreamBuilder<Map<String, ReadState>>(
                    stream: _repo.watchReadStates(),
                    builder: (context, readSnap) {
                      final readMap = readSnap.data ?? const {};
                      return FutureBuilder<Map<String, ConversationMeta>>(
                        future: _metaService.fetchManyForConversations(
                          conversations,
                        ),
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
                              _metaService.fetchManyForConversations(conversations);
                              setState(() {});
                            });
                          }

                          Widget buildList(List<Conversation> list,
                              {required bool archivedList}) {
                            final filtered = list.where((c) {
                              if (_query.isEmpty) return true;
                              final meta = metaMap[c.id];
                              final title = meta?.productTitle ?? '';
                              final seller = meta?.sellerName ?? '';
                              return title.toLowerCase().contains(_query) ||
                                  seller.toLowerCase().contains(_query);
                            }).toList();
                            final limited = filtered.take(_maxConversations).toList();
                            if (limited.isEmpty) {
                              return Center(
                                child: Text(L10n.tr(context, 'chat.no_results')),
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
                                  final unread = !archivedList &&
                                      conv.lastMessageAt != null &&
                                      (read?.lastReadAt == null ||
                                          conv.lastMessageAt!
                                              .isAfter(read!.lastReadAt!));
                                  final rawSubtitle =
                                      conv.lastMessageText ?? meta?.productTitle ?? '';
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
                                    padding:
                                        const EdgeInsets.only(right: 20),
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
                                      await _repo.restoreConversation(conv.id);
                                    } else {
                                      await _repo.deleteConversation(conv.id);
                                    }
                                  },
                                  child: ListTile(
                                    leading: meta?.productImage != null
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Image.network(
                                              meta!.productImage!,
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.chat_bubble_outline),
                                    title: Text(
                                      meta?.productTitle ??
                                          L10n.tr(context, 'chat.fallback_title'),
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
                                                conv.lastMessageAt!
                                                    .toLocal()),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall,
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
}
