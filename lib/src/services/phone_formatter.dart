class PhoneFormatter {
  /// Returns the canonical E.164 form for an Algerian mobile number.
  ///
  /// The public seller-contact flow supports the three mobile prefixes 05,
  /// 06 and 07 only. Empty or non-Algerian values are intentionally rejected.
  static String normalizeDzMobileE164(String value) {
    var digits = value.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('00')) {
      digits = '+${digits.substring(2)}';
    }
    if (RegExp(r'^0[567]\d{8}$').hasMatch(digits)) {
      return '+213${digits.substring(1)}';
    }
    if (RegExp(r'^\+213[567]\d{8}$').hasMatch(digits)) {
      return digits;
    }
    if (RegExp(r'^\+2130[567]\d{8}$').hasMatch(digits)) {
      return '+213${digits.substring(5)}';
    }
    return '';
  }

  static String formatDzMobile(String value) {
    final normalized = normalizeDzMobileE164(value);
    if (normalized.isEmpty) return '';
    final national = '0${normalized.substring(4)}';
    return '${national.substring(0, 3)} ${national.substring(3, 6)} '
        '${national.substring(6, 8)} ${national.substring(8)}';
  }

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
