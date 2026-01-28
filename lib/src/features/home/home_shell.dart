import 'package:dzmarket/src/features/chat/chat_hub_page.dart';
import 'package:dzmarket/src/features/listings/listings_page.dart';
import 'package:dzmarket/src/features/profile/profile_page.dart';
import 'package:dzmarket/src/services/chat_room_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
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
  static final ChatRoomService _roomService = ChatRoomService();
  late int _currentIndex = _tabIndexFor(widget.initialTab);

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _currentIndex = _tabIndexFor(widget.initialTab);
    }
  }

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
    context.go('/?tab=${_tabs[index]}');
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const ListingsPage(), // index 0: Browse/Product list
      const ChatHubPage(),  // index 1: Chat hub
      const ProfilePage(),  // index 2: Profile
    ];
    final userId = supabase.auth.currentUser?.id;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabSelected,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.storefront_outlined),
            label: L10n.t(context, 'Parcourir', 'Parcourir'),
          ),
          NavigationDestination(
            icon: _ChatBadge(
              userId: userId,
              roomService: _roomService,
            ),
            label: L10n.t(context, 'Chat', 'Chat'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            label: L10n.t(context, 'Profil', 'Profil'),
          ),
        ],
      ),
    );
  }

  int _tabIndexFor(String tab) {
    final index = _tabs.indexOf(tab);
    if (index == -1) return 0;
    return index;
  }
}



class _ChatBadge extends StatelessWidget {
  const _ChatBadge({required this.userId, required this.roomService});

  final String? userId;
  final ChatRoomService roomService;

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return const Icon(Icons.chat_bubble_outline);
    }
    return StreamBuilder<List<ChatRoomSummary>>(
      stream: roomService.streamRoomsForUser(userId!),
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? const [];
        final unread = rooms.fold<int>(
          0,
          (sum, room) => sum + (room.buyerId == userId ? room.unreadByBuyer : room.unreadBySeller),
        );
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
  }
}




