import 'dart:typed_data';

import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'supabase_service.dart';

class StorageService {
  static const _bucket = 'products';
  final _uuid = const Uuid();

  Future<List<String>> uploadImages({
    required List<Uint8List> files,
    required List<String> fileNames,
    String bucket = _bucket,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required to upload images.');

    if (files.length != fileNames.length) {
      throw ArgumentError('Files and names length mismatch');
    }

    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      final bytes = files[i];
      final originalName = _sanitizeFileName(fileNames[i]);
      final path = '$userId/${_uuid.v4()}-$originalName';
      await RateLimiter.instance.run(
        'storage.upload',
        () => supabase.storage
            .from(bucket)
            .uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            ),
      );
      final publicUrl = supabase.storage.from(bucket).getPublicUrl(path);
      urls.add(publicUrl);
    }
    return urls;
  }

  /// Upload a single file to a bucket and return a signed URL (for private buckets like labels).
  Future<String> uploadBytesAndSign({
    required Uint8List data,
    required String fileName,
    required String bucket,
    int expiresInSeconds = 60 * 60 * 24, // 24h
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required to upload files.');
    final safeFileName = _sanitizeFileName(fileName);
    final path = '$userId/${_uuid.v4()}-$safeFileName';
    await RateLimiter.instance.run(
      'storage.upload.sign',
      () => supabase.storage.from(bucket).uploadBinary(
            path,
            data,
            fileOptions: const FileOptions(upsert: true),
          ),
    );
    final signed = await RateLimiter.instance.run(
      'storage.sign',
      () => supabase.storage.from(bucket).createSignedUrl(path, expiresInSeconds),
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
    final userId = ownerId ?? supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required to upload files.');
    final safeFileName = _sanitizeFileName(fileName);
    final path = '$userId/${_uuid.v4()}-$safeFileName';
    await RateLimiter.instance.run(
      'storage.upload.private',
      () => supabase.storage
          .from(bucket)
          .uploadBinary(path, data, fileOptions: const FileOptions(upsert: true)),
    );
    return path;
  }

  String _sanitizeFileName(String input) {
    final base = InputSanitizer.sanitizeText(input, maxLength: 120);
    final slashCleaned = base.replaceAll(RegExp(r'[\\/]+'), '-');
    final collapsed = slashCleaned.replaceAll(RegExp(r'\s+'), '-');
    final safe = collapsed.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '');
    final trimmed = safe.replaceAll(RegExp(r'[-_.]{2,}'), '-').trim();
    return trimmed.isEmpty ? 'file' : trimmed;
  }
}
