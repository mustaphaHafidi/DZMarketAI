import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ModerationResult {
  const ModerationResult({
    required this.allowed,
    required this.action,
    this.reason,
    this.labels,
    this.score,
  });

  final bool allowed;
  final String action;
  final String? reason;
  final List<String>? labels;
  final double? score;

  factory ModerationResult.fromJson(Map<String, dynamic> json) {
    final labels = (json['labels'] as List?)
        ?.map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    final score = json['score'] as num?;
    return ModerationResult(
      allowed: json['allowed'] == true,
      action:
          json['action']?.toString() ??
          (json['allowed'] == true ? 'allow' : 'block'),
      reason: json['reason']?.toString(),
      labels: labels,
      score: score?.toDouble(),
    );
  }
}

class ModerationService {
  static const _functionName = 'moderate-content';

  String _unavailableMessage() {
    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    return L10n.trLocale(locale, 'moderation.unavailable');
  }

  bool _isModerationUnavailable(Object error) {
    bool hasUnavailableMarkers(String value) {
      final raw = value.toLowerCase();
      return raw.contains('status: 404') ||
          raw.contains('status: 503') ||
          raw.contains('status: 500') ||
          raw.contains('not_found') ||
          raw.contains('requested function was not found') ||
          raw.contains('service unavailable') ||
          raw.contains('sightengine_user') ||
          raw.contains('sightengine_secret') ||
          raw.contains('socketexception') ||
          raw.contains('failed host lookup') ||
          raw.contains('timed out') ||
          raw.contains('timeout');
    }

    if (error is FormatException && error.message == _unavailableMessage()) {
      return true;
    }
    if (error is FunctionException) {
      if (error.status == 404 || error.status >= 500) {
        return true;
      }
      if (hasUnavailableMarkers('${error.details}')) {
        return true;
      }
    }
    return hasUnavailableMarkers(error.toString());
  }

  Future<ModerationResult> moderateText(String text) async {
    final safeText = InputSanitizer.sanitizeText(
      text,
      maxLength: 1200,
      allowNewlines: true,
    );
    if (safeText.isEmpty) {
      return const ModerationResult(allowed: true, action: 'allow');
    }
    try {
      final response = await RateLimiter.instance.run(
        'moderation.text',
        () => supabase.functions.invoke(
          _functionName,
          body: {'text': safeText, 'type': 'chat'},
        ),
      );
      if (response.data is! Map) {
        throw FormatException(_unavailableMessage());
      }
      return ModerationResult.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } catch (e) {
      if (_isModerationUnavailable(e)) {
        return const ModerationResult(allowed: true, action: 'allow');
      }
      rethrow;
    }
  }

  Future<ModerationResult> moderateListing({
    required String title,
    String? description,
    List<String> imageUrls = const [],
    String? categorySlug,
    String? policyProfile,
  }) async {
    final safeTitle = InputSanitizer.sanitizeText(title, maxLength: 120);
    final safeDescription = InputSanitizer.sanitizeOptionalText(
      description,
      maxLength: 2000,
      allowNewlines: true,
    );
    final safeImages = InputSanitizer.sanitizeUrlList(imageUrls, maxItems: 5);
    final safeCategorySlug = InputSanitizer.sanitizeOptionalText(
      categorySlug,
      maxLength: 60,
    );
    final safePolicyProfile = InputSanitizer.sanitizeOptionalText(
      policyProfile,
      maxLength: 40,
    );
    try {
      final response = await RateLimiter.instance.run(
        'moderation.listing',
        () => supabase.functions.invoke(
          _functionName,
          body: {
            'text': [
              safeTitle,
              safeDescription,
            ].where((e) => e != null && e.isNotEmpty).join('\n'),
            'image_urls': safeImages,
            'type': 'listing',
            if (safeCategorySlug != null && safeCategorySlug.isNotEmpty)
              'category_slug': safeCategorySlug,
            if (safePolicyProfile != null && safePolicyProfile.isNotEmpty)
              'policy_profile': safePolicyProfile,
          },
        ),
      );
      if (response.data is! Map) {
        throw FormatException(_unavailableMessage());
      }
      return ModerationResult.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } catch (e) {
      if (_isModerationUnavailable(e)) {
        return const ModerationResult(allowed: true, action: 'allow');
      }
      rethrow;
    }
  }
}
