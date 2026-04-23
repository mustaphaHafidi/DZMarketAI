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

bool isArrangedDelivery({String? deliveryMethod, String? shippingOption}) {
  return isArrangedDeliveryValue(deliveryMethod) ||
      isArrangedDeliveryValue(shippingOption);
}

bool isArrangedOrderSystemEvent({
  required String? i18nKey,
  required bool isOfferEvent,
  String? deliveryMethod,
  String? shippingOption,
}) {
  if (isOfferEvent) return false;
  if (i18nKey == 'order.system.pickup_request') return true;
  if (i18nKey == null || i18nKey.isEmpty) return false;
  final isOrderEvent =
      i18nKey.startsWith('order.system.') || i18nKey.startsWith('chat.order.');
  if (!isOrderEvent) return false;
  return isArrangedDelivery(
    deliveryMethod: deliveryMethod,
    shippingOption: shippingOption,
  );
}

String? arrangedDeliverySystemMessageKey(String? i18nKey) {
  switch (i18nKey) {
    case 'order.system.validated':
      return 'order.system.arranged_validated';
    case 'order.system.shipped':
    case 'order.system.tracking':
      return 'order.system.arranged_confirmed';
    case 'order.system.label_reminder':
    case 'order.system.carrier_scan_reminder':
      return 'order.system.arranged_no_label';
    default:
      return i18nKey;
  }
}

bool isTrackingReminderSystemEvent(String? i18nKey) {
  switch (i18nKey) {
    case 'order.system.label_reminder':
    case 'order.system.carrier_scan_reminder':
      return true;
    default:
      return false;
  }
}
