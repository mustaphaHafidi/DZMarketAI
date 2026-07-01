String _normalizeAmountToken(String value) {
  return value.replaceAll(RegExp(r'[^0-9]'), '');
}

bool isDeclaredValueManualOverride({
  required String priceText,
  required String declaredValueText,
}) {
  final declared = declaredValueText.trim();
  if (declared.isEmpty) return false;
  return _normalizeAmountToken(declared) != _normalizeAmountToken(priceText);
}

String nextDeclaredValueFromPrice({
  required String priceText,
  required String currentDeclaredValueText,
  required bool manuallyEdited,
}) {
  if (manuallyEdited && currentDeclaredValueText.trim().isNotEmpty) {
    return currentDeclaredValueText.trim();
  }
  return priceText.trim();
}
