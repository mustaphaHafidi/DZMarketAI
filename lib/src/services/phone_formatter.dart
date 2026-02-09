class PhoneFormatter {
  static String normalizeDzE164(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    var cleaned = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.startsWith('00')) {
      cleaned = '+${cleaned.substring(2)}';
    }
    if (cleaned.startsWith('+')) {
      final digits = cleaned.substring(1).replaceAll(RegExp(r'\D'), '');
      if (digits.startsWith('2130')) {
        final fixed = '213${digits.substring(4)}';
        if (fixed.length < 8) return '';
        return '+$fixed';
      }
      if (digits.length < 8) return '';
      return '+$digits';
    }
    var digits = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('213')) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length < 8) return '';
    if (digits.length > 9) {
      digits = digits.substring(digits.length - 9);
    }
    return '+213$digits';
  }

  static String normalizeDzE164ForZr(String value) {
    final normalized = normalizeDzE164(value);
    if (normalized.isEmpty) return '';
    final national = normalized.replaceFirst('+213', '');
    if (national.startsWith('5') || national.startsWith('6')) {
      return normalized;
    }
    return '';
  }

  static bool isZrExpressCompatible(String value) =>
      normalizeDzE164ForZr(value).isNotEmpty;
}
