import 'dart:convert';

import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/label_service.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/utils/label_url_resolver.dart';

class LabelUrlService {
  LabelUrlService({LabelService? labelService})
    : _labelService = labelService ?? LabelService();

  final LabelService _labelService;

  Future<Uri?> resolveFreshLabelUri(
    String? rawUrl, {
    String? orderId,
    int expiresInSeconds = 60 * 60 * 24,
  }) async {
    final normalized = normalizeLabelUrl(rawUrl);
    if (normalized.isEmpty) return null;

    final parsed = Uri.tryParse(normalized);
    if (parsed == null) return null;
    final rawUrlExpired = _isSignedUrlExpired(parsed);
    final objectRef = _extractStorageObjectRef(parsed);

    if (!rawUrlExpired) {
      return parsed;
    }

    final fromOrder = await _resolveFromOrder(orderId);
    if (fromOrder != null) {
      if (!_isSignedUrlExpired(fromOrder)) return fromOrder;
      final fromOrderObjectRef = _extractStorageObjectRef(fromOrder);
      if (fromOrderObjectRef != null) {
        final refreshed = await _tryCreateSignedUrl(
          fromOrderObjectRef,
          expiresInSeconds,
        );
        if (refreshed != null) return refreshed;
      }
    }

    if (objectRef == null) {
      return null;
    }

    final refreshed = await _tryCreateSignedUrl(objectRef, expiresInSeconds);
    if (refreshed != null) return refreshed;

    // Avoid opening a known-expired URL.
    return null;
  }

  Future<Uri?> _resolveFromOrder(String? orderId) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId ?? '', maxLength: 64);
    if (safeOrderId.isEmpty) return null;
    try {
      final data = await _labelService.generateLabel(safeOrderId);
      if (data == null || data.isEmpty) return null;
      final resolved = normalizeLabelUrl(
        data['label_url']?.toString() ??
            data['signed_url']?.toString() ??
            data['label']?.toString(),
      );
      if (resolved.isEmpty) return null;
      return Uri.tryParse(resolved);
    } catch (_) {
      return null;
    }
  }

  Future<Uri?> _tryCreateSignedUrl(
    _StorageObjectRef objectRef,
    int expiresInSeconds,
  ) async {
    try {
      final signedUrl = await RateLimiter.instance.run(
        'label.refresh.sign',
        () => supabase.storage
            .from(objectRef.bucket)
            .createSignedUrl(objectRef.path, expiresInSeconds),
      );
      return Uri.tryParse(normalizeLabelUrl(signedUrl));
    } catch (_) {
      return null;
    }
  }

  _StorageObjectRef? _extractStorageObjectRef(Uri uri) {
    final path = uri.path;
    final prefixes = <String>[
      '/storage/v1/object/sign/',
      '/storage/v1/object/public/',
      '/storage/v1/object/authenticated/',
      '/storage/v1/object/',
      '/object/sign/',
      '/object/public/',
      '/object/authenticated/',
      '/object/',
    ];

    String? suffix;
    for (final prefix in prefixes) {
      if (path.startsWith(prefix)) {
        suffix = path.substring(prefix.length);
        break;
      }
    }
    if (suffix == null || suffix.isEmpty) return null;

    final split = suffix.indexOf('/');
    if (split <= 0 || split >= suffix.length - 1) return null;

    final bucket = Uri.decodeComponent(suffix.substring(0, split)).trim();
    final objectPath = Uri.decodeComponent(suffix.substring(split + 1)).trim();
    if (bucket.isEmpty || objectPath.isEmpty) return null;

    return _StorageObjectRef(bucket: bucket, path: objectPath);
  }

  bool _isSignedUrlExpired(Uri uri) {
    final token = uri.queryParameters['token']?.trim() ?? '';
    if (token.isNotEmpty) {
      try {
        final parts = token.split('.');
        if (parts.length >= 2) {
          final payload = parts[1];
          final normalized = base64Url.normalize(payload);
          final decoded = utf8.decode(base64Url.decode(normalized));
          final map = jsonDecode(decoded);
          if (map is Map<String, dynamic>) {
            final exp = map['exp'];
            if (exp is num) {
              final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              return exp.toInt() <= now;
            }
          }
        }
      } catch (_) {}
    }

    try {
      final sasExpiry = uri.queryParameters['se']?.trim() ?? '';
      if (sasExpiry.isEmpty) return false;
      final expiresAt = DateTime.tryParse(sasExpiry)?.toUtc();
      if (expiresAt == null) return false;
      return expiresAt.isBefore(DateTime.now().toUtc());
    } catch (_) {
      return false;
    }
  }
}

class _StorageObjectRef {
  const _StorageObjectRef({required this.bucket, required this.path});

  final String bucket;
  final String path;
}
