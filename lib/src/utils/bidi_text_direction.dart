import 'package:flutter/widgets.dart' show TextDirection;

/// Picks the direction a free-text block (e.g. a listing description)
/// should render in, independent of the app's current UI locale.
///
/// A description written mostly in French must stay left-to-right even
/// when the app is in Arabic, and vice versa -- otherwise punctuation,
/// numbers and paragraph alignment look reversed/mixed up when a seller
/// writes in one language while the app locale is the other. Uses the
/// standard "first strong character" rule (same heuristic as HTML's
/// `dir="auto"`): the first character with inherent directionality
/// decides the whole block; digits, spaces and punctuation are skipped.
TextDirection detectTextDirection(String? text) {
  if (text == null) return TextDirection.ltr;
  for (final rune in text.runes) {
    if (_isRtlRune(rune)) return TextDirection.rtl;
    if (_isLtrRune(rune)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

bool _isRtlRune(int rune) {
  // Hebrew, Arabic, Arabic Supplement, Arabic Presentation Forms.
  return (rune >= 0x0590 && rune <= 0x08FF) ||
      (rune >= 0xFB1D && rune <= 0xFDFF) ||
      (rune >= 0xFE70 && rune <= 0xFEFF);
}

bool _isLtrRune(int rune) {
  // Basic Latin letters + Latin-1 Supplement/Extended (accented FR chars).
  return (rune >= 0x0041 && rune <= 0x005A) ||
      (rune >= 0x0061 && rune <= 0x007A) ||
      (rune >= 0x00C0 && rune <= 0x02AF);
}
