import 'package:dzmarket/src/app.dart';
import 'package:dzmarket/src/config/app_config.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/notification_service.dart';
import 'package:dzmarket/src/services/translation_service.dart';
import 'package:dzmarket/src/services/connectivity_service.dart';
import 'package:dzmarket/src/services/firebase_service.dart';
import 'package:dzmarket/src/services/crashlytics_service.dart';
import 'package:dzmarket/src/services/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocaleService.instance.init();

  final config = await AppConfig.load();
  if (config.supabaseUrl.isEmpty || config.supabaseAnonKey.isEmpty) {
    throw StateError(
      'Supabase URL/anon key manquants (SUPABASE_URL / SUPABASE_ANON_KEY).',
    );
  }
  // Log in debug to confirm the runtime config actually matches the project (helps diagnose "invalid API key").
  assert(() {
    debugPrint('Supabase URL: ${config.supabaseUrl}');
    final prefixLen =
        config.supabaseAnonKey.length < 8 ? config.supabaseAnonKey.length : 8;
    debugPrint(
      'Supabase anon key (prefix): ${config.supabaseAnonKey.substring(0, prefixLen)}...',
    );
    return true;
  }());

  await Supabase.initialize(
    url: config.supabaseUrl,
    anonKey: config.supabaseAnonKey,
    // Supabase client auto-refreshes tokens by default; no extra options needed here.
  );
  await FirebaseService.instance.init(config);
  await TranslationService.instance.load();
  await ConnectivityService.instance.start();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  NotificationService.instance.start(messengerKey);

  if (CrashlyticsService.instance.isEnabled) {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      CrashlyticsService.instance.recordFlutterError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashlyticsService.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } else {
    FlutterError.onError = FlutterError.presentError;
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
