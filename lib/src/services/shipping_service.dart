import 'dart:convert';
import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/message.dart';
import 'package:dzmarket/src/models/parcel_import_model.dart';
import 'package:dzmarket/src/models/shipment.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/label_service.dart';
import 'package:dzmarket/src/services/message_service.dart';
import 'package:dzmarket/src/services/notification_service.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/services/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// Simple generic cache item with expiry.
class _CacheItem<T> {
  final T value;
  final DateTime expiry;
  _CacheItem(this.value, this.expiry);
  bool get isExpired => DateTime.now().isAfter(expiry);
}

class ShippingService {
  // Shared HTTP client to reuse connections across instances.
  static final http.Client _httpClient = http.Client();

  // Simple in-memory cache for Yalidine responses to avoid repeated network calls
  // when UI re-opens forms. Cache keys are based on API credentials and
  // optionally wilaya code for communes.
  static const Duration _cacheTtl = Duration(minutes: 30);
  static final Map<String, _CacheItem<List<Map<String, String>>>> _yalidineWilayasCache = {};
  static final Map<String, _CacheItem<List<Map<String, String>>>> _yalidineCommunesCache = {};
  static final Map<String, _CacheItem<Map<String, dynamic>>> _ecotrackFeesCache = {};
  static const options = <String>[
    'Livraison domicile (24-72h)',
    'Point relais / bureau poste',
    'Coursier local (même ville)',
  ];

  static const couriers = <Map<String, String>>[
    {
      'id': 'yalidine',
      'name': 'Yalidine Express',
      'contact': 'contact@yalidine.com',
      'coverage': 'National',
    },
    {
      'id': 'imir',
      'name': 'Imir Logistics',
      'contact': 'contact@imir.dz',
      'coverage': 'National',
    },
    {
      'id': 'chronorex',
      'name': 'Chronorex Express',
      'contact': 'contact@chronorex.com',
      'coverage': 'National',
    },
    {
      'id': 'sms-express',
      'name': 'SMS Express',
      'contact': 'contact@smsexpress.dz',
      'coverage': 'National',
    },
    {
      'id': 'ems',
      'name': 'EMS Champion Post (Algerie Poste)',
      'contact': 'contact@poste.dz',
      'coverage': 'National',
    },
    {
      'id': 'beez',
      'name': 'Beez Delivery',
      'contact': 'contact@beez.dz',
      'coverage': 'Local/National',
    },
    {
      'id': 'livrator',
      'name': 'Livrator',
      'contact': 'contact@livrator.dz',
      'coverage': 'Local/National',
    },
    {
      'id': 'raha',
      'name': 'Raha Express',
      'contact': 'contact@raha.dz',
      'coverage': 'Local/National',
    },
    {
      'id': 'tozali',
      'name': 'Tozali Delivery',
      'contact': 'contact@tozali.dz',
      'coverage': 'Local/National',
    },
    {
      'id': 'ecotrack',
      'name': 'Ecotrack',
      'contact': 'contact@ecotrack.dz',
      'coverage': 'Local/National',
    },
  ];

  Future<List<Map<String, String>>> fetchCouriers() async => couriers;

  static Map<String, String> deliveryMode(String option) {
    if (option.contains('Coursier')) return {'mode': 'local_driver'};
    if (option.contains('relais') || option.contains('poste')) {
      return {'mode': 'pickup_postal'};
    }
    return {'mode': 'home'};
  }

  Stream<Shipment?> streamShipment(String orderId) {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    return RateLimiter.instance.stream(
      'shipments.stream',
      () => supabase
          .from(SupabaseTables.shipments)
          .stream(primaryKey: ['order_id'])
          .eq('order_id', safeOrderId)
          .map((rows) => rows.isNotEmpty ? Shipment.fromJson(rows.first) : null),
    );
  }

  Future<List<Map<String, dynamic>>> fetchEnabledCouriersForSeller(
    String sellerId,
  ) async {
    final safeSellerId = InputSanitizer.sanitizeId(sellerId, maxLength: 64);
    try {
      final rows = await RateLimiter.instance.run(
        'shipments.couriers.rpc',
        () => supabase.rpc(
          'get_enabled_couriers_for_seller',
          params: {'seller_id': safeSellerId},
        ),
      );
      if (rows is List) {
        return rows
            .map(
              (r) => {
                'courier_id': (r as Map)['courier_id'],
                'courier_name': r['courier_name'],
              },
            )
            .toList();
      }
    } catch (_) {
      // swallow and try fallback
    }

    try {
      // Fallback if RPC unavailable: attempt direct select (may be blocked by RLS)
      final rows = await RateLimiter.instance.run(
        'shipments.couriers.select',
        () => supabase
            .from('seller_delivery_settings')
            .select('courier_id, api_key, api_secret, sender_id, couriers(name)')
            .eq('owner_id', safeSellerId)
            .not('api_key', 'is', null)
            .not('api_secret', 'is', null),
      );
      return rows
          .map(
            (r) => {
              'courier_id': r['courier_id'],
              'courier_name':
                  (r['couriers'] as Map?)?['name'] ?? 'Transporteur',
            },
          )
          .toList();
    } catch (_) {}
    return const [];
  }

  Future<void> appendCarrierEvent({
    required String orderId,
    required Map<String, dynamic> event,
  }) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeEvent = _sanitizeEvent(event);
    final rows = await RateLimiter.instance.run(
      'shipments.events.select',
      () => supabase
          .from(SupabaseTables.shipments)
          .select('events')
          .eq('order_id', safeOrderId)
          .maybeSingle(),
    );
    final current = (rows?['events'] as List?) ?? <dynamic>[];
    final updated = [...current, safeEvent];
    await RateLimiter.instance.run(
      'shipments.events.update',
      () => supabase
          .from(SupabaseTables.shipments)
          .update({'events': updated})
          .eq('order_id', safeOrderId),
    );
  }

  Future<void> createLabelForOrder({
    required String orderId,
    required String courierId,
    required String courierName,
    String? option,
    double? shippingCost,
    String? deliveryMode,
  }) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeCourierId = InputSanitizer.sanitizeText(courierId, maxLength: 64);
    final safeCourierName =
        InputSanitizer.sanitizeText(courierName, maxLength: 80);
    final safeOption = InputSanitizer.sanitizeOptionalText(option, maxLength: 60);
    final safeDelivery =
        InputSanitizer.sanitizeOptionalText(deliveryMode, maxLength: 40);
    await createShipment(
      orderId: safeOrderId,
      courierId: safeCourierId,
      courierName: safeCourierName,
      deliveryMode: safeDelivery,
      shippingOption: safeOption,
      shippingCost: shippingCost,
    );
  }

  Future<Map<String, dynamic>> createShipment({
    required String orderId,
    required String courierId,
    required String courierName,
    String? deliveryMode,
    String? shippingOption,
    double? shippingCost,
    Map<String, dynamic>? selection,
  }) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeCourierId = InputSanitizer.sanitizeText(courierId, maxLength: 64);
    final safeCourierName =
        InputSanitizer.sanitizeText(courierName, maxLength: 80);
    final safeDelivery =
        InputSanitizer.sanitizeOptionalText(deliveryMode, maxLength: 40);
    final safeOption =
        InputSanitizer.sanitizeOptionalText(shippingOption, maxLength: 60);
    final body = <String, dynamic>{
      'order_id': safeOrderId,
      'courier_id': safeCourierId,
      'courier_name': safeCourierName,
      if (safeDelivery != null) 'delivery_mode': safeDelivery,
      if (safeOption != null) 'shipping_option': safeOption,
      if (shippingCost != null) 'shipping_cost': shippingCost,
      if (selection != null) 'selection': selection,
    };
    final response = await RateLimiter.instance.run(
      'shipments.create.edge',
      () => supabase.functions.invoke(
        SupabaseOptions.createShipmentFunction,
        body: body,
      ),
    );
    final data = response.data;
    if (data is Map && data['ok'] == false) {
      throw StateError(data['message']?.toString() ?? 'Shipment failed');
    }
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {'ok': true};
  }

  double estimateCost({
    required String? buyerWilaya,
    required String? sellerWilaya,
  }) {
    if (buyerWilaya == null || sellerWilaya == null) return 500.0;
    return buyerWilaya.trim().toLowerCase() == sellerWilaya.trim().toLowerCase()
        ? 300.0
        : 700.0;
  }

  String estimateEtaLabel({String? courierName, String? courierId}) {
    final name = courierName?.toLowerCase() ?? '';
    final id = courierId?.toLowerCase() ?? '';
    if (name.contains('yalidine') || id.contains('yalidine')) {
      return '24-72h';
    }
    if (name.contains('chronorex') || id.contains('chronorex')) {
      return '24-48h';
    }
    if (name.contains('ecotrack') || id.contains('ecotrack')) {
      return '24-72h';
    }
    if (name.contains('ems') || id.contains('ems')) {
      return '48-96h';
    }
    return '48-96h';
  }
  Future<Map<String, dynamic>> createYalidineParcel({
    required Map<String, dynamic> settings,
    required Map<String, dynamic> parcel,
  }) async {
    final apiIdRaw = settings['api_key']?.toString();
    final tokenRaw = settings['api_secret']?.toString();
    final apiId = apiIdRaw == null
        ? null
        : InputSanitizer.sanitizeText(apiIdRaw, maxLength: 120);
    final token = tokenRaw == null
        ? null
        : InputSanitizer.sanitizeText(tokenRaw, maxLength: 120);
    if (apiId == null || token == null) {
      throw StateError('Yalidine API credentials missing');
    }
    final uri = Uri.parse('https://api.yalidine.app/v1/parcels/');
    final body = jsonEncode([parcel]);
    final resp = await RateLimiter.instance.run(
      'yalidine.parcels.create',
      () => _httpClient
          .post(
            uri,
            headers: {
              'X-API-ID': apiId,
              'X-API-TOKEN': token,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15)),
    );
    if (resp.statusCode >= 400) {
      throw Exception('Yalidine ${resp.statusCode}: ${resp.body}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is List && data.isNotEmpty) {
        return Map<String, dynamic>.from(data.first as Map);
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      final orderId = parcel['order_id']?.toString();
      if (orderId != null && decoded[orderId] is Map) {
        return Map<String, dynamic>.from(decoded[orderId] as Map);
      }
      return decoded;
    }
    if (decoded is List && decoded.isNotEmpty) {
      return Map<String, dynamic>.from(decoded.first as Map);
    }
    throw StateError('Yalidine response missing parcel data');
  }

  Future<Uint8List> _loadLabelBytes(String labelValue) async {
    final trimmed = labelValue.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final resp = await _httpClient
          .get(Uri.parse(trimmed))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode >= 400) {
        throw Exception('Label download failed: ${resp.statusCode}');
      }
      return resp.bodyBytes;
    }
    final base64Prefix = RegExp(r'^data:.*;base64,', caseSensitive: false);
    final cleaned = trimmed.replaceAll(base64Prefix, '');
    try {
      return base64Decode(cleaned);
    } catch (_) {
      throw Exception('Unsupported label payload');
    }
  }

  Future<void> generateYalidineParcelAndAttachLabel({
    required String orderId,
    required Map<String, dynamic> sellerCourierSettings,
    required String senderWilayaName,
    required String receiverName,
    required String receiverPhone,
    required String receiverAddress,
    required String receiverWilaya,
    required String receiverCommune,
    required String productList,
    required double price,
    required double weight,
    bool freeShipping = false,
    int lengthCm = 0,
    int widthCm = 0,
    int heightCm = 0,
  }) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeSenderWilaya =
        InputSanitizer.sanitizeText(senderWilayaName, maxLength: 80);
    final safeReceiverName =
        InputSanitizer.sanitizeText(receiverName, maxLength: 80);
    final safeReceiverPhone = InputSanitizer.sanitizePhone(receiverPhone);
    final safeReceiverAddress =
        InputSanitizer.sanitizeText(receiverAddress, maxLength: 140);
    final safeReceiverWilaya =
        InputSanitizer.sanitizeText(receiverWilaya, maxLength: 80);
    final safeReceiverCommune =
        InputSanitizer.sanitizeText(receiverCommune, maxLength: 80);
    final safeProductList =
        InputSanitizer.sanitizeText(productList, maxLength: 120);

    if (safeSenderWilaya.isEmpty ||
        safeReceiverWilaya.isEmpty ||
        safeReceiverCommune.isEmpty) {
      throw FormatException('Receiver location missing');
    }
    if (safeReceiverPhone == null) {
      throw FormatException('Receiver phone missing');
    }
    if (!RegExp(r'^0\\d{8,9}\$').hasMatch(safeReceiverPhone)) {
      throw FormatException('Receiver phone invalid for Yalidine');
    }

    final nameParts =
        safeReceiverName.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final firstName = nameParts.isNotEmpty ? nameParts.first : safeReceiverName;
    final familyName = nameParts.length > 1
        ? nameParts.sublist(1).join(' ')
        : safeReceiverName;

    final parcel = <String, dynamic>{
      'order_id': safeOrderId,
      'from_wilaya_name': safeSenderWilaya,
      'firstname': firstName,
      'familyname': familyName,
      'contact_phone': safeReceiverPhone,
      'address': safeReceiverAddress,
      'to_commune_name': safeReceiverCommune,
      'to_wilaya_name': safeReceiverWilaya,
      'product_list': safeProductList,
      'price': price.round(),
      'do_insurance': false,
      'declared_value': price.round(),
      'height': heightCm,
      'width': widthCm,
      'length': lengthCm,
      'weight': weight.round(),
      'freeshipping': freeShipping,
      'is_stopdesk': false,
      'has_exchange': false,
    };

    final result = await createYalidineParcel(
      settings: sellerCourierSettings,
      parcel: parcel,
    );
    if (result['success'] == false) {
      final message = result['message']?.toString() ?? 'Yalidine error';
      throw Exception(message);
    }
    final trackingNumber = result['tracking'] ??
        result['tracking_number'] ??
        result['tracking_id'] ??
        result['parcel_id'];
    final labelValue =
        result['label'] ??
        result['label_url'] ??
        result['label_pdf'] ??
        result['labels'];
    if (labelValue == null || labelValue.toString().isEmpty) {
      throw StateError('Yalidine label missing');
    }
    final bytes = await _loadLabelBytes(labelValue.toString());
    final signedUrl = await StorageService().uploadBytesAndSign(
      data: bytes,
      fileName: 'yalidine-$safeOrderId.pdf',
      bucket: SupabaseOptions.labelBucket,
    );

    await RateLimiter.instance.run(
      'shipments.upsert',
      () => supabase.from(SupabaseTables.shipments).upsert({
        'order_id': safeOrderId,
        'tracking_number': trackingNumber,
        'label_url': signedUrl,
        'status': 'shipped',
        'carrier': 'Yalidine Express',
        'option': null,
        'delivery_mode': 'home',
        'shipping_cost': null,
        'events': [
          {
            'title': 'Label generated',
            'description': 'Ready for carrier pickup',
            'at': DateTime.now().toIso8601String(),
          },
        ],
      }),
    );

    await RateLimiter.instance.run(
      'orders.update.label',
      () => supabase.from(SupabaseTables.orders).update({
        'tracking_number': trackingNumber,
        'label_url': signedUrl,
      }).eq('id', safeOrderId),
    );

    await MessageService().sendMessage(
      roomId: 'order:$safeOrderId',
      content: 'Bordereau disponible',
      type: MessageType.label,
      payload: {
        'label_url': signedUrl,
        'tracking_number': trackingNumber,
        'carrier': 'Yalidine Express',
      },
    );
  }

  Future<Map<String, dynamic>> generateYalidineParcelAndAttachLabelFromImport({
    required ParcelImportModel model,
    required Map<String, dynamic> sellerCourierSettings,
    bool freeShipping = false,
  }) async {
    final parcel = model.toYalidinePayload();
    parcel['freeshipping'] = freeShipping;
    final result = await createYalidineParcel(
      settings: sellerCourierSettings,
      parcel: parcel,
    );
    if (result['success'] == false) {
      final message = result['message']?.toString() ?? 'Yalidine error';
      throw Exception(message);
    }
    final trackingNumber = result['tracking'] ??
        result['tracking_number'] ??
        result['tracking_id'] ??
        result['parcel_id'];
    final labelValue =
        result['label'] ??
        result['label_url'] ??
        result['label_pdf'] ??
        result['labels'];
    if (labelValue == null || labelValue.toString().isEmpty) {
      throw StateError('Yalidine label missing');
    }
    final bytes = await _loadLabelBytes(labelValue.toString());
    final signedUrl = await StorageService().uploadBytesAndSign(
      data: bytes,
      fileName: 'yalidine-${model.orderId}.pdf',
      bucket: SupabaseOptions.labelBucket,
    );

    await RateLimiter.instance.run(
      'shipments.upsert',
      () => supabase.from(SupabaseTables.shipments).upsert({
        'order_id': model.orderId,
        'tracking_number': trackingNumber,
        'label_url': signedUrl,
        'status': 'shipped',
        'carrier': 'Yalidine Express',
        'option': null,
        'delivery_mode': model.isStopdesk ? 'stopdesk' : 'home',
        'shipping_cost': null,
        'events': [
          {
            'title': 'Label generated',
            'description': 'Ready for carrier pickup',
            'at': DateTime.now().toIso8601String(),
          },
        ],
      }),
    );

    await RateLimiter.instance.run(
      'orders.update.label',
      () => supabase.from(SupabaseTables.orders).update({
        'tracking_number': trackingNumber,
        'label_url': signedUrl,
      }).eq('id', model.orderId),
    );

    await MessageService().sendMessage(
      roomId: 'order:${model.orderId}',
      content: 'Bordereau disponible',
      type: MessageType.label,
      payload: {
        'label_url': signedUrl,
        'tracking_number': trackingNumber,
        'carrier': 'Yalidine Express',
      },
    );
    return {
      'delivery_fee': result['delivery_fee'],
      'taxe_percentage': result['taxe_percentage'],
      'taxe_retour': result['taxe_retour'],
      'price': result['price'] ?? model.price,
      'declared_value': result['declared_value'] ?? model.declaredValue,
      'tracking': trackingNumber,
      'label_url': signedUrl,
    };
  }

  Future<void> generateAndAttachLabel({
    required String orderId,
    required String carrier,
    String? option,
    double? shippingCost,
    String? deliveryMode,
    Map<String, dynamic>? sellerCourierSettings,
    String? receiverName,
    String? receiverPhone,
    String? receiverAddress,
    String? receiverCity,
    String? receiverDaira,
    String? receiverWilaya,
    String? receiverZip,
    double? parcelWeight,
    double? parcelPrice,
    String? parcelContent,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');

    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeCarrier = InputSanitizer.sanitizeText(carrier, maxLength: 80);
    final safeOption =
        InputSanitizer.sanitizeOptionalText(option, maxLength: 60);
    final safeDelivery =
        InputSanitizer.sanitizeOptionalText(deliveryMode, maxLength: 40);
    final safeReceiverName =
        InputSanitizer.sanitizeOptionalText(receiverName, maxLength: 80);
    final safeReceiverPhone = InputSanitizer.sanitizePhone(receiverPhone);
    final safeReceiverAddress =
        InputSanitizer.sanitizeOptionalText(receiverAddress, maxLength: 140);
    final safeReceiverCity =
        InputSanitizer.sanitizeOptionalText(receiverCity, maxLength: 80);
    final safeReceiverDaira =
        InputSanitizer.sanitizeOptionalText(receiverDaira, maxLength: 80);
    final safeReceiverWilaya =
        InputSanitizer.sanitizeOptionalText(receiverWilaya, maxLength: 80);
    final safeReceiverZip =
        InputSanitizer.sanitizeOptionalText(receiverZip, maxLength: 20);
    final safeContent =
        InputSanitizer.sanitizeOptionalText(parcelContent, maxLength: 120);

    final request = <String, dynamic>{
      'carrier': safeCarrier,
      if (safeOption != null) 'option': safeOption,
      if (shippingCost != null) 'shipping_cost': shippingCost,
      if (safeDelivery != null) 'delivery_mode': safeDelivery,
      if (safeReceiverName != null) 'receiver_name': safeReceiverName,
      if (safeReceiverPhone != null) 'receiver_phone': safeReceiverPhone,
      if (safeReceiverAddress != null) 'receiver_address': safeReceiverAddress,
      if (safeReceiverCity != null) 'receiver_city': safeReceiverCity,
      if (safeReceiverDaira != null) 'receiver_daira': safeReceiverDaira,
      if (safeReceiverWilaya != null) 'receiver_wilaya': safeReceiverWilaya,
      if (safeReceiverZip != null) 'receiver_zip': safeReceiverZip,
      if (parcelWeight != null) 'parcel_weight': parcelWeight,
      if (parcelPrice != null) 'parcel_price': parcelPrice,
      if (safeContent != null) 'parcel_content': safeContent,
      if (sellerCourierSettings != null) 'seller_settings': sellerCourierSettings,
    };

    final data = await LabelService().generateLabel(
      safeOrderId,
      request: request,
    );
    if (data == null || data.isEmpty) {
      throw StateError('Label generation failed');
    }
    final labelUrl =
        data['signed_url'] ?? data['label_url'] ?? data['label'];
    final trackingNumber =
        data['tracking_number'] ?? data['tracking'] ?? data['tracking_id'];
    if (labelUrl == null || labelUrl.toString().isEmpty) {
      throw StateError('Label URL missing from server response');
    }

    await RateLimiter.instance.run(
      'shipments.upsert',
      () => supabase.from(SupabaseTables.shipments).upsert({
      'order_id': safeOrderId,
      'tracking_number': trackingNumber,
      'label_url': labelUrl,
      'status': 'shipped',
      'carrier': safeCarrier,
      'option': safeOption,
      'delivery_mode': safeDelivery,
      'shipping_cost': shippingCost,
      'events': [
        {
          'title': 'Label généré',
          'description': 'Prêt pour prise en charge par $safeCarrier',
          'at': DateTime.now().toIso8601String(),
        },
      ],
      }),
    );
  }

  Future<void> appendDeliveryStatus(String orderId, String status) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeStatus = InputSanitizer.sanitizeText(status, maxLength: 30);
    await RateLimiter.instance.run(
      'shipments.status.update',
      () => supabase
          .from(SupabaseTables.shipments)
          .update({'status': safeStatus})
          .eq('order_id', safeOrderId),
    );
    await RateLimiter.instance.run(
      'orders.status.update',
      () => supabase
          .from(SupabaseTables.orders)
          .update({'status': safeStatus})
          .eq('id', safeOrderId),
    );

    final msg = MessageService();
    final roomId = 'order:$safeOrderId';
    await msg.sendMessage(
      roomId: roomId,
      content: 'Statut livraison: $safeStatus',
      type: MessageType.text,
      payload: {'type': 'delivery_status', 'status': safeStatus},
    );
    NotificationService.instance.notifyLocal(
      'Livraison mise à jour',
      'Statut: $safeStatus',
    );
  }

  Future<bool> validateCredentials({
    required String courierName,
    required String? apiKey,
    required String? apiSecret,
    String? senderId,
  }) async {
    final detailed = await validateCredentialsDetailed(
      courierName: courierName,
      apiKey: apiKey,
      apiSecret: apiSecret,
      senderId: senderId,
    );
    return detailed['ok'] == true;
  }


  Future<bool> _validateYalidine({
    required String apiKey,
    required String apiSecret,
  }) async {
    apiKey = apiKey.trim();
    apiSecret = apiSecret.trim();
    final wilayasUri = Uri.parse('https://api.yalidine.app/v1/wilayas/');
    try {
      // First try with provided ID/TOKEN and request JSON explicitly.
      final headers = {
        'X-API-ID': apiKey,
        'X-API-TOKEN': apiSecret,
        'Accept': 'application/json',
      };
      final resp = await RateLimiter.instance.run(
        'yalidine.validate',
        () => _httpClient
            .get(wilayasUri, headers: headers)
            .timeout(const Duration(seconds: 10)),
      );
      if (resp.statusCode == 200) return true;

      // Log response for debugging (helps distinguish CORS/network error vs 401)
      debugPrint(
        'Yalidine validate: status=${resp.statusCode} body=${resp.body}',
      );

      // Fallback: some users swapped the fields, try the inverse.
      final swapHeaders = {
        'X-API-ID': apiSecret,
        'X-API-TOKEN': apiKey,
        'Accept': 'application/json',
      };
      final respSwap = await RateLimiter.instance.run(
        'yalidine.validate.swap',
        () => _httpClient
            .get(wilayasUri, headers: swapHeaders)
            .timeout(const Duration(seconds: 10)),
      );
      if (respSwap.statusCode == 200) return true;
      debugPrint(
        'Yalidine validate (swapped): status=${respSwap.statusCode} body=${respSwap.body}',
      );
      return false;
    } catch (e, st) {
      debugPrint('Yalidine validate exception: $e\n$st');
      return false;
    }
  }

  Future<Map<String, dynamic>> validateCredentialsDetailed({
    required String courierName,
    required String? apiKey,
    required String? apiSecret,
    String? senderId,
  }) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      return {'ok': false, 'message': 'Token manquant'};
    }
    final name =
        InputSanitizer.sanitizeText(courierName, maxLength: 80).toLowerCase();
    if (!name.contains('ecotrack') &&
        (apiSecret == null || apiSecret.trim().isEmpty)) {
      return {'ok': false, 'message': 'Secret manquant'};
    }
    try {
      if (name.contains('yalidine') || name.contains('ecotrack')) {
        final tokenLength = name.contains('ecotrack') ? 200 : 120;
        final edge = await _validateViaEdgeDetailed(
          courierName: courierName,
          apiKey: InputSanitizer.sanitizeText(apiKey, maxLength: tokenLength),
          apiSecret: apiSecret == null || apiSecret.trim().isEmpty
              ? ''
              : InputSanitizer.sanitizeText(apiSecret, maxLength: 120),
        );
        if (edge != null) return edge;
        if (name.contains('yalidine') && !kIsWeb) {
          final secret = apiSecret ?? '';
          final ok = await _validateYalidine(
            apiKey: InputSanitizer.sanitizeText(apiKey, maxLength: 120),
            apiSecret: InputSanitizer.sanitizeText(secret, maxLength: 120),
          ).timeout(const Duration(seconds: 8), onTimeout: () => false);
          return {'ok': ok, 'message': ok ? 'OK' : 'Token invalide'};
        }
        if (name.contains('ecotrack') && !kIsWeb) {
          final ok = await _validateEcotrack(
            token: InputSanitizer.sanitizeText(apiKey, maxLength: 200),
          ).timeout(const Duration(seconds: 8), onTimeout: () => false);
          return {'ok': ok, 'message': ok ? 'OK' : 'Token invalide'};
        }
        return {'ok': false, 'message': 'Validation impossible'};
      }
      return {'ok': true, 'message': 'OK'};
    } catch (_) {
      return {'ok': false, 'message': 'Erreur validation'};
    }
  }

  Future<Map<String, dynamic>?> _validateViaEdgeDetailed({
    required String courierName,
    required String apiKey,
    required String apiSecret,
  }) async {
    try {
      final response = await RateLimiter.instance.run(
        'couriers.validate.edge',
        () => supabase.functions.invoke(
          'validate-courier',
          body: {
            'courierName': courierName,
            'apiKey': apiKey,
            'apiSecret': apiSecret,
          },
        ),
      );
      final data = response.data;
      if (data is Map) {
        final ok = data['ok'] == true;
        final message = data['message']?.toString() ?? '';
        debugPrint(
          'Courier validate edge: ${courierName.toLowerCase()} ok=$ok message="$message"',
        );
        return {'ok': ok, 'message': message};
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<Map<String, dynamic>> fetchYalidineParcels({
    required Map<String, dynamic> settings,
    String? tracking,
  }) async {
    final apiIdRaw = settings['api_key']?.toString();
    final tokenRaw = settings['api_secret']?.toString();
    final apiId = apiIdRaw == null
        ? null
        : InputSanitizer.sanitizeText(apiIdRaw, maxLength: 120);
    final token = tokenRaw == null
        ? null
        : InputSanitizer.sanitizeText(tokenRaw, maxLength: 120);
    if (apiId == null || token == null) {
      throw StateError('Clés Yalidine manquantes');
    }

    final safeTracking =
        InputSanitizer.sanitizeOptionalText(tracking, maxLength: 60);
    final uri = safeTracking == null
        ? Uri.parse('https://api.yalidine.app/v1/parcels/')
        : Uri.parse('https://api.yalidine.app/v1/parcels/$safeTracking');
    final resp = await RateLimiter.instance.run(
      'yalidine.parcels',
      () => _httpClient
          .get(
            uri,
            headers: {
              'X-API-ID': apiId,
              'X-API-TOKEN': token,
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12)),
    );
    if (resp.statusCode >= 400) {
      throw Exception('Yalidine ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body);
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  Future<List<Map<String, String>>> fetchCourierWilayas({
    required String courierId,
    Map<String, dynamic>? settings,
  }) async {
    final safeCourierId =
        InputSanitizer.sanitizeText(courierId, maxLength: 40).toLowerCase();
    final apiKey = settings?['api_key']?.toString() ?? '';
    final apiSecret = settings?['api_secret']?.toString() ?? '';
    if (safeCourierId.contains('yalidine')) {
      if (apiKey.isEmpty || apiSecret.isEmpty) {
        return _fetchDbWilayas();
      }
      return _fetchYalidineWilayas(
        apiKey: apiKey,
        apiSecret: apiSecret,
      );
    } else if (safeCourierId.contains('ecotrack')) {
      if (apiKey.isEmpty) {
        return _fetchDbWilayas();
      }
      return _fetchEcotrackWilayas(
        apiKey: apiKey,
      );
    }
    return _fetchDbWilayas();
  }

  Future<List<Map<String, String>>> fetchCourierCommunes({
    required String courierId,
    Map<String, dynamic>? settings,
    required String wilayaCode,
  }) async {
    final safeCourierId =
        InputSanitizer.sanitizeText(courierId, maxLength: 40).toLowerCase();
    final safeWilayaCode = InputSanitizer.sanitizeText(wilayaCode, maxLength: 8);
    final apiKey = settings?['api_key']?.toString() ?? '';
    final apiSecret = settings?['api_secret']?.toString() ?? '';
    if (safeCourierId.contains('yalidine')) {
      if (apiKey.isEmpty || apiSecret.isEmpty) {
        return _fetchDbCommunes(safeWilayaCode);
      }
      return _fetchYalidineCommunes(
        apiKey: apiKey,
        apiSecret: apiSecret,
        wilayaCode: safeWilayaCode,
      );
    } else if (safeCourierId.contains('ecotrack')) {
      if (apiKey.isEmpty) {
        return _fetchDbCommunes(safeWilayaCode);
      }
      return _fetchEcotrackCommunes(
        apiKey: apiKey,
        wilayaCode: safeWilayaCode,
      );
    }
    return _fetchDbCommunes(safeWilayaCode);
  }

  Future<Map<String, dynamic>> fetchEcotrackFees({
    required String token,
  }) async {
    return _fetchEcotrackFees(apiKey: token);
  }

  Future<List<Map<String, String>>> _fetchDbWilayas() async {
    try {
      final rows = await RateLimiter.instance.run(
        'wilayas.db',
        () => supabase
            .from(SupabaseTables.wilayas)
            .select('code, name_fr, name_ar')
            .order('code'),
      );
      return rows
          .map(
            (r) => {
              'id': r['code']?.toString() ?? '',
              'code': r['code']?.toString() ?? '',
              'name': (r['name_fr'] ?? r['name_ar'] ?? '').toString(),
            },
          )
          .where((m) => m['name']!.isNotEmpty)
          .toList();
    } catch (_) {}
    return const [];
  }

  Future<List<Map<String, String>>> _fetchDbCommunes(String wilayaCode) async {
    try {
      final rows = await RateLimiter.instance.run(
        'communes.db',
        () => supabase
            .from(SupabaseTables.communes)
            .select('name_fr, name_ar')
            .eq('wilaya_code', wilayaCode)
            .order('name_fr'),
      );
      return rows
          .map(
            (r) => {
              'id': '',
              'name': (r['name_fr'] ?? r['name_ar'] ?? '').toString(),
              'wilaya_id': wilayaCode,
              'has_stop_desk': '0',
              'stopdesk_id': '',
            },
          )
          .where((m) => m['name']!.isNotEmpty)
          .toList();
    } catch (_) {}
    return const [];
  }

  Future<List<Map<String, String>>> _fetchYalidineWilayas({
    required String apiKey,
    required String apiSecret,
  }) async {
    final uri = Uri.parse('https://api.yalidine.app/v1/wilayas/');
    try {
      final cacheKey = '${apiKey.trim()}|${apiSecret.trim()}';
      final cached = _yalidineWilayasCache[cacheKey];
      if (cached != null && !cached.isExpired) return cached.value;

      final resp = await RateLimiter.instance.run(
        'yalidine.wilayas',
        () => _httpClient
            .get(
              uri,
              headers: {
                'X-API-ID': apiKey.trim(),
                'X-API-TOKEN': apiSecret.trim(),
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 10)),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) return const [];
      final data = jsonDecode(resp.body);
      if (data is Map && data['data'] is List) {
        final list = (data['data'] as List)
            .whereType<Map>()
            .map(
              (m) => {
                'id': m['id']?.toString() ?? '',
                'code': m['wilaya_code']?.toString() ?? '',
                'name': m['wilaya_name']?.toString() ?? '',
              },
            )
            .where((m) => m['name']!.isNotEmpty)
            .toList();
        _yalidineWilayasCache[cacheKey] = _CacheItem(list, DateTime.now().add(_cacheTtl));
        return list;
      }
    } catch (_) {}
    return const [];
  }

  Future<List<Map<String, String>>> _fetchYalidineCommunes({
    required String apiKey,
    required String apiSecret,
    required String wilayaCode,
  }) async {
    final uri = Uri.parse(
      'https://api.yalidine.app/v1/communes?wilaya_id=${Uri.encodeQueryComponent(wilayaCode)}',
    );
    try {
      final cacheKey = '${apiKey.trim()}|${apiSecret.trim()}|$wilayaCode';
      final cached = _yalidineCommunesCache[cacheKey];
      if (cached != null && !cached.isExpired) return cached.value;

      final resp = await RateLimiter.instance.run(
        'yalidine.communes',
        () => _httpClient
            .get(
              uri,
              headers: {
                'X-API-ID': apiKey.trim(),
                'X-API-TOKEN': apiSecret.trim(),
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 10)),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) return const [];
      final data = jsonDecode(resp.body);
      if (data is Map && data['data'] is List) {
        final list = (data['data'] as List)
            .whereType<Map>()
            .map(
              (m) => {
                'id': m['id']?.toString() ?? '',
                'name': m['commune_name']?.toString() ?? '',
                'wilaya_id': m['wilaya_id']?.toString() ?? '',
                'has_stop_desk': m['has_stop_desk']?.toString() ?? '',
                'stopdesk_id': m['stopdesk_id']?.toString() ?? '',
              },
            )
            .where((m) => m['name']!.isNotEmpty)
            .toList();
        _yalidineCommunesCache[cacheKey] = _CacheItem(list, DateTime.now().add(_cacheTtl));
        return list;
      }
    } catch (_) {}
    return const [];
  }

  Future<bool> _validateEcotrack({required String token}) async {
    final uriWithParam = Uri.parse(
      'https://api.ecotrack.dz/api/v1/validate/token?api_token=${Uri.encodeQueryComponent(token.trim())}',
    );
    final uriNoParam = Uri.parse('https://api.ecotrack.dz/api/v1/validate/token');
    try {
      final resp = await RateLimiter.instance.run(
        'ecotrack.validate',
        () => _httpClient
            .get(
              uriWithParam,
              headers: {
                'Authorization': 'Bearer ${token.trim()}',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 8)),
      );
      final ok = _isEcotrackTokenValid(resp);
      if (ok != null) return ok;
      final retry = await RateLimiter.instance.run(
        'ecotrack.validate.retry',
        () => _httpClient
            .get(
              uriNoParam,
              headers: {
                'Authorization': 'Bearer ${token.trim()}',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 8)),
      );
      final retryOk = _isEcotrackTokenValid(retry);
      return retryOk ?? false;
    } catch (_) {
      return false;
    }
  }

  bool? _isEcotrackTokenValid(http.Response resp) {
    if (resp.statusCode == 401 || resp.statusCode == 403) return false;
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    var message = '';
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['message'] is String) {
        message = decoded['message'] as String;
      }
    } catch (_) {
      message = resp.body.trim();
    }
    if (message.isEmpty) {
      debugPrint('Ecotrack validate: success (empty message)');
      return true;
    }
    if (message == 'INVALID_TOKEN' || message == 'TOKEN_NOT_ALLOWED') {
      debugPrint('Ecotrack validate: $message');
      return false;
    }
    debugPrint('Ecotrack validate: success message="$message"');
    return true;
  }

  Future<List<Map<String, String>>> _fetchEcotrackWilayas({
    required String apiKey,
  }) async {
    try {
      final fees = await _fetchEcotrackFees(apiKey: apiKey);
      final livraison = fees['livraison'];
      if (livraison is! List) return const [];
      final idsRaw = livraison
          .whereType<Map>()
          .map((m) => m['wilaya_id']?.toString())
          .whereType<String>()
          .toSet();
      final ids = idsRaw
          .expand((id) => {id, id.padLeft(2, '0')})
          .toSet()
          .toList();
      if (ids.isEmpty) return const [];

      final rows = await RateLimiter.instance.run(
        'ecotrack.wilayas.db',
        () => supabase
            .from('wilayas')
            .select('code, name_fr')
            .inFilter('code', ids),
      );
      return rows
          .whereType<Map>()
          .map(
            (m) => {
              'code': m['code']?.toString() ?? '',
              'name': m['name_fr']?.toString() ?? '',
            },
          )
          .where((m) => m['code']!.isNotEmpty && m['name']!.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, String>>> _fetchEcotrackCommunes({
    required String apiKey,
    required String wilayaCode,
  }) async {
    final uri = Uri.parse(
      'https://api.ecotrack.dz/api/v1/get/communes?wilaya_id=${Uri.encodeQueryComponent(wilayaCode)}',
    );
    try {
      final resp = await RateLimiter.instance.run(
        'ecotrack.communes',
        () => _httpClient
            .get(
              uri,
              headers: {
                'Authorization': 'Bearer ${apiKey.trim()}',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 10)),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) return const [];
      final data = jsonDecode(resp.body);
      if (data is List) {
        return data
            .whereType<Map>()
            .map(
              (m) => {
                'name': m['commune']?.toString() ?? m['name']?.toString() ?? '',
                'wilaya_code': wilayaCode,
              },
            )
            .where((m) => m['name']!.isNotEmpty)
            .toList();
      }
      if (data is Map && data['data'] is List) {
        return (data['data'] as List)
            .whereType<Map>()
            .map(
              (m) => {
                'name': m['commune']?.toString() ?? m['name']?.toString() ?? '',
                'wilaya_code': wilayaCode,
              },
            )
            .where((m) => m['name']!.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<Map<String, dynamic>> _fetchEcotrackFees({
    required String apiKey,
  }) async {
    final cacheKey = apiKey.trim();
    final cached = _ecotrackFeesCache[cacheKey];
    if (cached != null && !cached.isExpired) return cached.value;
    final uri = Uri.parse('https://api.ecotrack.dz/api/v1/get/fees');
    final resp = await RateLimiter.instance.run(
      'ecotrack.fees',
      () => _httpClient
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer ${apiKey.trim()}',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12)),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Ecotrack fees ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body);
    if (data is Map<String, dynamic>) {
      _ecotrackFeesCache[cacheKey] =
          _CacheItem(data, DateTime.now().add(_cacheTtl));
      return data;
    }
    throw StateError('Ecotrack fees response invalid');
  }

  Future<Map<String, dynamic>> createEcotrackOrder({
    required Map<String, dynamic> settings,
    required Map<String, dynamic> order,
  }) async {
    final tokenRaw = settings['api_key']?.toString();
    final token = tokenRaw == null
        ? null
        : InputSanitizer.sanitizeText(tokenRaw, maxLength: 200);
    if (token == null || token.isEmpty) {
      throw StateError('Ecotrack token missing');
    }
    final params = order.map((key, value) => MapEntry(key, value.toString()));
    final uri = Uri.parse('https://api.ecotrack.dz/api/v1/create/order')
        .replace(queryParameters: params);
    final resp = await RateLimiter.instance.run(
      'ecotrack.order.create',
      () => _httpClient
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${token.trim()}',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15)),
    );
    if (resp.statusCode >= 400) {
      throw Exception('Ecotrack ${resp.statusCode}: ${resp.body}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw StateError('Ecotrack response invalid');
  }

  Future<String> _fetchEcotrackLabel({
    required String token,
    required String tracking,
  }) async {
    final uri = Uri.parse(
      'https://api.ecotrack.dz/api/v1/get/order/label?tracking=${Uri.encodeQueryComponent(tracking)}',
    );
    final resp = await RateLimiter.instance.run(
      'ecotrack.label',
      () => _httpClient
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer ${token.trim()}',
              'Accept': 'application/pdf,application/json',
            },
          )
          .timeout(const Duration(seconds: 15)),
    );
    if (resp.statusCode >= 400) {
      throw Exception('Ecotrack label ${resp.statusCode}: ${resp.body}');
    }
    final contentType = resp.headers['content-type'] ?? '';
    if (contentType.contains('application/pdf') ||
        (resp.bodyBytes.isNotEmpty && resp.bodyBytes.first == 0x25)) {
      final signedUrl = await StorageService().uploadBytesAndSign(
        data: resp.bodyBytes,
        fileName: 'ecotrack-$tracking.pdf',
        bucket: SupabaseOptions.labelBucket,
      );
      return signedUrl;
    }
    final bodyText = resp.body;
    if (bodyText.trim().startsWith('http')) {
      final bytes = await _loadLabelBytes(bodyText.trim());
      final signedUrl = await StorageService().uploadBytesAndSign(
        data: bytes,
        fileName: 'ecotrack-$tracking.pdf',
        bucket: SupabaseOptions.labelBucket,
      );
      return signedUrl;
    }
    try {
      final decoded = jsonDecode(bodyText);
      if (decoded is Map && decoded['label'] != null) {
        final bytes = await _loadLabelBytes(decoded['label'].toString());
        final signedUrl = await StorageService().uploadBytesAndSign(
          data: bytes,
          fileName: 'ecotrack-$tracking.pdf',
          bucket: SupabaseOptions.labelBucket,
        );
        return signedUrl;
      }
    } catch (_) {}
    throw StateError('Ecotrack label missing');
  }

  Future<Map<String, dynamic>> generateEcotrackOrderAndAttachLabel({
    required String orderId,
    required Map<String, dynamic> sellerCourierSettings,
    required Map<String, dynamic> selection,
  }) async {
    final tokenRaw = sellerCourierSettings['api_key']?.toString();
    if (tokenRaw == null || tokenRaw.trim().isEmpty) {
      throw StateError('Ecotrack token missing');
    }
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final orderPayload = <String, dynamic>{
      'reference': safeOrderId,
      'nom_client': '${selection['familyname']} ${selection['firstname']}'.trim(),
      'telephone': selection['phone_main'] ?? selection['phone'],
      'telephone_2': selection['phone_secondary'] ?? '',
      'adresse': selection['address'],
      'code_postal': selection['zip'] ?? '',
      'commune': selection['receiverCommune'],
      'code_wilaya': selection['wilayaCode'],
      'montant': selection['price'],
      'remarque': selection['remark'] ?? '',
      'produit': selection['productList'],
      'boutique': selection['shopName'] ?? '',
      'type': selection['hasExchange'] == true ? 2 : 1,
      'stop_desk': selection['deliveryType'] == 'stopdesk' ? 1 : 0,
      'weight': selection['weight'],
    };

    final created = await createEcotrackOrder(
      settings: sellerCourierSettings,
      order: orderPayload,
    );
    final results = created['results'];
    String? tracking;
    if (results is Map && results[safeOrderId] is Map) {
      tracking = results[safeOrderId]['tracking']?.toString();
      final success = results[safeOrderId]['success'];
      if (success == false) {
        final msg = results[safeOrderId]['message']?.toString() ??
            'Ecotrack error';
        throw Exception(msg);
      }
    }
    tracking ??= created['tracking']?.toString();
    if (tracking == null || tracking.isEmpty) {
      throw StateError('Ecotrack tracking missing');
    }
    final labelUrl = await _fetchEcotrackLabel(
      token: tokenRaw,
      tracking: tracking,
    );

    await RateLimiter.instance.run(
      'shipments.upsert.ecotrack',
      () => supabase.from(SupabaseTables.shipments).upsert({
        'order_id': safeOrderId,
        'tracking_number': tracking,
        'label_url': labelUrl,
        'status': 'shipped',
        'carrier': 'Ecotrack',
        'option': null,
        'delivery_mode': selection['deliveryType'],
        'shipping_cost': selection['estimatedFee'],
        'events': [
          {
            'title': 'Label generated',
            'description': 'Ready for carrier pickup',
            'at': DateTime.now().toIso8601String(),
          },
        ],
      }),
    );

    await RateLimiter.instance.run(
      'orders.update.label.ecotrack',
      () => supabase.from(SupabaseTables.orders).update({
        'tracking_number': tracking,
        'label_url': labelUrl,
      }).eq('id', safeOrderId),
    );

    await MessageService().sendMessage(
      roomId: 'order:$safeOrderId',
      content: 'Bordereau disponible',
      type: MessageType.label,
      payload: {
        'label_url': labelUrl,
        'tracking_number': tracking,
        'carrier': 'Ecotrack',
      },
    );

    return {
      'tracking': tracking,
      'label_url': labelUrl,
    };
  }

  /// Stream shipments for a seller identified by [sellerId].
  ///
  /// This streams the `orders` table including the related `product` record
  /// and maps results to a list of shipment-like maps expected by the
  /// `ShipmentsDashboardPage` UI.
  Stream<List<Map<String, dynamic>>> streamSellerShipments(String sellerId) {
    final safeSellerId = InputSanitizer.sanitizeId(sellerId, maxLength: 64);
    final shipmentsStream = RateLimiter.instance.stream(
      'shipments.seller.stream',
      () => supabase
          .from(SupabaseTables.shipments)
          .stream(primaryKey: ['order_id']),
    );

    return shipmentsStream.asyncMap((rows) async {
      if (rows.isEmpty) return <Map<String, dynamic>>[];

      final orderIds = rows
          .map((r) => r['order_id']?.toString())
          .where((e) => e != null)
          .cast<String>()
          .toList();

      final ordersResponse = orderIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await RateLimiter.instance.run(
                'orders.shipments.select',
                () => supabase
                    .from(SupabaseTables.orders)
                    .select(
                      'id, seller_id, courier_name, courier_id, shipping_cost, created_at',
                    )
                    .filter('id', 'in', orderIds),
              );
      final ordersById = <String, Map<String, dynamic>>{};
      for (final o in ordersResponse) {
        final map = Map<String, dynamic>.from(o as Map);
        final id = map['id']?.toString();
        if (id != null) ordersById[id] = map;
      }

      final result = <Map<String, dynamic>>[];
      for (final r in rows) {
        final orderId = r['order_id']?.toString();
        if (orderId == null) continue;
        final order = ordersById[orderId];
        if (order == null) continue;
        if ((order['seller_id']?.toString() ?? '') != safeSellerId) continue;

        final createdAt =
            r['created_at'] as String? ?? order['created_at'] as String?;
        result.add({
          'order_id': orderId,
          'status': r['status'] as String? ?? 'pending',
          'carrier':
              r['carrier'] as String? ??
              r['courier_name'] as String? ??
              order['courier_name'] as String? ??
              '-',
          'tracking_number': r['tracking_number'] as String?,
          'shipping_cost': r['shipping_cost'] ?? order['shipping_cost'],
          'label_url': r['label_url'] as String?,
          'created_at': createdAt,
        });
      }

      result.sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at'] ?? '');
        final bDate = DateTime.tryParse(b['created_at'] ?? '');
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      return result;
    });
  }

  /// Update the shipment status for [orderId] and notify involved parties.
  Future<void> updateShipmentStatus({
    required String orderId,
    required String status,
  }) async {
    await appendDeliveryStatus(orderId, status);
  }

  /// Load seller delivery settings for a given courier id.
  /// If [ownerId] is provided it will query that seller, otherwise it
  /// returns the first matching settings row (may be the current user).
  Future<Map<String, dynamic>?> loadSellerDeliverySettings(
    String courierId, {
    String? ownerId,
    String? courierName,
  }) async {
    final safeCourierId = InputSanitizer.sanitizeText(courierId, maxLength: 40);
    final safeCourierIdLower = safeCourierId.toLowerCase();
    final courierIdVariants = <String>{
      safeCourierId,
      safeCourierIdLower,
      safeCourierId.toUpperCase(),
    }.toList();
    final safeOwnerId =
        ownerId == null ? null : InputSanitizer.sanitizeId(ownerId, maxLength: 64);
    final current = supabase.auth.currentUser?.id;
    if (safeOwnerId != null && safeOwnerId != current) {
      return null;
    }

    // Direct select: only for the authenticated owner.
    var query = supabase
        .from('seller_delivery_settings')
        .select('api_key, api_secret, sender_id, extra');
    query = query.inFilter('courier_id', courierIdVariants);
    if (safeOwnerId != null) query = query.eq('owner_id', safeOwnerId);
    if (safeOwnerId == null && current != null) query = query.eq('owner_id', current);

    final row = await RateLimiter.instance.run(
      'seller_settings.select',
      () => query.maybeSingle(),
    );
    final normalized = _normalizeCourierSettings(row);
    return normalized;
  }

  Map<String, dynamic>? _normalizeCourierSettings(Object? row) {
    if (row == null) return null;
    final map = Map<String, dynamic>.from(row as Map);
    final apiKey = map['api_key'] ?? map['api_id'];
    final apiSecret = map['api_secret'] ?? map['api_token'];
    if (apiKey == null) return null;
    final extra = map['extra'] is Map ? Map<String, dynamic>.from(map['extra'] as Map) : null;
    final baseUrl = map['base_url'] ?? extra?['base_url'];
    return {
      'api_key': apiKey,
      'api_secret': apiSecret,
      'base_url': baseUrl,
      'sender_id': map['sender_id'],
      'extra': map['extra'],
    };
  }

  /// Load settings for the current user by courier name.
  Future<Map<String, dynamic>?> loadSellerDeliverySettingsByName(
    String courierName,
  ) async {
    final safeCourierName =
        InputSanitizer.sanitizeText(courierName, maxLength: 80);
    // Find courier ID from the couriers list
    final c = couriers.firstWhere(
      (e) =>
          (e['name'] ?? '').toString().toLowerCase() ==
          safeCourierName.toLowerCase(),
      orElse: () => {},
    );
    final courierId = c['id'];
    if (courierId == null || courierId.isEmpty) return null;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    return await loadSellerDeliverySettings(
      courierId,
      ownerId: userId,
      courierName: safeCourierName,
    );
  }

  /// Save or update current user's settings for a courier name.
  Future<void> saveSellerDeliverySettingsByName({
    required String courierName,
    required String apiKey,
    required String apiSecret,
    String? senderId,
  }) async {
    final safeCourierName =
        InputSanitizer.sanitizeText(courierName, maxLength: 80);
    final isEcotrack = safeCourierName.toLowerCase().contains('ecotrack');
    final safeApiKey = InputSanitizer.sanitizeText(
      apiKey,
      maxLength: isEcotrack ? 200 : 120,
    );
    final safeApiSecret = isEcotrack || apiSecret.trim().isEmpty
        ? ''
        : InputSanitizer.sanitizeText(apiSecret, maxLength: 120);
    final safeSenderId =
        InputSanitizer.sanitizeOptionalText(senderId, maxLength: 80);
    // Find the courier by name to get its ID
    final c = couriers.firstWhere(
      (e) =>
          (e['name'] ?? '').toString().toLowerCase() ==
          safeCourierName.toLowerCase(),
      orElse: () => {},
    );
    final courierId = c['id'];
    if (courierId == null || courierId.isEmpty) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');

    // Save directly with the courier ID string from the couriers list
    await RateLimiter.instance.run(
      'seller_settings.upsert',
      () => supabase.from('seller_delivery_settings').upsert({
        'owner_id': userId,
        'courier_id': courierId,
        'api_key': safeApiKey.isEmpty ? null : safeApiKey,
        'api_secret': safeApiSecret.isEmpty ? null : safeApiSecret,
        'sender_id': safeSenderId,
        'extra': isEcotrack ? {'base_url': 'https://api.ecotrack.dz'} : null,
      }, onConflict: 'owner_id,courier_id'),
    );
  }

  Future<void> deleteSellerDeliverySettingsByName(String courierName) async {
    final safeCourierName =
        InputSanitizer.sanitizeText(courierName, maxLength: 80);
    final c = couriers.firstWhere(
      (e) =>
          (e['name'] ?? '').toString().toLowerCase() ==
          safeCourierName.toLowerCase(),
      orElse: () => {},
    );
    final courierId = c['id'];
    if (courierId == null || courierId.isEmpty) return;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');
    await RateLimiter.instance.run(
      'seller_settings.delete',
      () => supabase
          .from('seller_delivery_settings')
          .delete()
          .eq('owner_id', userId)
          .eq('courier_id', courierId),
    );
  }

  Map<String, dynamic> _sanitizeEvent(Map<String, dynamic> event) {
    final sanitized = <String, dynamic>{};
    event.forEach((key, value) {
      if (value is String) {
        sanitized[key] = InputSanitizer.sanitizeText(value, maxLength: 200);
        return;
      }
      sanitized[key] = value;
    });
    return sanitized;
  }
}






