import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/foundation.dart';

class AppErrorService {
  AppErrorService._();
  static final instance = AppErrorService._();

  static const int _maxMessageLength = 2000;
  static const int _maxStackLength = 8000;
  static const Duration _duplicateWindow = Duration(minutes: 15);
  final Map<String, DateTime> _recentFingerprints = <String, DateTime>{};

  String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return value.substring(0, max);
  }

  @visibleForTesting
  static bool isSkippableAppError({
    required String message,
    String? context,
    required bool fatal,
    required bool hasAuthenticatedUser,
  }) {
    final loweredMessage = message.toLowerCase();
    final loweredContext = (context ?? '').toLowerCase();

    const authSessionNoise = <String>[
      'invalidjwttoken',
      'jwt expired',
      'expired jwt',
      'pgrst301',
      '401 unauthorized',
      'auth session missing',
    ];
    if (authSessionNoise.any(loweredMessage.contains)) {
      return true;
    }

    const realtimeNoise = <String>[
      'realtimesubscribeexception(channelerror',
      'realtimesubscribeexception(status: realtimesubscribestatus.timedout',
      'realtimesubscribeexception(status: realtimesubscribestatus.channelerror',
      'realtimecloseevent(code: 1006',
      'websocketchannelexception',
      'channelerror',
      'timedout, details: null',
      'websocket exception',
      'closed before the connection was established',
    ];
    if (realtimeNoise.any(loweredMessage.contains)) {
      return true;
    }

    const offlineHints = <String>[
      'socketexception',
      'failed host lookup',
      'network is unreachable',
      'network unreachable',
      'no address associated with hostname',
      'clientexception',
      'timed out',
      'timeout',
      'connection refused',
      'connection reset',
    ];
    const noisyOfflineContexts = <String>[
      'chat_hub.watch_conversations',
      'order_chat_gate.ensure_order_conversation',
      'chat_room.force_reload',
      'listings.refresh',
      'profile.load_locations',
      'profile.load_communes',
      'resolving an image codec',
    ];
    if (offlineHints.any(loweredMessage.contains) &&
        noisyOfflineContexts.any(loweredContext.contains)) {
      return true;
    }
    if (offlineHints.any(loweredMessage.contains) &&
        loweredMessage.contains('api.dzmarket.pro/storage/v1/object/public/')) {
      return true;
    }

    const mediaNoise = <String>[
      'encodingerror: the source image cannot be decoded',
      'invalid statuscode: 400, uri = https://api.dzmarket.pro/storage/v1/object/public/',
    ];
    if (mediaNoise.any(loweredMessage.contains)) {
      return true;
    }

    if (!hasAuthenticatedUser && !fatal) return true;

    return false;
  }

  void _pruneRecentFingerprints(DateTime now) {
    _recentFingerprints.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _duplicateWindow,
    );
  }

  String _fingerprint({
    required String message,
    String? context,
    required bool fatal,
    required String platform,
    required String? userId,
  }) {
    return [
      platform,
      userId ?? 'anon',
      fatal ? 'fatal' : 'nonfatal',
      (context ?? '').trim().toLowerCase(),
      message.trim().toLowerCase(),
    ].join('|');
  }

  Future<void> logError(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
      final message = _truncate(error.toString(), _maxMessageLength);
      if (isSkippableAppError(
        message: message,
        context: context,
        fatal: fatal,
        hasAuthenticatedUser: userId != null,
      )) {
        return;
      }

      final now = DateTime.now();
      _pruneRecentFingerprints(now);
      final fingerprint = _fingerprint(
        message: message,
        context: context,
        fatal: fatal,
        platform: platform,
        userId: userId,
      );
      final lastLoggedAt = _recentFingerprints[fingerprint];
      if (lastLoggedAt != null &&
          now.difference(lastLoggedAt) <= _duplicateWindow) {
        return;
      }
      _recentFingerprints[fingerprint] = now;

      final payload = {
        'user_id': userId,
        'message': message,
        'stack': stack == null
            ? null
            : _truncate(stack.toString(), _maxStackLength),
        'context': {
          if (context != null) 'context': context,
          'fatal': fatal,
          'platform': platform,
        },
        'platform': platform,
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
