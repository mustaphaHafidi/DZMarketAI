import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> ensureSupabaseInitialized({
  required String url,
  required String anonKey,
}) async {
  try {
    Supabase.instance.client;
  } catch (_) {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }
}
