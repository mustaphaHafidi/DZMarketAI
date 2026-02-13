import 'package:dzmarket/src/router.dart';
import 'package:dzmarket/src/theme.dart';
import 'package:dzmarket/src/widgets/app_state_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/analytics_service.dart';
import 'package:dzmarket/src/services/session_controller.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DZMarketApp extends StatelessWidget {
  DZMarketApp({super.key, required this.scaffoldMessengerKey})
      : _router = _buildRouter();

  final GoRouter _router;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;

  static GoRouter _buildRouter() {
    final observer = AnalyticsService.instance.createObserver();
    return createRouter(
      observers: observer == null ? const [] : [observer],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the router when auth state changes to avoid stale/blank screens on session expiry.
    final authStream = Supabase.instance.client.auth.onAuthStateChange;
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleService.instance.locale,
      builder: (context, locale, _) {
        return StreamBuilder<AuthState>(
          stream: authStream,
          builder: (context, snapshot) {
            final user = snapshot.data?.session?.user;
            if (user != null) {
              // Make sure a profile row exists after login.
              // The fetchProfile returns a Future<Profile?>, so ensure the
              // catchError handler returns null on error to satisfy the
              // analyzer about the return type.
              AuthService.instance.fetchProfile().catchError(
                (_) => null,
              ); // fire-and-forget
            }
            return MaterialApp.router(
              title: 'DZMarket',
              theme: buildTheme(),
              routerConfig: _router,
              debugShowCheckedModeBanner: false,
              scaffoldMessengerKey: scaffoldMessengerKey,
              supportedLocales: L10n.supportedLocales,
              locale: locale ?? const Locale('fr'),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              localeResolutionCallback: (loc, supported) {
                if (loc == null) return supported.first;
                for (final s in supported) {
                  if (s.languageCode == loc.languageCode) return s;
                }
                return supported.first;
              },
              builder: (context, child) {
                final resolved = Localizations.localeOf(context);
                final isRtl = resolved.languageCode == 'ar';
                return AppStateScope(
                  notifier: SessionController.instance,
                  child: Directionality(
                    textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
