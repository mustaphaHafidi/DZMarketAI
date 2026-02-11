import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class ModerationResult {
  const ModerationResult({
    required this.allowed,
    this.reason,
    this.labels,
    this.score,
  });

  final bool allowed;
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

  Future<ModerationResult> moderateText(String text) async {
    final safeText = InputSanitizer.sanitizeText(
      text,
      maxLength: 1200,
      allowNewlines: true,
    );
    if (safeText.isEmpty) {
      return const ModerationResult(allowed: true);
    }
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
  }

  Future<ModerationResult> moderateListing({
    required String title,
    String? description,
    List<String> imageUrls = const [],
  }) async {
    final safeTitle = InputSanitizer.sanitizeText(title, maxLength: 120);
    final safeDescription = InputSanitizer.sanitizeOptionalText(
      description,
      maxLength: 2000,
      allowNewlines: true,
    );
    final safeImages = InputSanitizer.sanitizeUrlList(imageUrls, maxItems: 6);
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
        },
      ),
    );
    if (response.data is! Map) {
      throw FormatException(_unavailableMessage());
    }
    return ModerationResult.fromJson(
      (response.data as Map).cast<String, dynamic>(),
    );
  }
}
