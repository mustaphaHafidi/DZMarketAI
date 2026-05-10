import 'package:dzmarket/src/features/chat/chat_hub_page.dart';
import 'package:dzmarket/src/features/listings/listings_page.dart';
import 'package:dzmarket/src/features/profile/profile_page.dart';
import 'package:dzmarket/src/models/chat_message.dart';
import 'package:dzmarket/src/models/conversation.dart';
import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/notification_inbox_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/widgets/web_frame.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom navigation shell: Browse, Chat, Profile.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 'listings'});

  final String initialTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _tabs = ['listings', 'chat', 'profile'];
  static const double _desktopBreakpoint = 920;
  static final ChatRepository _chatRepository = ChatRepository();
  static final NotificationInboxService _notificationInboxService =
      NotificationInboxService();
  late int _currentIndex = _tabIndexFor(widget.initialTab);

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _currentIndex = _tabIndexFor(widget.initialTab);
    }
  }

  void _onTabSelected(int index) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null && index != 0) {
      final from = Uri.encodeComponent('/?tab=${_tabs[index]}');
      context.go('/sign-in?from=$from');
      return;
    }
    setState(() {
      _currentIndex = index;
    });
    context.go('/?tab=${_tabs[index]}');
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const ListingsPage(), // index 0: Browse/Product list
      const ChatHubPage(), // index 1: Chat hub
      const ProfilePage(), // index 2: Profile
    ];
    final userId = supabase.auth.currentUser?.id;
    final shellBody = IndexedStack(index: _currentIndex, children: pages);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
        if (!isDesktop) {
          return Scaffold(
            body: shellBody,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: _onTabSelected,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.storefront_outlined),
                  label: L10n.tr(context, 'nav.browse', fallback: 'Parcourir'),
                ),
                NavigationDestination(
                  icon: _ChatBadge(
                    userId: userId,
                    chatRepository: _chatRepository,
                  ),
                  label: L10n.tr(context, 'nav.chat', fallback: 'Chat'),
                ),
                NavigationDestination(
                  icon: _ProfileBadge(
                    userId: userId,
                    inboxService: _notificationInboxService,
                  ),
                  label: L10n.tr(context, 'nav.profile', fallback: 'Profil'),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _onTabSelected,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(Icons.storefront_outlined),
                      label: Text(
                        L10n.tr(context, 'nav.browse', fallback: 'Parcourir'),
                      ),
                    ),
                    NavigationRailDestination(
                      icon: _ChatBadge(
                        userId: userId,
                        chatRepository: _chatRepository,
                      ),
                      label: Text(
                        L10n.tr(context, 'nav.chat', fallback: 'Chat'),
                      ),
                    ),
                    NavigationRailDestination(
                      icon: _ProfileBadge(
                        userId: userId,
                        inboxService: _notificationInboxService,
                      ),
                      label: Text(
                        L10n.tr(context, 'nav.profile', fallback: 'Profil'),
                      ),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: WebFrame(child: shellBody)),
              ],
            ),
          ),
        );
      },
    );
  }

  int _tabIndexFor(String tab) {
    final index = _tabs.indexOf(tab);
    if (index == -1) return 0;
    return index;
  }
}

class _ChatBadge extends StatelessWidget {
  const _ChatBadge({required this.userId, required this.chatRepository});

  final String? userId;
  final ChatRepository chatRepository;

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return const Icon(Icons.chat_bubble_outline);
    }
    return StreamBuilder<List<Conversation>>(
      stream: chatRepository.watchConversations(),
      builder: (context, snapshot) {
        final conversations = snapshot.data ?? const [];
        return StreamBuilder<Map<String, ReadState>>(
          stream: chatRepository.watchReadStates(),
          builder: (context, readSnap) {
            final readMap = readSnap.data ?? const {};
            final unread = conversations.fold<int>(0, (sum, c) {
              if (c.hasUnreadCounters) {
                return sum + c.unreadCountForUser(userId!);
              }
              final read = readMap[c.id];
              final fallback =
                  c.lastMessageAt != null &&
                  (read?.lastReadAt == null ||
                      c.lastMessageAt!.isAfter(read!.lastReadAt!));
              return sum + (fallback ? 1 : 0);
            });
            if (unread <= 0) {
              return const Icon(Icons.chat_bubble_outline);
            }
            return Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble_outline),
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unread.toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({required this.userId, required this.inboxService});

  final String? userId;
  final NotificationInboxService inboxService;

  @override
  Widget build(BuildContext context) {
    if (userId == null) return const Icon(Icons.person_outline);
    return StreamBuilder<int>(
      stream: inboxService.watchUnreadCount(),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        if (unread <= 0) return const Icon(Icons.person_outline);
        final label = unread > 99 ? '99+' : unread.toString();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.person_outline),
            Positioned(
              right: -8,
              top: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
