import 'package:dzmarket/src/app.dart';
import 'package:dzmarket/src/config/app_config.dart';
import 'dart:async';

import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/notification_service.dart';
import 'package:dzmarket/src/services/push_notification_service.dart';
import 'package:dzmarket/src/services/translation_service.dart';
import 'package:dzmarket/src/services/connectivity_service.dart';
import 'package:dzmarket/src/services/firebase_service.dart';
import 'package:dzmarket/src/services/crashlytics_service.dart';
import 'package:dzmarket/src/services/app_error_service.dart';
import 'package:dzmarket/src/services/app_logger.dart';
import 'package:dzmarket/src/services/network_preferences_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _bootstrapApp();
  } catch (error, stackTrace) {
    AppLogger.warn(
      'Fatal bootstrap error',
      error: error,
      stackTrace: stackTrace,
    );
    runApp(_BootstrapErrorApp(error: error));
  }
}

Future<void> _bootstrapApp() async {
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  await LocaleService.instance.init();
  await NetworkPreferencesService.instance.init();

  final config = await AppConfig.load();
  if (config.supabaseUrl.isEmpty || config.supabaseAnonKey.isEmpty) {
    throw StateError(
      'Supabase URL/anon key manquants (SUPABASE_URL / SUPABASE_ANON_KEY).',
    );
  }
  // Log in debug to confirm the runtime config actually matches the project (helps diagnose "invalid API key").
  assert(() {
    debugPrint('Supabase URL: ${config.supabaseUrl}');
    final prefixLen = config.supabaseAnonKey.length < 8
        ? config.supabaseAnonKey.length
        : 8;
    debugPrint(
      'Supabase anon key (prefix): ${config.supabaseAnonKey.substring(0, prefixLen)}...',
    );
    return true;
  }());

  await Supabase.initialize(
    url: config.supabaseUrl,
    anonKey: config.supabaseAnonKey,
    // We handle auth callback links ourselves in /auth/callback.
    // This avoids blank page crashes when a PKCE code link is opened from an
    // email client without local PKCE verifier storage.
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    // Supabase client auto-refreshes tokens by default; no extra options needed here.
  );
  await FirebaseService.instance.init(config);
  if (!kIsWeb && FirebaseService.instance.isEnabled) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await PushNotificationService.instance.start();
  }
  await TranslationService.instance.load();
  await ConnectivityService.instance.start();
  NetworkPreferencesService.instance.bindToConnectivity(
    ConnectivityService.instance,
  );
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  NotificationService.instance.start(messengerKey);

  if (CrashlyticsService.instance.isEnabled) {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      CrashlyticsService.instance.recordFlutterError(details);
      unawaited(AppErrorService.instance.logFlutterError(details));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashlyticsService.instance.recordError(error, stack, fatal: true);
      unawaited(AppErrorService.instance.logError(error, stack, fatal: true));
      return true;
    };
  } else {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(AppErrorService.instance.logFlutterError(details));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(AppErrorService.instance.logError(error, stack, fatal: true));
      return true;
    };
  }

  AppLogger.info('App flavor: ${config.flavor}');
  runApp(DZMarketApp(scaffoldMessengerKey: messengerKey));
}

// Backwards compatibility for tests or code expecting `MyApp`.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DZMarketApp(
      scaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
    );
  }
}

class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F7F6),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDCE7E1)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DZMarket',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'L’application n’a pas pu demarrer.',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _bootstrapErrorMessage(error),
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Color(0xFF41534B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _bootstrapErrorMessage(Object error) {
  final raw = error.toString();
  if (raw.contains('SUPABASE_URL') || raw.contains('SUPABASE_ANON_KEY')) {
    return 'Configuration manquante: SUPABASE_URL / SUPABASE_ANON_KEY. '
        'Regenerer le build avec les variables Codemagic de production.';
  }
  return 'Erreur de demarrage. Regenerer le build ou verifier la configuration '
      'de production.';
}
