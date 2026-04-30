import 'dart:async';

import 'package:dzmarket/src/features/auth/auth_callback_page.dart';
import 'package:dzmarket/src/features/auth/sign_in_page.dart';
import 'package:dzmarket/src/features/auth/sign_up_page.dart';
import 'package:dzmarket/src/features/auth/reset_password_page.dart';
import 'package:dzmarket/src/features/admin/app_errors_page.dart';
import 'package:dzmarket/src/features/admin/moderation_admin_page.dart';
import 'package:dzmarket/src/features/chat/order_chat_gate_page.dart';
import 'package:dzmarket/src/features/home/home_shell.dart';
import 'package:dzmarket/src/features/legal/legal_page.dart';
import 'package:dzmarket/src/features/listings/product_detail_page.dart';
import 'package:dzmarket/src/features/marketing/web_marketing_landing_page.dart';
import 'package:dzmarket/src/features/notifications/notifications_page.dart';
import 'package:dzmarket/src/features/orders/seller_orders_page.dart';
import 'package:dzmarket/src/features/orders/shipments_dashboard_page.dart';
import 'package:dzmarket/src/features/profile/courier_settings_page.dart';
import 'package:dzmarket/src/features/profile/my_listings_page.dart';
import 'package:dzmarket/src/features/profile/seller_dashboard_page.dart';
import 'package:dzmarket/src/features/tracking/map_tracking_page.dart';
import 'package:dzmarket/src/utils/ios_public_browse_policy.dart';
import 'package:dzmarket/src/utils/web_host_context.dart';
import 'package:dzmarket/src/widgets/guest_browse_gate.dart';
import 'package:dzmarket/src/widgets/web_frame.dart';
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

  Map<String, String> authParamsFromUri(Uri uri) {
    final merged = <String, String>{...uri.queryParameters};
    final fragment = uri.fragment;
    if (fragment.isEmpty) return merged;
    Map<String, String> parsedFragment = const {};
    try {
      parsedFragment = Uri.splitQueryString(fragment);
    } catch (_) {
      final queryIndex = fragment.indexOf('?');
      if (queryIndex >= 0 && queryIndex + 1 < fragment.length) {
        final afterQuestionMark = fragment.substring(queryIndex + 1);
        try {
          parsedFragment = Uri.splitQueryString(afterQuestionMark);
        } catch (_) {
          parsedFragment = const {};
        }
      }
    }
    merged.addAll(parsedFragment);
    return merged;
  }

  bool hasAuthCallbackParams(Uri uri) {
    final qp = authParamsFromUri(uri);
    if (qp.containsKey('code') || qp.containsKey('token_hash')) return true;
    if (qp.containsKey('access_token') || qp.containsKey('refresh_token')) {
      return true;
    }
    final hasAuthError =
        qp.containsKey('error_description') ||
        (qp.containsKey('error') && qp.containsKey('type'));
    return hasAuthError;
  }

  Uri? callbackFromFromParam(GoRouterState state) {
    final from = state.uri.queryParameters['from'];
    if (from == null || from.isEmpty) return null;
    final decoded = Uri.decodeComponent(from);
    final parsed = Uri.tryParse(decoded);
    if (parsed == null) return null;
    if (!hasAuthCallbackParams(parsed)) return null;
    final merged = authParamsFromUri(parsed);
    return parsed.replace(queryParameters: merged, fragment: '');
  }

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    refreshListenable: GoRouterRefreshStream(auth.onAuthStateChange),
    observers: observers,
    redirect: (context, state) {
      final session = auth.currentSession;
      final loggingIn = state.matchedLocation == '/sign-in';
      final signingUp = state.matchedLocation == '/sign-up';
      final resetting = state.matchedLocation == '/reset-password';
      final callback =
          state.matchedLocation == '/auth/callback' ||
          state.matchedLocation == '/auth/call';
      final inLegal = state.matchedLocation.startsWith('/legal');

      if (!callback && hasAuthCallbackParams(state.uri)) {
        final merged = authParamsFromUri(state.uri);
        return Uri(path: '/auth/callback', queryParameters: merged).toString();
      }

      if (loggingIn) {
        final callbackUri = callbackFromFromParam(state);
        if (callbackUri != null) {
          return Uri(
            path: '/auth/callback',
            queryParameters: callbackUri.queryParameters,
          ).toString();
        }
      }

      if (session == null) {
        if (loggingIn ||
            signingUp ||
            resetting ||
            inLegal ||
            callback ||
            shouldShowMarketingLanding(
              matchedLocation: state.matchedLocation,
              uri: state.uri,
            ) ||
            isAnonymousRouteAllowed(
              matchedLocation: state.matchedLocation,
              uri: state.uri,
            )) {
          return null;
        }
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
            const NoTransitionPage(child: WebFrame(child: SignInPage())),
      ),
      GoRoute(
        path: '/sign-up',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: WebFrame(child: SignUpPage())),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: WebFrame(child: ResetPasswordPage())),
      ),
      GoRoute(
        path: '/auth/callback',
        pageBuilder: (context, state) =>
            NoTransitionPage(child: AuthCallbackPage(uri: state.uri)),
      ),
      GoRoute(
        path: '/auth/call',
        pageBuilder: (context, state) =>
            NoTransitionPage(child: AuthCallbackPage(uri: state.uri)),
      ),
      GoRoute(
        path: '/legal/privacy',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WebFrame(
            child: LegalPage(
              titleKey: 'legal.privacy.title',
              bodyKey: 'legal.privacy.body',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/legal/account-deletion',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WebFrame(
            child: LegalPage(
              titleKey: 'legal.account_deletion.title',
              bodyKey: 'legal.account_deletion.body',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/legal/terms',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WebFrame(
            child: LegalPage(
              titleKey: 'legal.terms.title',
              bodyKey: 'legal.terms.body',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/legal/imprint',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WebFrame(
            child: LegalPage(
              titleKey: 'legal.imprint.title',
              bodyKey: 'legal.imprint.body',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: WebFrame(child: NotificationsPage())),
      ),
      GoRoute(
        path: '/seller/orders',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: WebFrame(child: SellerOrdersPage())),
      ),
      GoRoute(
        path: '/seller/dashboard',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WebFrame(child: SellerDashboardPage()),
        ),
      ),
      GoRoute(
        path: '/seller/listings',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: WebFrame(child: MyListingsPage())),
      ),
      GoRoute(
        path: '/seller/shipments',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WebFrame(child: ShipmentsDashboardPage()),
        ),
      ),
      GoRoute(
        path: '/seller/couriers',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WebFrame(child: CourierSettingsPage()),
        ),
      ),
      GoRoute(
        path: '/admin/errors',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: WebFrame(child: AppErrorsPage())),
      ),
      GoRoute(
        path: '/admin/moderation',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WebFrame(child: ModerationAdminPage()),
        ),
      ),
      GoRoute(
        path: '/product/:id',
        name: 'product',
        builder: (context, state) => GuestBrowseGate(
          returnPath: state.uri.toString(),
          child: ProductDetailPage(productId: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) {
          final tab = state.uri.queryParameters['tab'] ?? 'listings';
          if (shouldShowMarketingLanding(
            matchedLocation: state.matchedLocation,
            uri: state.uri,
          )) {
            return const NoTransitionPage(child: WebMarketingLandingPage());
          }
          return NoTransitionPage(
            child: GuestBrowseGate(
              returnPath: state.uri.toString(),
              child: HomeShell(initialTab: tab),
            ),
          );
        },
        routes: [
          GoRoute(
            path: 'profile',
            name: 'profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeShell(initialTab: 'profile')),
          ),
          GoRoute(
            path: 'order/:id/chat',
            name: 'order-chat',
            builder: (context, state) {
              final orderId = state.pathParameters['id'] ?? '';
              return OrderChatGatePage(orderId: orderId);
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
