import 'dart:async';

import 'package:dzmarket/src/features/auth/sign_in_page.dart';
import 'package:dzmarket/src/features/auth/sign_up_page.dart';
import 'package:dzmarket/src/features/chat/chat_room_page.dart';
import 'package:dzmarket/src/features/home/home_shell.dart';
import 'package:dzmarket/src/features/listings/product_detail_page.dart';
import 'package:dzmarket/src/features/tracking/map_tracking_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

GoRouter createRouter({List<NavigatorObserver> observers = const []}) {
  final auth = Supabase.instance.client.auth;

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    refreshListenable: GoRouterRefreshStream(auth.onAuthStateChange),
    observers: observers,
    redirect: (context, state) {
      final session = auth.currentSession;
      final loggingIn = state.matchedLocation == '/sign-in';
      final signingUp = state.matchedLocation == '/sign-up';

      if (session == null) {
        if (loggingIn || signingUp) return null;
        final from = Uri.encodeComponent(state.uri.toString());
        return '/sign-in?from=$from';
      }

      if (loggingIn || signingUp) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: SignInPage()),
      ),
      GoRoute(
        path: '/sign-up',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: SignUpPage()),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) {
          final tab = state.uri.queryParameters['tab'] ?? 'listings';
          return NoTransitionPage(child: HomeShell(initialTab: tab));
        },
        routes: [
          GoRoute(
            path: 'profile',
            name: 'profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeShell(initialTab: 'profile')),
          ),
          GoRoute(
            path: 'product/:id',
            name: 'product',
            builder: (context, state) =>
                ProductDetailPage(productId: state.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: 'order/:id/chat',
            name: 'order-chat',
              builder: (context, state) {
                final orderId = state.pathParameters['id'] ?? '';
              return ChatRoomPage(conversationId: 'order:$orderId');
              },
            ),
          GoRoute(
            path: 'order/:id/track',
            name: 'order-track',
            builder: (context, state) =>
                MapTrackingPage(orderId: state.pathParameters['id'] ?? ''),
          ),
        ],
      ),
    ],
  );
}
