import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dzmarket/src/services/connectivity_service.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'supabase_service.dart';

class StorageException implements Exception {
  const StorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StorageService {
  static const _bucket = 'products';
  static const _maxUploadLongEdge = 1280;
  static const _compressionThresholdBytes = 450 * 1024;
  final _uuid = const Uuid();

  Future<List<String>> uploadImages({
    required List<Uint8List> files,
    required List<String> fileNames,
    String bucket = _bucket,
  }) async {
    final locale = _localeCode();
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StorageException(
        L10n.trLocale(locale, 'storage.error.signin_required_upload'),
      );
    }
    if (!ConnectivityService.instance.isOnline.value) {
      throw StorageException(
        L10n.trLocale(locale, 'storage.error.offline_upload'),
      );
    }

    if (files.length != fileNames.length) {
      throw ArgumentError('Files and names length mismatch');
    }

    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      final originalName = _sanitizeFileName(fileNames[i]);
      final prepared = _prepareImageForUpload(
        bytes: files[i],
        fileName: originalName,
      );
      final path = '$userId/${_uuid.v4()}-${prepared.fileName}';
      await _runUploadWithRetry<void>(
        limiterKey: 'storage.upload',
        timeoutKey: 'storage.error.upload_timeout',
        genericKey: 'storage.error.upload_failed',
        locale: locale,
        task: () => supabase.storage
            .from(bucket)
            .uploadBinary(
              path,
              prepared.bytes,
              fileOptions: FileOptions(
                upsert: true,
                contentType: prepared.contentType,
              ),
            ),
      );
      final publicUrl = supabase.storage.from(bucket).getPublicUrl(path);
      urls.add(publicUrl);
    }
    return urls;
  }

  Future<void> deletePublicUrls(
    List<String> urls, {
    String bucket = _bucket,
  }) async {
    if (urls.isEmpty) return;
    final paths = <String>[];
    for (final url in urls) {
      try {
        final uri = Uri.parse(url);
        final marker = '/storage/v1/object/public/$bucket/';
        final idx = uri.path.indexOf(marker);
        if (idx == -1) continue;
        final path = uri.path.substring(idx + marker.length);
        if (path.isNotEmpty) {
          paths.add(path);
        }
      } catch (_) {
        // Ignore malformed URLs.
      }
    }
    if (paths.isEmpty) return;
    await RateLimiter.instance.run(
      'storage.delete',
      () => supabase.storage.from(bucket).remove(paths),
    );
  }

  /// Upload a single file to a bucket and return a signed URL (for private buckets like labels).
  Future<String> uploadBytesAndSign({
    required Uint8List data,
    required String fileName,
    required String bucket,
    int expiresInSeconds = 60 * 60 * 24, // 24h
  }) async {
    final locale = _localeCode();
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StorageException(
        L10n.trLocale(locale, 'storage.error.signin_required_upload'),
      );
    }
    if (!ConnectivityService.instance.isOnline.value) {
      throw StorageException(
        L10n.trLocale(locale, 'storage.error.offline_upload'),
      );
    }
    final safeFileName = _sanitizeFileName(fileName);
    final path = '$userId/${_uuid.v4()}-$safeFileName';
    await _runUploadWithRetry<void>(
      limiterKey: 'storage.upload.sign',
      timeoutKey: 'storage.error.upload_timeout',
      genericKey: 'storage.error.upload_failed',
      locale: locale,
      task: () => supabase.storage
          .from(bucket)
          .uploadBinary(
            path,
            data,
            fileOptions: const FileOptions(upsert: true),
          ),
    );
    final signed = await _runUploadWithRetry<String>(
      limiterKey: 'storage.sign',
      timeoutKey: 'storage.error.upload_timeout',
      genericKey: 'storage.error.upload_failed',
      locale: locale,
      task: () =>
          supabase.storage.from(bucket).createSignedUrl(path, expiresInSeconds),
    );
    return signed;
  }

  /// Upload in a private bucket and return the storage path (no signed URL).
  /// Use storage RLS to restrict reads (e.g. auth.uid() = split_part(path, '/', 1)).
  Future<String> uploadPrivate({
    required Uint8List data,
    required String fileName,
    required String bucket,
    String? ownerId,
  }) async {
    final locale = _localeCode();
    final userId = ownerId ?? supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StorageException(
        L10n.trLocale(locale, 'storage.error.signin_required_upload'),
      );
    }
    if (!ConnectivityService.instance.isOnline.value) {
      throw StorageException(
        L10n.trLocale(locale, 'storage.error.offline_upload'),
      );
    }
    final safeFileName = _sanitizeFileName(fileName);
    final path = '$userId/${_uuid.v4()}-$safeFileName';
    await _runUploadWithRetry<void>(
      limiterKey: 'storage.upload.private',
      timeoutKey: 'storage.error.upload_timeout',
      genericKey: 'storage.error.upload_failed',
      locale: locale,
      task: () => supabase.storage
          .from(bucket)
          .uploadBinary(
            path,
            data,
            fileOptions: const FileOptions(upsert: true),
          ),
    );
    return path;
  }

  String _localeCode() =>
      LocaleService.instance.locale.value?.languageCode ?? 'fr';

  Future<T> _runUploadWithRetry<T>({
    required String limiterKey,
    required String timeoutKey,
    required String genericKey,
    required String locale,
    required Future<T> Function() task,
    int attempts = 4,
    Duration timeout = const Duration(seconds: 30),
    Duration timeoutIncrement = const Duration(seconds: 15),
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      final effectiveTimeout = Duration(
        seconds: timeout.inSeconds +
            (timeoutIncrement.inSeconds * math.max(0, attempt - 1)),
      );
      try {
        return await RateLimiter.instance.run(
          limiterKey,
          () => task().timeout(effectiveTimeout),
        );
      } on TimeoutException {
        lastError = StorageException(L10n.trLocale(locale, timeoutKey));
      } catch (error) {
        lastError = error;
      }
      if (attempt < attempts) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    if (lastError is StorageException) {
      throw lastError;
    }
    throw StorageException(L10n.trLocale(locale, genericKey));
  }

  String _sanitizeFileName(String input) {
    final base = InputSanitizer.sanitizeText(input, maxLength: 120);
    final slashCleaned = base.replaceAll(RegExp(r'[\\/]+'), '-');
    final collapsed = slashCleaned.replaceAll(RegExp(r'\s+'), '-');
    final safe = collapsed.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '');
    final trimmed = safe.replaceAll(RegExp(r'[-_.]{2,}'), '-').trim();
    return trimmed.isEmpty ? 'file' : trimmed;
  }

  _PreparedUpload _prepareImageForUpload({
    required Uint8List bytes,
    required String fileName,
  }) {
    final originalType = _contentTypeFromName(fileName);
    if (bytes.length < _compressionThresholdBytes) {
      return _PreparedUpload(
        bytes: bytes,
        fileName: fileName,
        contentType: originalType,
      );
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return _PreparedUpload(
        bytes: bytes,
        fileName: fileName,
        contentType: originalType,
      );
    }

    final resized = _resizeIfNeeded(decoded);
    final lower = fileName.toLowerCase();
    final isPng = lower.endsWith('.png');

    try {
      if (isPng) {
        final pngBytes = Uint8List.fromList(img.encodePng(resized, level: 6));
        if (pngBytes.length < bytes.length) {
          return _PreparedUpload(
            bytes: pngBytes,
            fileName: fileName,
            contentType: 'image/png',
          );
        }
      } else {
        final jpgBytes = Uint8List.fromList(
          img.encodeJpg(resized, quality: 78),
        );
        if (jpgBytes.length < bytes.length) {
          return _PreparedUpload(
            bytes: jpgBytes,
            fileName: _replaceExtension(fileName, 'jpg'),
            contentType: 'image/jpeg',
          );
        }
      }
    } catch (_) {
      // Keep original image when optimization fails.
    }

    return _PreparedUpload(
      bytes: bytes,
      fileName: fileName,
      contentType: originalType,
    );
  }

  img.Image _resizeIfNeeded(img.Image source) {
    final longEdge = math.max(source.width, source.height);
    if (longEdge <= _maxUploadLongEdge) return source;

    final ratio = _maxUploadLongEdge / longEdge;
    final targetWidth = math.max(1, (source.width * ratio).round());
    final targetHeight = math.max(1, (source.height * ratio).round());
    return img.copyResize(
      source,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.average,
    );
  }

  String _replaceExtension(String fileName, String ext) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return '$fileName.$ext';
    return '${fileName.substring(0, dot)}.$ext';
  }

  String _contentTypeFromName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}

class _PreparedUpload {
  const _PreparedUpload({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
}
