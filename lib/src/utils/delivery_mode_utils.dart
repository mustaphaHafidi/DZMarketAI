String _normalizeDeliveryToken(String? value) {
  if (value == null) return '';
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

bool isArrangedDeliveryValue(String? value) {
  final token = _normalizeDeliveryToken(value);
  if (token.isEmpty) return false;
  return token == 'pickup' ||
      token == 'livraisonaconvenir' ||
      token == 'deliveryarranged' ||
      token == 'arrangeddelivery' ||
      token == 'remiseenmainpropre' ||
      token == 'mainpropre';
}

bool isArrangedDelivery({
  String? deliveryMethod,
  String? shippingOption,
}) {
  return isArrangedDeliveryValue(deliveryMethod) ||
      isArrangedDeliveryValue(shippingOption);
}
