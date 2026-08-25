class InputSanitizer {
  static String sanitizeText(
    String input, {
    int maxLength = 200,
    bool allowNewlines = false,
  }) {
    var value = input.trim();
    value = value.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '');
    if (!allowNewlines) {
      value = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
    }
    if (value.length > maxLength) {
      value = value.substring(0, maxLength);
    }
    return value;
  }

  static String? sanitizeOptionalText(
    String? input, {
    int maxLength = 200,
    bool allowNewlines = false,
  }) {
    if (input == null) return null;
    final value = sanitizeText(
      input,
      maxLength: maxLength,
      allowNewlines: allowNewlines,
    );
    return value.isEmpty ? null : value;
  }

  static String sanitizeEmail(String input) {
    final value = sanitizeText(input, maxLength: 254).toLowerCase();
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(value)) {
      throw FormatException('Invalid email.');
    }
    return value;
  }

  static String normalizeEmailForSignUp(String input) {
    final value = sanitizeEmail(input);
    final at = value.lastIndexOf('@');
    if (at <= 0) return value;
    final local = value.substring(0, at);
    final domain = value.substring(at + 1);
    if (domain != 'gmail.com' && domain != 'googlemail.com') return value;
    final normalizedLocal = local.split('+').first.replaceAll('.', '');
    if (normalizedLocal.isEmpty) return value;
    return '$normalizedLocal@gmail.com';
  }

  static String sanitizePassword(
    String input, {
    int minLength = 8,
    int maxLength = 128,
  }) {
    final value = input.trim();
    if (value.length < minLength) {
      throw FormatException('Password too short.');
    }
    if (value.length > maxLength) {
      throw FormatException('Password too long.');
    }
    return value;
  }

  static String sanitizeSearchQuery(String input, {int maxLength = 80}) {
    var value = sanitizeText(input, maxLength: maxLength);
    value = value.replaceAll(',', ' ');
    value = value.replaceAll(RegExp(r'[()]'), ' ');
    return value.trim();
  }

  static String sanitizeId(String input, {int maxLength = 64}) {
    final value = sanitizeText(input, maxLength: maxLength);
    if (value.isEmpty) {
      throw FormatException('Invalid id.');
    }
    return value;
  }

  static String? sanitizePhone(String? input, {int maxLength = 20}) {
    final value = sanitizeOptionalText(input, maxLength: maxLength);
    if (value == null) return null;
    final cleaned = value.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) {
      throw FormatException('Invalid phone.');
    }
    return cleaned;
  }

  static String? sanitizeUrl(String? input, {int maxLength = 300}) {
    final value = sanitizeOptionalText(input, maxLength: maxLength);
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw FormatException('Invalid URL.');
    }
    return uri.toString();
  }

  static String? safeUrl(String? input, {int maxLength = 300}) {
    final value = sanitizeOptionalText(input, maxLength: maxLength);
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri.toString();
  }

  static List<String> sanitizeUrlList(List<String> urls, {int maxItems = 6}) {
    final cleaned = <String>[];
    for (final url in urls) {
      final sanitized = sanitizeUrl(url);
      if (sanitized != null) {
        cleaned.add(sanitized);
      }
      if (cleaned.length >= maxItems) break;
    }
    return cleaned;
  }

  static double parseAmount(
    String input, {
    double min = 0,
    double max = 100000000,
  }) {
    final value = sanitizeText(input, maxLength: 32);
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < min || parsed > max) {
      throw FormatException('Invalid amount.');
    }
    return parsed;
  }

  static double offerMinAmountFromBasePrice(
    double? basePrice, {
    double ratio = 0.5,
    double minimum = 1,
  }) {
    final base = (basePrice ?? 0).isFinite ? (basePrice ?? 0) : 0;
    final computed = (base * ratio).ceilToDouble();
    if (computed < minimum) return minimum;
    return computed;
  }
}
