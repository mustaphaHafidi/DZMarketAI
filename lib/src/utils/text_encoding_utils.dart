import 'dart:convert';

bool looksLikeMojibake(String value) {
  if (value.isEmpty) return false;
  if (value.contains('\uFFFD')) return true;
  if (value.contains('\u00C3') ||
      value.contains('\u00C2') ||
      value.contains('\u00D8') ||
      value.contains('\u00D9')) {
    return true;
  }
  if (value.contains('\u00E2\u20AC\u2122') ||
      value.contains('\u00E2\u20AC\u201C') ||
      value.contains('\u00E2\u20AC\u201D')) {
    return true;
  }
  if (RegExp(r'Ã.|Â.|Ø.|Ù.|â€').hasMatch(value)) return true;
  return false;
}

String repairMojibake(String? value) {
  final input = value?.trim() ?? '';
  if (input.isEmpty || !looksLikeMojibake(input)) return input;
  var candidate = input;
  for (var i = 0; i < 3; i++) {
    try {
      final decoded = utf8.decode(
        latin1.encode(candidate),
        allowMalformed: true,
      );
      final normalized = decoded.trim();
      if (normalized.isEmpty || normalized == candidate) break;
      candidate = normalized;
    } catch (_) {
      break;
    }
    if (!looksLikeMojibake(candidate)) {
      return candidate;
    }
  }
  return candidate;
}
