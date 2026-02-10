import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/foundation.dart';

class AppErrorService {
  AppErrorService._();
  static final instance = AppErrorService._();

  static const int _maxMessageLength = 2000;
  static const int _maxStackLength = 8000;

  String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return value.substring(0, max);
  }

  Future<void> logError(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      final payload = {
        'user_id': userId,
        'message': _truncate(error.toString(), _maxMessageLength),
        'stack': stack == null ? null : _truncate(stack.toString(), _maxStackLength),
        'context': {
          if (context != null) 'context': context,
          'fatal': fatal,
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        },
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      };
      await RateLimiter.instance.run(
        'app_errors.insert',
        () => supabase.from('app_errors').insert(payload),
      );
    } catch (_) {
      // Best-effort logging only.
    }
  }

  Future<void> logFlutterError(FlutterErrorDetails details) async {
    await logError(
      details.exception,
      details.stack,
      context: details.context?.toDescription(),
      fatal: details.stack?.toString().contains('fatal') ?? false,
    );
  }
}
