import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class ListingSuggestion {
  const ListingSuggestion({
    this.category,
    this.tags = const [],
    this.score = 0,
  });

  final Map<String, String>? category;
  final List<String> tags;
  final int score;

  bool get hasSuggestion => category != null || tags.isNotEmpty;
}

class ListingSuggestionService {
  static const int _maxImagesToScan = 3;
  static const int _maxTags = 8;
  static const double _minLabelConfidence = 0.62;
  static const double _minCategoryScore = 0.75;

  // Keep mappings explicit to avoid noisy suggestions.
  static const Map<String, List<String>> _categorySignals = {
    'electronics-computers': [
      'laptop',
      'notebook',
      'ordinateur',
      'pc',
      'computer',
      'clavier',
      'keyboard',
      'souris',
      'mouse',
      'monitor',
      'screen',
      'cpu',
    ],
    'electronics-phones': [
      'smartphone',
      'phone',
      'mobile phone',
      'cell phone',
      'telephone',
      'android',
      'iphone',
    ],
    'electronics-gaming': [
      'gaming',
      'game console',
      'video game console',
      'console',
      'gamepad',
      'controller',
      'joystick',
      'xbox',
      'playstation',
      'nintendo',
      'switch',
    ],
    'electronics-audio': [
      'headphone',
      'headphones',
      'earphone',
      'earphones',
      'headset',
      'speaker',
      'microphone',
      'audio',
    ],
    'home-appliances': [
      'refrigerator',
      'fridge',
      'washing machine',
      'microwave',
      'air conditioner',
      'tv',
      'television',
    ],
    'electronics': [
      'electronics',
      'electronic device',
      'computer',
      'phone',
      'television',
    ],
  };

  static const Map<String, String> _signalTagMap = {
    'laptop': 'laptop',
    'notebook': 'laptop',
    'computer': 'pc',
    'pc': 'pc',
    'keyboard': 'clavier',
    'mouse': 'souris',
    'monitor': 'ecran',
    'screen': 'ecran',
    'smartphone': 'smartphone',
    'phone': 'telephone',
    'mobile phone': 'telephone',
    'cell phone': 'telephone',
    'telephone': 'telephone',
    'iphone': 'iphone',
    'android': 'android',
    'gaming': 'gaming',
    'game console': 'console',
    'video game console': 'console',
    'console': 'console',
    'gamepad': 'manette',
    'controller': 'manette',
    'joystick': 'manette',
    'xbox': 'xbox',
    'playstation': 'playstation',
    'nintendo': 'nintendo',
    'switch': 'switch',
    'headphone': 'casque',
    'headphones': 'casque',
    'earphone': 'ecouteurs',
    'earphones': 'ecouteurs',
    'headset': 'casque',
    'speaker': 'speaker',
    'microphone': 'micro',
    'audio': 'audio',
    'refrigerator': 'frigo',
    'fridge': 'frigo',
    'washing machine': 'machinealaver',
    'microwave': 'microonde',
    'air conditioner': 'climatiseur',
    'tv': 'tv',
    'television': 'tv',
  };

  Future<ListingSuggestion> suggest({
    required List<String> imagePaths,
    required List<Map<String, String>> categories,
  }) async {
    if (categories.isEmpty) {
      return const ListingSuggestion();
    }
    final candidatePaths = imagePaths
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(_maxImagesToScan)
        .toList();
    if (candidatePaths.isEmpty) return const ListingSuggestion();

    final availableBySlug = <String, Map<String, String>>{};
    for (final category in categories) {
      final slug = (category['slug'] ?? '').trim();
      if (slug.isEmpty) continue;
      availableBySlug[slug] = category;
    }

    final labels = await _detectImageLabels(candidatePaths);
    if (labels.isEmpty) return const ListingSuggestion();

    final categoryScores = <String, double>{};
    for (final entry in _categorySignals.entries) {
      final category = availableBySlug[entry.key];
      if (category == null) continue;
      final score = _scoreCategory(labels, entry.value);
      if (score > 0) {
        categoryScores[entry.key] = score;
      }
    }

    Map<String, String>? bestCategory;
    var bestScore = 0.0;
    final sortedScores = categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sortedScores.isNotEmpty &&
        sortedScores.first.value >= _minCategoryScore) {
      bestCategory = availableBySlug[sortedScores.first.key];
      bestScore = sortedScores.first.value;
    }

    final tagScores = <String, double>{};
    for (final label in labels) {
      final tag = _resolveTag(label.text);
      if (tag == null) continue;
      final prev = tagScores[tag] ?? 0;
      if (label.confidence > prev) {
        tagScores[tag] = label.confidence;
      }
    }
    if (bestCategory != null) {
      final slug = bestCategory['slug'] ?? '';
      final parts = slug
          .split('-')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.length >= 3)
          .where((e) => RegExp(r'[a-z\u0600-\u06FF]').hasMatch(e));
      for (final part in parts) {
        tagScores.putIfAbsent(part, () => 0.01);
      }
    }
    final sortedTags = tagScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final finalTags = sortedTags
        .map((e) => _sanitizeTag(e.key))
        .whereType<String>()
        .take(_maxTags)
        .toList();

    return ListingSuggestion(
      category: bestCategory,
      tags: finalTags,
      score: (bestScore * 100).round(),
    );
  }

  Future<List<_DetectedLabel>> _detectImageLabels(
    List<String> imagePaths,
  ) async {
    final labeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: _minLabelConfidence),
    );
    final detected = <_DetectedLabel>[];
    try {
      for (final path in imagePaths) {
        final labels = await labeler.processImage(
          InputImage.fromFilePath(path),
        );
        for (final label in labels) {
          final normalized = _normalizeText(label.label);
          if (normalized.isEmpty) continue;
          detected.add(
            _DetectedLabel(
              text: normalized,
              confidence: label.confidence.clamp(0.0, 1.0),
            ),
          );
        }
      }
    } finally {
      await labeler.close();
    }
    return detected;
  }

  double _scoreCategory(List<_DetectedLabel> labels, List<String> signals) {
    var score = 0.0;
    for (final signal in signals) {
      final normalizedSignal = _normalizeText(signal);
      if (normalizedSignal.isEmpty) continue;
      for (final label in labels) {
        if (_labelContainsSignal(label.text, normalizedSignal)) {
          score += label.confidence;
        }
      }
    }
    return score;
  }

  String? _resolveTag(String normalizedLabel) {
    for (final entry in _signalTagMap.entries) {
      final signal = _normalizeText(entry.key);
      if (signal.isEmpty) continue;
      if (_labelContainsSignal(normalizedLabel, signal)) {
        return entry.value;
      }
    }
    return null;
  }

  bool _labelContainsSignal(String label, String signal) {
    if (signal.contains(' ')) {
      return label.contains(signal);
    }
    return RegExp('(^|\\s)$signal(\\s|\$)').hasMatch(label);
  }

  String _normalizeText(String input) {
    var value = input.toLowerCase();
    value = value
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c');
    value = value.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value;
  }

  String? _sanitizeTag(String raw) {
    final token = InputSanitizer.sanitizeText(raw, maxLength: 24).toLowerCase();
    if (token.length < 2) return null;
    final compact = token.replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF_-]'), '');
    if (compact.length < 2) return null;
    if (!RegExp(r'[a-z\u0600-\u06FF]').hasMatch(compact)) return null;
    if (RegExp(r'^\d+$').hasMatch(compact)) return null;
    return compact;
  }
}

class _DetectedLabel {
  const _DetectedLabel({required this.text, required this.confidence});

  final String text;
  final double confidence;
}
