import 'dart:convert';

import 'package:dzmarket/src/app.dart';
import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/notification_service.dart';
import 'package:dzmarket/src/services/translation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocaleService.instance.init();

  // Supabase credentials (centralized to avoid typos). Trim to avoid stray whitespace/newlines
  // when values are injected via --dart-define or environment.
  var supabaseUrl = SupabaseOptions.supabaseUrl.trim();
  var anonKey = SupabaseOptions.supabaseAnonKey.trim();
  if ((supabaseUrl.isEmpty || anonKey.isEmpty) && kIsWeb) {
    final runtime = await _loadWebRuntimeConfig();
    supabaseUrl = runtime['supabaseUrl'] ?? supabaseUrl;
    anonKey = runtime['supabaseAnonKey'] ?? anonKey;
  }
  if (supabaseUrl.isEmpty || anonKey.isEmpty) {
    throw StateError(
      'Supabase URL/anon key manquants (SUPABASE_URL / SUPABASE_ANON_KEY).',
    );
  }
  // Log in debug to confirm the runtime config actually matches the project (helps diagnose "invalid API key").
  assert(() {
    debugPrint('Supabase URL: $supabaseUrl');
    debugPrint('Supabase anon key (prefix): ${anonKey.substring(0, 8)}...');
    return true;
  }());

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: anonKey,
    // Supabase client auto-refreshes tokens by default; no extra options needed here.
  );
  await TranslationService.instance.load();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  NotificationService.instance.start(messengerKey);
  runApp(DZMarketApp(scaffoldMessengerKey: messengerKey));
}

Future<Map<String, String>> _loadWebRuntimeConfig() async {
  try {
    final uri = Uri.base.resolve('config.json');
    final resp = await http.get(uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) return {};
    final data = jsonDecode(resp.body);
    if (data is! Map) return {};
    final url = data['supabaseUrl']?.toString().trim();
    final key = data['supabaseAnonKey']?.toString().trim();
    return {
      if (url != null && url.isNotEmpty) 'supabaseUrl': url,
      if (key != null && key.isNotEmpty) 'supabaseAnonKey': key,
    };
  } catch (_) {
    return {};
  }
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
