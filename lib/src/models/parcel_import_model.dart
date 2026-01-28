import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/location_data_service.dart';

class ParcelImportModel {
  ParcelImportModel({
    required this.orderId,
    required this.fromWilayaName,
    required this.firstName,
    required this.familyName,
    required this.contactPhone,
    required this.address,
    required this.toWilayaName,
    required this.toCommuneName,
    required this.productList,
    required this.price,
    required this.weight,
    required this.height,
    required this.width,
    required this.length,
    required this.doInsurance,
    required this.declaredValue,
    required this.isStopdesk,
    this.stopdeskId,
    required this.hasExchange,
    this.productToCollect,
  });

  final String orderId;
  final String fromWilayaName;
  final String firstName;
  final String familyName;
  final String contactPhone;
  final String address;
  final String toWilayaName;
  final String toCommuneName;
  final String productList;
  final int price;
  final int weight;
  final int height;
  final int width;
  final int length;
  final bool doInsurance;
  final int declaredValue;
  final bool isStopdesk;
  final int? stopdeskId;
  final bool hasExchange;
  final String? productToCollect;

  Map<String, dynamic> toYalidinePayload() {
    return {
      'order_id': orderId,
      'from_wilaya_name': fromWilayaName,
      'firstname': firstName,
      'familyname': familyName,
      'contact_phone': contactPhone,
      'address': address,
      'to_wilaya_name': toWilayaName,
      'to_commune_name': toCommuneName,
      'product_list': productList,
      'price': price,
      'do_insurance': doInsurance,
      'declared_value': declaredValue,
      'height': height,
      'width': width,
      'length': length,
      'weight': weight,
      'freeshipping': false,
      'is_stopdesk': isStopdesk,
      if (stopdeskId != null) 'stopdesk_id': stopdeskId,
      'has_exchange': hasExchange,
      if (productToCollect != null) 'product_to_collect': productToCollect,
    };
  }

  static Future<ParcelImportModel> fromCheckout({
    required String orderId,
    required String senderWilaya,
    required String receiverFullName,
    required String receiverPhone,
    required String receiverAddress,
    required String receiverWilayaName,
    required String receiverCommuneName,
    required String productList,
    required double price,
    required double weight,
    String? receiverWilayaCode,
  }) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeSenderWilaya =
        InputSanitizer.sanitizeText(senderWilaya, maxLength: 80);
    final safeReceiverName =
        InputSanitizer.sanitizeText(receiverFullName, maxLength: 80);
    final safeReceiverPhone = InputSanitizer.sanitizePhone(receiverPhone);
    final safeReceiverAddress =
        InputSanitizer.sanitizeText(receiverAddress, maxLength: 140);
    final safeReceiverWilaya =
        InputSanitizer.sanitizeText(receiverWilayaName, maxLength: 80);
    final safeReceiverCommune =
        InputSanitizer.sanitizeText(receiverCommuneName, maxLength: 80);
    final safeProductList =
        InputSanitizer.sanitizeText(productList, maxLength: 120);

    if (safeReceiverPhone == null) {
      throw const FormatException('Telephone invalide');
    }

    final nameParts = safeReceiverName
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final firstName = nameParts.isNotEmpty ? nameParts.first : safeReceiverName;
    final familyName =
        nameParts.length > 1 ? nameParts.sublist(1).join(' ') : safeReceiverName;

    final locationService = LocationDataService.instance;
    final wilayas = await locationService.fetchWilayas();
    final senderMatch = wilayas.firstWhere(
      (w) =>
          (w['code'] ?? '') == safeSenderWilaya ||
          (w['name_fr'] ?? '').toLowerCase() ==
              safeSenderWilaya.toLowerCase() ||
          (w['name_ar'] ?? '').toLowerCase() ==
              safeSenderWilaya.toLowerCase(),
      orElse: () => {},
    );
    final officialSenderWilaya = senderMatch['name_fr'];
    if (officialSenderWilaya == null || officialSenderWilaya.isEmpty) {
      throw const FormatException('Wilaya expedition invalide');
    }
    String? officialWilaya;
    String? wilayaCode = receiverWilayaCode;

    if (wilayaCode == null || wilayaCode.isEmpty) {
      final match = wilayas.firstWhere(
        (w) =>
            (w['name_fr'] ?? '').toLowerCase() ==
                safeReceiverWilaya.toLowerCase() ||
            (w['name_ar'] ?? '').toLowerCase() ==
                safeReceiverWilaya.toLowerCase(),
        orElse: () => {},
      );
      wilayaCode = match['code'];
      officialWilaya = match['name_fr'];
    } else {
      final match = wilayas.firstWhere(
        (w) => (w['code'] ?? '') == wilayaCode,
        orElse: () => {},
      );
      officialWilaya = match['name_fr'];
    }

    if (wilayaCode == null || wilayaCode.isEmpty || officialWilaya == null) {
      throw const FormatException('Wilaya invalide');
    }

    final communes = await locationService.fetchCommunes(wilayaCode);
    final communeMatch = communes.firstWhere(
      (c) =>
          (c['name_fr'] ?? '').toLowerCase() ==
              safeReceiverCommune.toLowerCase() ||
          (c['name_ar'] ?? '').toLowerCase() ==
              safeReceiverCommune.toLowerCase(),
      orElse: () => {},
    );
    final officialCommune = communeMatch['name_fr'];
    if (officialCommune == null || officialCommune.isEmpty) {
      throw const FormatException('Commune invalide');
    }

    return ParcelImportModel(
      orderId: safeOrderId,
      fromWilayaName: officialSenderWilaya,
      firstName: firstName,
      familyName: familyName,
      contactPhone: safeReceiverPhone,
      address: safeReceiverAddress,
      toWilayaName: officialWilaya,
      toCommuneName: officialCommune,
      productList: safeProductList,
      price: price.round(),
      weight: weight.round(),
      height: 0,
      width: 0,
      length: 0,
      doInsurance: false,
      declaredValue: price.round(),
      isStopdesk: false,
      hasExchange: false,
    );
  }
}
