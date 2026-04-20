String _takeLeadingCharacters(String value, int count) {
  return value.runes.take(count).map(String.fromCharCode).join();
}

String userInitials({String? fullName, String? email}) {
  final normalizedName = fullName?.trim() ?? '';
  final emailLocalPart = (email?.trim().split('@').first ?? '')
      .replaceAll(RegExp(r'[._-]+'), ' ')
      .trim();
  final source = normalizedName.isNotEmpty ? normalizedName : emailLocalPart;
  if (source.isEmpty) return '?';

  final parts = source
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';

  if (parts.length >= 2) {
    final first = _takeLeadingCharacters(parts.first, 1);
    final last = _takeLeadingCharacters(parts.last, 1);
    final initials = '$first$last'.trim();
    return initials.isEmpty ? '?' : initials.toUpperCase();
  }

  final single = _takeLeadingCharacters(parts.first, 2).trim();
  return single.isEmpty ? '?' : single.toUpperCase();
}
