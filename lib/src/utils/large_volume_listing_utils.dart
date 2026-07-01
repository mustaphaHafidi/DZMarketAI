final RegExp _largeVolumeKeywordPattern = RegExp(
  r'\b(?:voiture|voitures|moto|motos|camion|camions|meuble|meubles|canape|canapes|armoire|armoires|frigo|frigos|refrigerateur|refrigerateurs|climatiseur|climatiseurs|lit|lits|table|tables|bureau|bureaux|vehicle|vehicles|furniture)\b|lave[- ]linge|machine[- ]a[- ]laver',
  caseSensitive: false,
);

bool hasLargeVolumeListingKeywords(Iterable<String?> values) {
  final text = values
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(' ');
  if (text.isEmpty) return false;
  return _largeVolumeKeywordPattern.hasMatch(text);
}
