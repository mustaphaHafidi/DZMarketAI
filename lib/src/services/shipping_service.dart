import 'dart:convert';
import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/parcel_import_model.dart';
import 'package:dzmarket/src/models/shipment.dart';
import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/label_service.dart';
import 'package:dzmarket/src/services/notification_service.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/services/storage_service.dart';
import 'package:dzmarket/src/services/phone_formatter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Simple generic cache item with expiry.
class _CacheItem<T> {
  final T value;
  final DateTime expiry;
  _CacheItem(this.value, this.expiry);
  bool get isExpired => DateTime.now().isAfter(expiry);
}

class CourierCapabilities {
  final bool supportsStopdesk;
  final bool supportsInsurance;
  final bool supportsExchange;
  final bool supportsDeclaredValue;
  final bool supportsDimensions;
  final bool supportsWeight;

  const CourierCapabilities({
    required this.supportsStopdesk,
    required this.supportsInsurance,
    required this.supportsExchange,
    required this.supportsDeclaredValue,
    required this.supportsDimensions,
    required this.supportsWeight,
  });

  static const all = CourierCapabilities(
    supportsStopdesk: true,
    supportsInsurance: true,
    supportsExchange: true,
    supportsDeclaredValue: true,
    supportsDimensions: true,
    supportsWeight: true,
  );

  static const none = CourierCapabilities(
    supportsStopdesk: false,
    supportsInsurance: false,
    supportsExchange: false,
    supportsDeclaredValue: false,
    supportsDimensions: false,
    supportsWeight: false,
  );

  CourierCapabilities mergeAny(CourierCapabilities other) {
    return CourierCapabilities(
      supportsStopdesk: supportsStopdesk || other.supportsStopdesk,
      supportsInsurance: supportsInsurance || other.supportsInsurance,
      supportsExchange: supportsExchange || other.supportsExchange,
      supportsDeclaredValue:
          supportsDeclaredValue || other.supportsDeclaredValue,
      supportsDimensions: supportsDimensions || other.supportsDimensions,
      supportsWeight: supportsWeight || other.supportsWeight,
    );
  }
}

class CourierParcelRules {
  final int minWeightKg;
  final int maxWeightKg;
  final int maxHeightCm;
  final int maxWidthCm;
  final int maxLengthCm;
  final int maxVolumeCm3;
  final double maxDeclaredValue;
  final int overweightThresholdKg;

  const CourierParcelRules({
    required this.minWeightKg,
    required this.maxWeightKg,
    required this.maxHeightCm,
    required this.maxWidthCm,
    required this.maxLengthCm,
    required this.maxVolumeCm3,
    required this.maxDeclaredValue,
    required this.overweightThresholdKg,
  });

  static const generic = CourierParcelRules(
    minWeightKg: 1,
    maxWeightKg: 60,
    maxHeightCm: 200,
    maxWidthCm: 200,
    maxLengthCm: 200,
    maxVolumeCm3: 8000000,
    maxDeclaredValue: 99999999,
    overweightThresholdKg: 5,
  );

  CourierParcelRules mergeStrict(CourierParcelRules other) {
    return CourierParcelRules(
      minWeightKg: minWeightKg > other.minWeightKg
          ? minWeightKg
          : other.minWeightKg,
      maxWeightKg: maxWeightKg < other.maxWeightKg
          ? maxWeightKg
          : other.maxWeightKg,
      maxHeightCm: maxHeightCm < other.maxHeightCm
          ? maxHeightCm
          : other.maxHeightCm,
      maxWidthCm: maxWidthCm < other.maxWidthCm ? maxWidthCm : other.maxWidthCm,
      maxLengthCm: maxLengthCm < other.maxLengthCm
          ? maxLengthCm
          : other.maxLengthCm,
      maxVolumeCm3: maxVolumeCm3 < other.maxVolumeCm3
          ? maxVolumeCm3
          : other.maxVolumeCm3,
      maxDeclaredValue: maxDeclaredValue < other.maxDeclaredValue
          ? maxDeclaredValue
          : other.maxDeclaredValue,
      overweightThresholdKg: overweightThresholdKg < other.overweightThresholdKg
          ? overweightThresholdKg
          : other.overweightThresholdKg,
    );
  }
}

class CourierParcelValidation {
  final String code;
  final Map<String, String> params;

  const CourierParcelValidation(this.code, {this.params = const {}});
}

class ShippingFeeQuote {
  final double fee;
  final String source;
  final bool freeShipping;

  const ShippingFeeQuote({
    required this.fee,
    required this.source,
    required this.freeShipping,
  });
}

class ShippingService {
  // Shared HTTP client to reuse connections across instances.
  static final http.Client _httpClient = http.Client();

  // Simple in-memory cache for courier responses to avoid repeated network calls.
  static const Duration _cacheTtl = Duration(minutes: 30);
  static final Map<String, _CacheItem<List<Map<String, String>>>>
  _courierWilayasCache = {};
  static final Map<String, _CacheItem<List<Map<String, String>>>>
  _courierCommunesCache = {};
  static final Map<String, _CacheItem<Map<String, dynamic>>>
  _ecotrackFeesCache = {};
  static final Map<String, _CacheItem<CourierParcelRules>> _parcelRulesCache =
      {};
  static const options = <String>[
    'Livraison domicile (24-72h)',
    'Point relais / bureau poste',
    'Coursier local (même ville)',
  ];
  static const _optionKeyMap = <String, String>{
    'Livraison domicile (24-72h)': 'shipping.option.home',
    'Point relais / bureau poste': 'shipping.option.pickup',
    'Coursier local (même ville)': 'shipping.option.local',
    'shipping.option.home': 'shipping.option.home',
    'shipping.option.pickup': 'shipping.option.pickup',
    'shipping.option.local': 'shipping.option.local',
  };

  static String _courierWilayaCacheKey(String courierId, String? sellerId) {
    return '$courierId|${sellerId ?? ''}';
  }

  static String _courierCommuneCacheKey(
    String courierId,
    String? sellerId,
    String wilayaCode,
  ) {
    return '$courierId|${sellerId ?? ''}|$wilayaCode';
  }

  static const couriers = <Map<String, String>>[
    {
      'id': 'yalidine',
      'name': 'Yalidine Express',
      'contact': 'contact@yalidine.com',
      'coverage': 'National',
    },
    {
      'id': 'ecotrack',
      'name': 'Ecotrack',
      'contact': 'contact@ecotrack.dz',
      'coverage': 'Local/National',
    },
    {
      'id': 'zrexpress',
      'name': 'ZR Express',
      'contact': 'support@zrexpress.app',
      'coverage': 'National',
    },
    {
      'id': 'guepex',
      'name': 'Guepex',
      'contact': 'developer@guepex.com',
      'coverage': 'National',
    },
  ];

  Future<ShippingFeeQuote?> estimateCheckoutShippingFee({
    required String sellerId,
    required String courierId,
    String? courierName,
    String? productId,
    required String deliveryType,
    String? senderWilayaId,
    String? senderWilayaName,
    String? receiverWilayaId,
    String? receiverWilayaName,
    String? receiverCommuneId,
    String? receiverCommuneName,
    required double price,
    required int weightKg,
    required int heightCm,
    required int widthCm,
    required int lengthCm,
    double? declaredValue,
  }) async {
    final safeSellerId = InputSanitizer.sanitizeId(sellerId, maxLength: 64);
    final safeCourierId = InputSanitizer.sanitizeOptionalText(
      courierId,
      maxLength: 64,
    );
    if (safeSellerId.isEmpty ||
        safeCourierId == null ||
        safeCourierId.isEmpty) {
      return null;
    }

    final safeCourierName = InputSanitizer.sanitizeOptionalText(
      courierName,
      maxLength: 80,
    );
    final safeProductId = InputSanitizer.sanitizeOptionalText(
      productId,
      maxLength: 64,
    );
    final safeDelivery = InputSanitizer.sanitizeText(
      deliveryType,
      maxLength: 40,
    );
    final safeSenderWilayaId = InputSanitizer.sanitizeOptionalText(
      senderWilayaId,
      maxLength: 20,
    );
    final safeSenderWilayaName = InputSanitizer.sanitizeOptionalText(
      senderWilayaName,
      maxLength: 80,
    );
    final safeReceiverWilayaId = InputSanitizer.sanitizeOptionalText(
      receiverWilayaId,
      maxLength: 20,
    );
    final safeReceiverWilayaName = InputSanitizer.sanitizeOptionalText(
      receiverWilayaName,
      maxLength: 80,
    );
    final safeReceiverCommuneId = InputSanitizer.sanitizeOptionalText(
      receiverCommuneId,
      maxLength: 20,
    );
    final safeReceiverCommuneName = InputSanitizer.sanitizeOptionalText(
      receiverCommuneName,
      maxLength: 80,
    );

    final response = await RateLimiter.instance.run(
      'shipping.quote.invoke',
      () => supabase.functions.invoke(
        'estimate-shipping',
        body: {
          'seller_id': safeSellerId,
          'courier_id': safeCourierId,
          if (safeCourierName != null) 'courier_name': safeCourierName,
          if (safeProductId != null) 'product_id': safeProductId,
          'delivery_type': safeDelivery,
          if (safeSenderWilayaId != null)
            'sender_wilaya_id': safeSenderWilayaId,
          if (safeSenderWilayaName != null)
            'sender_wilaya_name': safeSenderWilayaName,
          if (safeReceiverWilayaId != null)
            'receiver_wilaya_id': safeReceiverWilayaId,
          if (safeReceiverWilayaName != null)
            'receiver_wilaya_name': safeReceiverWilayaName,
          if (safeReceiverCommuneId != null)
            'receiver_commune_id': safeReceiverCommuneId,
          if (safeReceiverCommuneName != null)
            'receiver_commune_name': safeReceiverCommuneName,
          'price': price,
          'declared_value': declaredValue ?? price,
          'weight_kg': weightKg,
          'height_cm': heightCm,
          'width_cm': widthCm,
          'length_cm': lengthCm,
        },
      ),
    );
    final data = response.data;
    if (data is! Map) return null;
    if (data['ok'] != true) return null;
    final fee =
        (data['fee'] as num?)?.toDouble() ?? double.tryParse('${data['fee']}');
    if (fee == null || !fee.isFinite || fee < 0) return null;
    final source = (data['source']?.toString() ?? '').trim();
    final freeShipping = data['free_shipping'] == true;
    return ShippingFeeQuote(
      fee: fee,
      source: source.isEmpty ? 'unknown' : source,
      freeShipping: freeShipping,
    );
  }

  Future<List<Map<String, String>>> fetchCouriers() async => couriers;

  static String? _courierNameFromId(String? courierId) {
    if (courierId == null || courierId.isEmpty) return null;
    final normalized = courierId.toLowerCase();
    final match = couriers.firstWhere(
      (c) => (c['id'] ?? '').toLowerCase() == normalized,
      orElse: () => const <String, String>{},
    );
    return match['name'];
  }

  static Map<String, String> deliveryMode(String option) {
    final key = _optionKeyMap[option] ?? option;
    if (key == 'shipping.option.local') return {'mode': 'local_driver'};
    if (key == 'shipping.option.pickup') {
      return {'mode': 'pickup_postal'};
    }
    return {'mode': 'home'};
  }

  static String _normalizeCourierKey(String? value) {
    if (value == null) return '';
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String? _canonicalCourierCode({
    String? courierId,
    String? courierName,
  }) {
    final merged = _normalizeCourierKey(
      '${courierId ?? ''} ${courierName ?? ''}',
    );
    if (merged.contains('yalidine')) return 'yalidine';
    if (merged.contains('ecotrack')) return 'ecotrack';
    if (merged.contains('zrexpress')) return 'zrexpress';
    if (merged.contains('guepex')) return 'guepex';
    final idKey = _normalizeCourierKey(courierId);
    if (idKey.isNotEmpty) return idKey;
    return null;
  }

  static CourierParcelRules _parcelRulesFromDbRow(
    Map<String, dynamic> row, {
    required CourierParcelRules fallback,
  }) {
    int parseIntField(String key, int fallbackValue) {
      final value = row[key];
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse('$value') ?? fallbackValue;
    }

    double parseDoubleField(String key, double fallbackValue) {
      final value = row[key];
      if (value is double) return value;
      if (value is num) return value.toDouble();
      return double.tryParse('$value') ?? fallbackValue;
    }

    return CourierParcelRules(
      minWeightKg: parseIntField('min_weight_kg', fallback.minWeightKg),
      maxWeightKg: parseIntField('max_weight_kg', fallback.maxWeightKg),
      maxHeightCm: parseIntField('max_height_cm', fallback.maxHeightCm),
      maxWidthCm: parseIntField('max_width_cm', fallback.maxWidthCm),
      maxLengthCm: parseIntField('max_length_cm', fallback.maxLengthCm),
      maxVolumeCm3: parseIntField('max_volume_cm3', fallback.maxVolumeCm3),
      maxDeclaredValue: parseDoubleField(
        'max_declared_value',
        fallback.maxDeclaredValue,
      ),
      overweightThresholdKg: parseIntField(
        'overweight_threshold_kg',
        fallback.overweightThresholdKg,
      ),
    );
  }

  static Future<CourierParcelRules?> _fetchParcelRulesFromDb({
    required String courierCode,
    required CourierParcelRules fallback,
  }) async {
    final cached = _parcelRulesCache[courierCode];
    if (cached != null && !cached.isExpired) return cached.value;
    try {
      final row = await RateLimiter.instance.run(
        'shipments.parcel_rules.$courierCode',
        () => supabase
            .from('courier_parcel_rules')
            .select(
              'courier_code,min_weight_kg,max_weight_kg,max_height_cm,'
              'max_width_cm,max_length_cm,max_volume_cm3,max_declared_value,'
              'overweight_threshold_kg',
            )
            .eq('courier_code', courierCode)
            .maybeSingle(),
      );
      if (row is Map) {
        final parsed = _parcelRulesFromDbRow(
          Map<String, dynamic>.from(row as Map),
          fallback: fallback,
        );
        _parcelRulesCache[courierCode] = _CacheItem(
          parsed,
          DateTime.now().add(_cacheTtl),
        );
        return parsed;
      }
    } catch (_) {
      // Keep static fallback when table/RLS is not available.
    }
    return null;
  }

  static bool isZrExpressCourier({String? courierId, String? courierName}) {
    final idKey = _normalizeCourierKey(courierId);
    final nameKey = _normalizeCourierKey(courierName);
    return idKey.contains('zrexpress') || nameKey.contains('zrexpress');
  }

  static bool isGuepexCourier({String? courierId, String? courierName}) {
    final idKey = _normalizeCourierKey(courierId);
    final nameKey = _normalizeCourierKey(courierName);
    return idKey.contains('guepex') || nameKey.contains('guepex');
  }

  static CourierCapabilities capabilitiesFor({
    String? courierId,
    String? courierName,
  }) {
    final key = _normalizeCourierKey('${courierId ?? ''} ${courierName ?? ''}');
    if (key.contains('yalidine')) {
      return const CourierCapabilities(
        supportsStopdesk: true,
        supportsInsurance: true,
        supportsExchange: true,
        supportsDeclaredValue: true,
        supportsDimensions: true,
        supportsWeight: true,
      );
    }
    if (key.contains('ecotrack')) {
      return const CourierCapabilities(
        supportsStopdesk: true,
        supportsInsurance: false,
        supportsExchange: true,
        supportsDeclaredValue: false,
        supportsDimensions: true,
        supportsWeight: true,
      );
    }
    if (key.contains('zrexpress')) {
      return const CourierCapabilities(
        supportsStopdesk: true,
        supportsInsurance: false,
        supportsExchange: false,
        supportsDeclaredValue: false,
        supportsDimensions: true,
        supportsWeight: true,
      );
    }
    if (key.contains('guepex')) {
      return const CourierCapabilities(
        supportsStopdesk: true,
        supportsInsurance: true,
        supportsExchange: true,
        supportsDeclaredValue: true,
        supportsDimensions: true,
        supportsWeight: true,
      );
    }
    return CourierCapabilities.all;
  }

  static CourierCapabilities aggregateCapabilities(
    List<Map<String, dynamic>> couriers,
  ) {
    if (couriers.isEmpty) return CourierCapabilities.all;
    var caps = CourierCapabilities.none;
    for (final courier in couriers) {
      caps = caps.mergeAny(
        capabilitiesFor(
          courierId: courier['courier_id']?.toString(),
          courierName: courier['courier_name']?.toString(),
        ),
      );
    }
    return caps;
  }

  static CourierParcelRules parcelRulesFor({
    String? courierId,
    String? courierName,
  }) {
    final key = _normalizeCourierKey('${courierId ?? ''} ${courierName ?? ''}');
    if (key.contains('yalidine')) {
      return const CourierParcelRules(
        minWeightKg: 1,
        maxWeightKg: 60,
        maxHeightCm: 200,
        maxWidthCm: 200,
        maxLengthCm: 200,
        maxVolumeCm3: 8000000,
        maxDeclaredValue: 99999999,
        overweightThresholdKg: 5,
      );
    }
    if (key.contains('ecotrack')) {
      return const CourierParcelRules(
        minWeightKg: 1,
        maxWeightKg: 60,
        maxHeightCm: 200,
        maxWidthCm: 200,
        maxLengthCm: 200,
        maxVolumeCm3: 8000000,
        maxDeclaredValue: 99999999,
        overweightThresholdKg: 5,
      );
    }
    if (key.contains('zrexpress')) {
      return const CourierParcelRules(
        minWeightKg: 1,
        maxWeightKg: 60,
        maxHeightCm: 200,
        maxWidthCm: 200,
        maxLengthCm: 200,
        maxVolumeCm3: 8000000,
        maxDeclaredValue: 99999999,
        overweightThresholdKg: 5,
      );
    }
    if (key.contains('guepex')) {
      return const CourierParcelRules(
        minWeightKg: 1,
        maxWeightKg: 60,
        maxHeightCm: 200,
        maxWidthCm: 200,
        maxLengthCm: 200,
        maxVolumeCm3: 8000000,
        maxDeclaredValue: 150000,
        overweightThresholdKg: 5,
      );
    }
    return CourierParcelRules.generic;
  }

  static CourierParcelRules aggregateParcelRules(
    List<Map<String, dynamic>> couriers,
  ) {
    if (couriers.isEmpty) return CourierParcelRules.generic;
    var rules = CourierParcelRules.generic;
    for (final courier in couriers) {
      rules = rules.mergeStrict(
        parcelRulesFor(
          courierId: courier['courier_id']?.toString(),
          courierName: courier['courier_name']?.toString(),
        ),
      );
    }
    return rules;
  }

  static Future<CourierParcelRules> parcelRulesForAsync({
    String? courierId,
    String? courierName,
  }) async {
    final fallback = parcelRulesFor(
      courierId: courierId,
      courierName: courierName,
    );
    final courierCode = _canonicalCourierCode(
      courierId: courierId,
      courierName: courierName,
    );
    if (courierCode == null || courierCode.isEmpty) return fallback;
    final remote = await _fetchParcelRulesFromDb(
      courierCode: courierCode,
      fallback: fallback,
    );
    return remote ?? fallback;
  }

  static Future<CourierParcelRules> aggregateParcelRulesAsync(
    List<Map<String, dynamic>> couriers,
  ) async {
    if (couriers.isEmpty) return CourierParcelRules.generic;
    final futures = couriers.map((courier) {
      return parcelRulesForAsync(
        courierId: courier['courier_id']?.toString(),
        courierName: courier['courier_name']?.toString(),
      );
    });
    final resolved = await Future.wait(futures);
    var rules = CourierParcelRules.generic;
    for (final item in resolved) {
      rules = rules.mergeStrict(item);
    }
    return rules;
  }

  static CourierParcelValidation? validateParcel({
    required CourierParcelRules rules,
    required int? weightKg,
    required int? heightCm,
    required int? widthCm,
    required int? lengthCm,
    required double? declaredValue,
    required bool insuranceActive,
  }) {
    if (weightKg == null ||
        weightKg < rules.minWeightKg ||
        weightKg > rules.maxWeightKg) {
      return CourierParcelValidation(
        'weight_range',
        params: {
          'min': rules.minWeightKg.toString(),
          'max': rules.maxWeightKg.toString(),
        },
      );
    }
    if (heightCm == null || heightCm < 0 || heightCm > rules.maxHeightCm) {
      return CourierParcelValidation(
        'height_max',
        params: {'max': rules.maxHeightCm.toString()},
      );
    }
    if (widthCm == null || widthCm < 0 || widthCm > rules.maxWidthCm) {
      return CourierParcelValidation(
        'width_max',
        params: {'max': rules.maxWidthCm.toString()},
      );
    }
    if (lengthCm == null || lengthCm < 0 || lengthCm > rules.maxLengthCm) {
      return CourierParcelValidation(
        'length_max',
        params: {'max': rules.maxLengthCm.toString()},
      );
    }
    final volumeCm3 = heightCm * widthCm * lengthCm;
    if (volumeCm3 > rules.maxVolumeCm3) {
      return CourierParcelValidation(
        'volume_max',
        params: {'max': rules.maxVolumeCm3.toString()},
      );
    }
    if (insuranceActive &&
        declaredValue != null &&
        declaredValue > rules.maxDeclaredValue) {
      return CourierParcelValidation(
        'declared_value_max',
        params: {'max': rules.maxDeclaredValue.toStringAsFixed(0)},
      );
    }
    return null;
  }

  static String optionLabel(BuildContext context, String option) {
    final key = _optionKeyMap[option];
    if (key == null) return option;
    return L10n.tr(context, key, fallback: option);
  }

  String _localeCode() {
    return LocaleService.instance.locale.value?.languageCode ?? 'fr';
  }

  String _statusLabel(String locale, String status) {
    switch (status) {
      case 'pending':
        return L10n.trLocale(locale, 'orders.status_pending');
      case 'paid':
        return L10n.trLocale(locale, 'orders.status_paid');
      case 'shipped':
        return L10n.trLocale(locale, 'orders.status_shipped');
      case 'delivered':
        return L10n.trLocale(locale, 'orders.status_delivered');
      case 'cancelled':
        return L10n.trLocale(locale, 'orders.status_cancelled');
      default:
        return status;
    }
  }

  String _labelEventTitle(String locale) {
    return L10n.trLocale(locale, 'shipments.event_label_generated_title');
  }

  String _labelEventDesc(String locale, String carrier) {
    return L10n.trLocale(
      locale,
      'shipments.event_label_generated_desc',
      params: {'carrier': carrier},
    );
  }

  Stream<Shipment?> streamShipment(String orderId) {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    return RateLimiter.instance.stream(
      'shipments.stream',
      () => supabase
          .from(SupabaseTables.shipments)
          .stream(primaryKey: ['order_id'])
          .eq('order_id', safeOrderId)
          .map(
            (rows) => rows.isNotEmpty ? Shipment.fromJson(rows.first) : null,
          ),
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
            .select(
              'courier_id, api_key, api_secret, sender_id, couriers(name)',
            )
            .eq('owner_id', safeSellerId)
            .not('api_key', 'is', null)
            .or('courier_id.eq.ecotrack,api_secret.not.is.null'),
      );
      return rows
          .map(
            (r) => {
              'courier_id': r['courier_id'],
              'courier_name':
                  (r['couriers'] as Map?)?['name'] ??
                  _courierNameFromId(r['courier_id']?.toString()) ??
                  r['courier_id']?.toString(),
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
    Map<String, dynamic>? selection,
  }) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeCourierId = InputSanitizer.sanitizeText(courierId, maxLength: 64);
    final safeCourierName = InputSanitizer.sanitizeText(
      courierName,
      maxLength: 80,
    );
    final safeOption = InputSanitizer.sanitizeOptionalText(
      option,
      maxLength: 60,
    );
    final safeDelivery = InputSanitizer.sanitizeOptionalText(
      deliveryMode,
      maxLength: 40,
    );
    await createShipment(
      orderId: safeOrderId,
      courierId: safeCourierId,
      courierName: safeCourierName,
      deliveryMode: safeDelivery,
      shippingOption: safeOption,
      shippingCost: shippingCost,
      selection: selection,
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
    final safeCourierName = InputSanitizer.sanitizeText(
      courierName,
      maxLength: 80,
    );
    final safeDelivery = InputSanitizer.sanitizeOptionalText(
      deliveryMode,
      maxLength: 40,
    );
    final safeOption = InputSanitizer.sanitizeOptionalText(
      shippingOption,
      maxLength: 60,
    );
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
      final rawMessage = data['message']?.toString() ?? 'Shipment failed';
      if (rawMessage == 'zr_phone_invalid') {
        final locale =
            LocaleService.instance.locale.value?.languageCode ?? 'fr';
        throw StateError(L10n.trLocale(locale, 'checkout.error_zr_phone'));
      }
      throw StateError(rawMessage);
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      try {
        final tracking = map['tracking_number']?.toString();
        final labelUrl = map['label_url']?.toString();
        final hasLabel = labelUrl != null && labelUrl.isNotEmpty;
        final statusValue = hasLabel ? 'shipped' : 'validated';
        final labelKey = hasLabel
            ? 'order.system.shipped'
            : 'order.system.validated';
        final eventKey = hasLabel
            ? 'order:$orderId:shipped'
            : 'order:$orderId:validated';
        final locale =
            LocaleService.instance.locale.value?.languageCode ?? 'fr';
        await _postOrderSystemMessage(
          orderId: orderId,
          text: L10n.trLocale(locale, labelKey),
          i18nKey: labelKey,
          status: statusValue,
          statusI18n: 'order.status.$statusValue',
          trackingNumber: tracking,
          labelUrl: labelUrl,
          courierName: courierName,
          dedupeKey: eventKey,
        );
      } catch (_) {
        // Best-effort: do not block shipment flow.
      }
      return map;
    }
    return {'ok': true};
  }

  Future<void> _postOrderSystemMessage({
    required String orderId,
    required String text,
    String? i18nKey,
    String? status,
    String? statusI18n,
    String? trackingNumber,
    String? labelUrl,
    String? courierName,
    String? dedupeKey,
  }) async {
    try {
      await ChatRepository().postOrderSystemMessage(
        orderId: orderId,
        text: text,
        payload: {
          if (i18nKey != null) 'i18n_key': i18nKey,
          if (status != null) 'status': status,
          if (statusI18n != null) 'status_i18n': statusI18n,
          if (trackingNumber != null) 'tracking_number': trackingNumber,
          if (labelUrl != null) 'label_url': labelUrl,
          if (courierName != null) 'courier_name': courierName,
        },
        dedupeKey: dedupeKey,
      );
    } catch (_) {
      // Best-effort: avoid blocking shipment flow.
    }
  }

  /// Génère une selection Yalidine/Ecotrack à partir de la commande + profil vendeur/acheteur + adresse.
  Future<Map<String, dynamic>> buildSelectionFromOrder(String orderId) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    // Charge order + buyer + seller + address + product (RLS: vendeur ou service)
    Map<String, dynamic>? orderRes;
    try {
      orderRes = await supabase
          .from(SupabaseTables.orders)
          .select(
            'product_id,buyer_id,seller_id,shipping_address_id,agreed_price,sale_price,shipping_selection',
          )
          .eq('id', safeOrderId)
          .maybeSingle();
    } on PostgrestException catch (e) {
      if (e.code == '42703' && e.message.contains('shipping_selection')) {
        orderRes = await supabase
            .from(SupabaseTables.orders)
            .select(
              'product_id,buyer_id,seller_id,shipping_address_id,agreed_price,sale_price',
            )
            .eq('id', safeOrderId)
            .maybeSingle();
      } else {
        rethrow;
      }
    }
    if (orderRes == null) {
      throw StateError('Commande introuvable');
    }
    final Map<String, dynamic> orderRow = Map<String, dynamic>.from(
      orderRes as Map,
    );
    final buyerId = orderRow['buyer_id']?.toString() ?? '';
    final sellerId = orderRow['seller_id']?.toString() ?? '';
    final productId = orderRow['product_id']?.toString();
    final addressId = orderRow['shipping_address_id']?.toString();
    final storedSelection = orderRow['shipping_selection'];
    final dynamic priceValue =
        orderRow['agreed_price'] ?? orderRow['sale_price'];
    double price = priceValue is num ? priceValue.toDouble() : 0.0;

    // Produit (for fallbacks / enrich stored selection)
    String productTitle = 'Produit $productId';
    bool freeShipping = false;
    bool exchangeAfterDelivery = false;
    bool insuranceActive = false;
    double? declaredValue;
    int? weightKg;
    int? heightCm;
    int? widthCm;
    int? lengthCm;
    if (productId != null) {
      final productRes = await supabase
          .from('products')
          .select(
            'title,price,shipping_free,exchange_after_delivery,insurance_active,declared_value,weight_kg,height_cm,width_cm,length_cm',
          )
          .eq('id', productId)
          .maybeSingle();
      final Map<String, dynamic>? product = productRes;
      if (product != null) {
        productTitle =
            InputSanitizer.sanitizeOptionalText(
              product['title'],
              maxLength: 120,
            ) ??
            productTitle;
        if (price <= 0 && product['price'] is num) {
          price = (product['price'] as num).toDouble();
        }
        freeShipping = product['shipping_free'] == true;
        exchangeAfterDelivery = product['exchange_after_delivery'] == true;
        insuranceActive = product['insurance_active'] == true;
        declaredValue =
            (product['declared_value'] as num?)?.toDouble() ?? declaredValue;
        weightKg = (product['weight_kg'] as num?)?.toInt() ?? weightKg;
        heightCm = (product['height_cm'] as num?)?.toInt() ?? heightCm;
        widthCm = (product['width_cm'] as num?)?.toInt() ?? widthCm;
        lengthCm = (product['length_cm'] as num?)?.toInt() ?? lengthCm;
      }
    }

    // If buyer selection is already stored, reuse it to avoid name mismatches.
    if (storedSelection is Map) {
      final selection = Map<String, dynamic>.from(storedSelection);
      selection['order_id'] = safeOrderId;
      selection['from_wilaya_name'] ??= selection['senderWilaya'];
      selection['to_wilaya_name'] ??= selection['receiverWilaya'];
      selection['to_commune_name'] ??= selection['receiverCommune'];
      selection['receiverDaira'] ??=
          selection['receiver_daira'] ?? selection['to_daira_name'];
      selection['receiver_daira'] ??= selection['receiverDaira'];
      selection['receiverWilaya'] ??= selection['to_wilaya_name'];
      selection['receiverCommune'] ??= selection['to_commune_name'];
      selection['receiverWilayaId'] ??=
          selection['receiver_wilaya_id'] ??
          selection['wilayaCode'] ??
          selection['wilaya_id'];
      selection['receiverCommuneId'] ??=
          selection['receiver_commune_id'] ?? selection['commune_id'];
      selection['phone_main'] ??= selection['phone'];
      selection['contact_phone'] ??= selection['phone_main'];
      final isZrSelection = isZrExpressCourier(
        courierId: selection['courierId']?.toString(),
        courierName: selection['courierName']?.toString(),
      );
      // Ensure E.164 phone is available for couriers that require it (ZR Express).
      if (selection['phone_e164'] == null) {
        final e164 = isZrSelection
            ? PhoneFormatter.normalizeDzE164ForZr(
                selection['phone_main'] ?? selection['phone'] ?? '',
              )
            : PhoneFormatter.normalizeDzE164(
                selection['phone_main'] ?? selection['phone'] ?? '',
              );
        if (e164.isNotEmpty) {
          selection['phone_e164'] = e164;
        }
      }
      if (selection['phone2_e164'] == null) {
        final e164Secondary = isZrSelection
            ? PhoneFormatter.normalizeDzE164ForZr(
                selection['phone2'] ?? selection['phone_secondary'] ?? '',
              )
            : PhoneFormatter.normalizeDzE164(
                selection['phone2'] ?? selection['phone_secondary'] ?? '',
              );
        if (e164Secondary.isNotEmpty) {
          selection['phone2_e164'] = e164Secondary;
        }
      }
      selection['productList'] ??= selection['product_list'] ?? productTitle;
      selection['freeshipping'] ??=
          selection['free_shipping'] ??
          selection['shipping_free'] ??
          freeShipping;
      selection['hasExchange'] ??=
          selection['exchange_after_delivery'] ??
          selection['has_exchange'] ??
          exchangeAfterDelivery;
      selection['insuranceActive'] ??=
          selection['insurance_active'] ??
          selection['insurance'] ??
          insuranceActive;
      selection['declaredValue'] ??=
          selection['declared_value'] ?? declaredValue;
      selection['declared_value'] ??= selection['declaredValue'];
      selection['weight'] ??= selection['weight_kg'] ?? weightKg;
      selection['height'] ??= selection['height_cm'] ?? heightCm;
      selection['width'] ??= selection['width_cm'] ?? widthCm;
      selection['length'] ??= selection['length_cm'] ?? lengthCm;
      selection['is_stopdesk'] ??=
          selection['deliveryType'] == 'stopdesk' ||
          selection['is_stopdesk'] == true;
      if (selection['stopdesk_id'] == null && selection['stopdeskId'] != null) {
        selection['stopdesk_id'] = selection['stopdeskId'];
      }
      return selection;
    }

    // Adresse acheteur
    String toWilaya = '';
    String toCommune = '';
    String address = '';
    String phone = '';
    if (addressId != null) {
      final addrRes = await supabase
          .from('addresses')
          .select('line1,city,state,postal_code,phone')
          .eq('id', addressId)
          .maybeSingle();
      final Map<String, dynamic>? addr = addrRes;
      if (addr != null) {
        address =
            InputSanitizer.sanitizeOptionalText(
              addr['line1'],
              maxLength: 140,
            ) ??
            '';
        toWilaya =
            InputSanitizer.sanitizeOptionalText(addr['state'], maxLength: 80) ??
            '';
        toCommune =
            InputSanitizer.sanitizeOptionalText(addr['city'], maxLength: 80) ??
            '';
        phone = InputSanitizer.sanitizePhone(addr['phone'] ?? '') ?? '';
      }
    }

    // Profil acheteur fallback phone
    if (buyerId.isNotEmpty && phone.isEmpty) {
      final buyerRes = await supabase
          .from('profiles')
          .select('phone')
          .eq('id', buyerId)
          .maybeSingle();
      final Map<String, dynamic>? buyer = buyerRes;
      if (buyer != null) {
        phone = InputSanitizer.sanitizePhone(buyer['phone'] ?? '') ?? '';
      }
    }

    // Wilaya expéditeur = vendeur
    String fromWilaya = 'Alger';
    if (sellerId.isNotEmpty) {
      final sellerRes = await supabase
          .from('profiles')
          .select('wilaya')
          .eq('id', sellerId)
          .maybeSingle();
      final Map<String, dynamic>? seller = sellerRes;
      if (seller != null) {
        fromWilaya =
            InputSanitizer.sanitizeOptionalText(
              seller['wilaya'],
              maxLength: 80,
            ) ??
            'Alger';
      }
    }

    // Produit (already loaded above)

    final safeAddress = address.isNotEmpty ? address : 'Adresse à confirmer';
    final safeWilaya = toWilaya.isNotEmpty ? toWilaya : 'M\'Sila';
    final safeCommune = toCommune.isNotEmpty ? toCommune : 'M\'Sila';
    final fallbackDeclared = declaredValue ?? price;
    final fallbackWeight = weightKg ?? 2;
    final fallbackHeight = heightCm ?? 30;
    final fallbackWidth = widthCm ?? 30;
    final fallbackLength = lengthCm ?? 30;
    return {
      'order_id': safeOrderId,
      'from_wilaya_name': fromWilaya,
      'senderWilaya': fromWilaya,
      'firstname': 'Client',
      'familyname': 'DZMarket',
      'contact_phone': phone,
      'phone': phone,
      'phone_main': phone,
      'address': safeAddress,
      'to_commune_name': safeCommune,
      'to_wilaya_name': safeWilaya,
      'receiverCommune': safeCommune,
      'receiverWilaya': safeWilaya,
      'productList': productTitle,
      'price': price,
      'do_insurance': insuranceActive,
      'insuranceActive': insuranceActive,
      'declared_value': fallbackDeclared,
      'declaredValue': fallbackDeclared,
      'length': fallbackLength,
      'width': fallbackWidth,
      'height': fallbackHeight,
      'weight': fallbackWeight,
      'freeshipping': freeShipping,
      'is_stopdesk': false,
      'has_exchange': exchangeAfterDelivery,
      'hasExchange': exchangeAfterDelivery,
    };
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
    if (isZrExpressCourier(courierId: courierId, courierName: courierName)) {
      return '24-72h';
    }
    if (isGuepexCourier(courierId: courierId, courierName: courierName)) {
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
    final safeSenderWilaya = InputSanitizer.sanitizeText(
      senderWilayaName,
      maxLength: 80,
    );
    final safeReceiverName = InputSanitizer.sanitizeText(
      receiverName,
      maxLength: 80,
    );
    final safeReceiverPhone = InputSanitizer.sanitizePhone(receiverPhone);
    final safeReceiverAddress = InputSanitizer.sanitizeText(
      receiverAddress,
      maxLength: 140,
    );
    final safeReceiverWilaya = InputSanitizer.sanitizeText(
      receiverWilaya,
      maxLength: 80,
    );
    final safeReceiverCommune = InputSanitizer.sanitizeText(
      receiverCommune,
      maxLength: 80,
    );
    final safeProductList = InputSanitizer.sanitizeText(
      productList,
      maxLength: 120,
    );

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

    final nameParts = safeReceiverName
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
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
    final trackingNumber =
        result['tracking'] ??
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

    final locale = _localeCode();
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
            'title': _labelEventTitle(locale),
            'description': _labelEventDesc(locale, 'Yalidine Express'),
            'at': DateTime.now().toIso8601String(),
          },
        ],
      }),
    );

    await RateLimiter.instance.run(
      'orders.update.label',
      () => supabase
          .from(SupabaseTables.orders)
          .update({'tracking_number': trackingNumber, 'label_url': signedUrl})
          .eq('id', safeOrderId),
    );

    final labelKey = 'order.system.shipped';
    await _postOrderSystemMessage(
      orderId: safeOrderId,
      text: L10n.trLocale(locale, labelKey),
      i18nKey: labelKey,
      status: 'shipped',
      statusI18n: 'order.status.shipped',
      trackingNumber: trackingNumber?.toString(),
      labelUrl: signedUrl,
      courierName: 'Yalidine Express',
      dedupeKey: 'order:$safeOrderId:shipped',
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
    final trackingNumber =
        result['tracking'] ??
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

    final locale = _localeCode();
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
            'title': _labelEventTitle(locale),
            'description': _labelEventDesc(locale, 'Yalidine Express'),
            'at': DateTime.now().toIso8601String(),
          },
        ],
      }),
    );

    await RateLimiter.instance.run(
      'orders.update.label',
      () => supabase
          .from(SupabaseTables.orders)
          .update({'tracking_number': trackingNumber, 'label_url': signedUrl})
          .eq('id', model.orderId),
    );

    final labelKey = 'order.system.shipped';
    await _postOrderSystemMessage(
      orderId: model.orderId,
      text: L10n.trLocale(locale, labelKey),
      i18nKey: labelKey,
      status: 'shipped',
      statusI18n: 'order.status.shipped',
      trackingNumber: trackingNumber?.toString(),
      labelUrl: signedUrl,
      courierName: 'Yalidine Express',
      dedupeKey: 'order:${model.orderId}:shipped',
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
    final safeOption = InputSanitizer.sanitizeOptionalText(
      option,
      maxLength: 60,
    );
    final safeDelivery = InputSanitizer.sanitizeOptionalText(
      deliveryMode,
      maxLength: 40,
    );
    final safeReceiverName = InputSanitizer.sanitizeOptionalText(
      receiverName,
      maxLength: 80,
    );
    final safeReceiverPhone = InputSanitizer.sanitizePhone(receiverPhone);
    final safeReceiverAddress = InputSanitizer.sanitizeOptionalText(
      receiverAddress,
      maxLength: 140,
    );
    final safeReceiverCity = InputSanitizer.sanitizeOptionalText(
      receiverCity,
      maxLength: 80,
    );
    final safeReceiverDaira = InputSanitizer.sanitizeOptionalText(
      receiverDaira,
      maxLength: 80,
    );
    final safeReceiverWilaya = InputSanitizer.sanitizeOptionalText(
      receiverWilaya,
      maxLength: 80,
    );
    final safeReceiverZip = InputSanitizer.sanitizeOptionalText(
      receiverZip,
      maxLength: 20,
    );
    final safeContent = InputSanitizer.sanitizeOptionalText(
      parcelContent,
      maxLength: 120,
    );

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
      if (sellerCourierSettings != null)
        'seller_settings': sellerCourierSettings,
    };

    final data = await LabelService().generateLabel(
      safeOrderId,
      request: request,
    );
    if (data == null || data.isEmpty) {
      throw StateError('Label generation failed');
    }
    final labelUrl = data['signed_url'] ?? data['label_url'] ?? data['label'];
    final trackingNumber =
        data['tracking_number'] ?? data['tracking'] ?? data['tracking_id'];
    if (labelUrl == null || labelUrl.toString().isEmpty) {
      throw StateError('Label URL missing from server response');
    }

    final locale = _localeCode();
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
            'title': _labelEventTitle(locale),
            'description': _labelEventDesc(locale, safeCarrier),
            'at': DateTime.now().toIso8601String(),
          },
        ],
      }),
    );
  }

  Future<void> appendDeliveryStatus(String orderId, String status) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeStatus = InputSanitizer.sanitizeText(status, maxLength: 30);
    final locale = _localeCode();
    final statusLabel = _statusLabel(locale, safeStatus);
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

    final statusText = L10n.trLocale(
      locale,
      'shipments.status_message',
      params: {'status': statusLabel},
    );
    await _postOrderSystemMessage(
      orderId: safeOrderId,
      text: statusText,
      status: safeStatus,
      statusI18n: 'order.status.$safeStatus',
      dedupeKey: 'order:$safeOrderId:status:$safeStatus',
    );
    NotificationService.instance.notifyLocal(
      L10n.trLocale(locale, 'shipments.status_notification_title'),
      L10n.trLocale(
        locale,
        'shipments.status_notification_body',
        params: {'status': statusLabel},
      ),
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
    final name = InputSanitizer.sanitizeText(
      courierName,
      maxLength: 80,
    ).toLowerCase();
    if (!name.contains('ecotrack') &&
        (apiSecret == null || apiSecret.trim().isEmpty)) {
      return {'ok': false, 'message': 'Secret manquant'};
    }
    try {
      final isZr = isZrExpressCourier(courierName: name);
      final isGuepex = isGuepexCourier(courierName: name);
      if (name.contains('yalidine') ||
          name.contains('ecotrack') ||
          isZr ||
          isGuepex) {
        final tokenLength = name.contains('ecotrack') || isZr || isGuepex
            ? 200
            : 120;
        final edge = await _validateViaEdgeDetailed(
          courierName: courierName,
          apiKey: InputSanitizer.sanitizeText(apiKey, maxLength: tokenLength),
          apiSecret: apiSecret == null || apiSecret.trim().isEmpty
              ? ''
              : InputSanitizer.sanitizeText(apiSecret, maxLength: 200),
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

    final safeTracking = InputSanitizer.sanitizeOptionalText(
      tracking,
      maxLength: 60,
    );
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
    String? sellerId,
  }) async {
    final safeCourierId = InputSanitizer.sanitizeText(
      courierId,
      maxLength: 40,
    ).toLowerCase();
    final cacheKey = _courierWilayaCacheKey(safeCourierId, sellerId);
    final cached = _courierWilayasCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }
    final isZrExpress = isZrExpressCourier(courierId: safeCourierId);
    if (safeCourierId.contains('yalidine')) {
      if (sellerId != null && sellerId.isNotEmpty) {
        final edge = await _fetchCourierWilayasViaEdge(
          sellerId: sellerId,
          courierId: safeCourierId,
        );
        if (edge.isNotEmpty) {
          _courierWilayasCache[cacheKey] = _CacheItem(
            edge,
            DateTime.now().add(_cacheTtl),
          );
          return edge;
        }
      }
      final fallback = await _fetchDbWilayas();
      if (fallback.isNotEmpty) {
        _courierWilayasCache[cacheKey] = _CacheItem(
          fallback,
          DateTime.now().add(_cacheTtl),
        );
      }
      return fallback;
    } else if (safeCourierId.contains('ecotrack')) {
      if (sellerId != null && sellerId.isNotEmpty) {
        final edge = await _fetchCourierWilayasViaEdge(
          sellerId: sellerId,
          courierId: safeCourierId,
        );
        if (edge.isNotEmpty) {
          _courierWilayasCache[cacheKey] = _CacheItem(
            edge,
            DateTime.now().add(_cacheTtl),
          );
          return edge;
        }
      }
      final fallback = await _fetchDbWilayas();
      if (fallback.isNotEmpty) {
        _courierWilayasCache[cacheKey] = _CacheItem(
          fallback,
          DateTime.now().add(_cacheTtl),
        );
      }
      return fallback;
    }
    if (isZrExpress) {
      if (sellerId != null && sellerId.isNotEmpty) {
        final edge = await _fetchCourierWilayasViaEdge(
          sellerId: sellerId,
          courierId: safeCourierId,
        );
        if (edge.isNotEmpty) {
          _courierWilayasCache[cacheKey] = _CacheItem(
            edge,
            DateTime.now().add(_cacheTtl),
          );
        }
        return edge;
      }
      return const [];
    }
    if (sellerId != null && sellerId.isNotEmpty) {
      final edge = await _fetchCourierWilayasViaEdge(
        sellerId: sellerId,
        courierId: safeCourierId,
      );
      if (edge.isNotEmpty) {
        _courierWilayasCache[cacheKey] = _CacheItem(
          edge,
          DateTime.now().add(_cacheTtl),
        );
        return edge;
      }
    }
    final fallback = await _fetchDbWilayas();
    if (fallback.isNotEmpty) {
      _courierWilayasCache[cacheKey] = _CacheItem(
        fallback,
        DateTime.now().add(_cacheTtl),
      );
    }
    return fallback;
  }

  Future<List<Map<String, String>>> _fetchCourierWilayasViaEdge({
    required String sellerId,
    required String courierId,
  }) async {
    try {
      final response = await RateLimiter.instance.run(
        'courier.wilayas.edge',
        () => supabase.functions.invoke(
          'courier-locations',
          body: {
            'seller_id': sellerId,
            'courier_id': courierId,
            'type': 'wilayas',
          },
        ),
      );
      final data = response.data;
      final rows = data is Map ? data['data'] : null;
      if (rows is List) {
        return rows
            .whereType<Map>()
            .map(
              (r) => {
                'id': r['id']?.toString() ?? '',
                'code': r['code']?.toString() ?? '',
                'name': r['name']?.toString() ?? '',
              },
            )
            .where((m) => m['name']!.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<List<Map<String, String>>> fetchCourierCommunes({
    required String courierId,
    Map<String, dynamic>? settings,
    required String wilayaCode,
    String? sellerId,
  }) async {
    final safeCourierId = InputSanitizer.sanitizeText(
      courierId,
      maxLength: 40,
    ).toLowerCase();
    final isZrExpress = isZrExpressCourier(courierId: safeCourierId);
    final safeWilayaCode = InputSanitizer.sanitizeText(
      wilayaCode,
      maxLength: isZrExpress ? 64 : 8,
    );
    final cacheKey = _courierCommuneCacheKey(
      safeCourierId,
      sellerId,
      safeWilayaCode,
    );
    final cached = _courierCommunesCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }
    if (safeCourierId.contains('yalidine')) {
      if (sellerId != null && sellerId.isNotEmpty) {
        final edge = await _fetchCourierCommunesViaEdge(
          sellerId: sellerId,
          courierId: safeCourierId,
          wilayaCode: safeWilayaCode,
        );
        if (edge.isNotEmpty) {
          _courierCommunesCache[cacheKey] = _CacheItem(
            edge,
            DateTime.now().add(_cacheTtl),
          );
          return edge;
        }
      }
      final fallback = await _fetchDbCommunes(safeWilayaCode);
      if (fallback.isNotEmpty) {
        _courierCommunesCache[cacheKey] = _CacheItem(
          fallback,
          DateTime.now().add(_cacheTtl),
        );
      }
      return fallback;
    } else if (safeCourierId.contains('ecotrack')) {
      if (sellerId != null && sellerId.isNotEmpty) {
        final edge = await _fetchCourierCommunesViaEdge(
          sellerId: sellerId,
          courierId: safeCourierId,
          wilayaCode: safeWilayaCode,
        );
        if (edge.isNotEmpty) {
          _courierCommunesCache[cacheKey] = _CacheItem(
            edge,
            DateTime.now().add(_cacheTtl),
          );
          return edge;
        }
      }
      final fallback = await _fetchDbCommunes(safeWilayaCode);
      if (fallback.isNotEmpty) {
        _courierCommunesCache[cacheKey] = _CacheItem(
          fallback,
          DateTime.now().add(_cacheTtl),
        );
      }
      return fallback;
    }
    if (isZrExpress) {
      if (sellerId != null && sellerId.isNotEmpty) {
        final edge = await _fetchCourierCommunesViaEdge(
          sellerId: sellerId,
          courierId: safeCourierId,
          wilayaCode: safeWilayaCode,
        );
        if (edge.isNotEmpty) {
          _courierCommunesCache[cacheKey] = _CacheItem(
            edge,
            DateTime.now().add(_cacheTtl),
          );
        }
        return edge;
      }
      return const [];
    }
    if (sellerId != null && sellerId.isNotEmpty) {
      final edge = await _fetchCourierCommunesViaEdge(
        sellerId: sellerId,
        courierId: safeCourierId,
        wilayaCode: safeWilayaCode,
      );
      if (edge.isNotEmpty) {
        _courierCommunesCache[cacheKey] = _CacheItem(
          edge,
          DateTime.now().add(_cacheTtl),
        );
        return edge;
      }
    }
    final fallback = await _fetchDbCommunes(safeWilayaCode);
    if (fallback.isNotEmpty) {
      _courierCommunesCache[cacheKey] = _CacheItem(
        fallback,
        DateTime.now().add(_cacheTtl),
      );
    }
    return fallback;
  }

  Future<List<Map<String, String>>> _fetchCourierCommunesViaEdge({
    required String sellerId,
    required String courierId,
    required String wilayaCode,
  }) async {
    try {
      final response = await RateLimiter.instance.run(
        'courier.locations.edge',
        () => supabase.functions.invoke(
          'courier-locations',
          body: {
            'seller_id': sellerId,
            'courier_id': courierId,
            'wilaya_code': wilayaCode,
          },
        ),
      );
      final data = response.data;
      final rows = data is Map ? data['data'] : null;
      if (rows is List) {
        return rows
            .whereType<Map>()
            .map(
              (r) => {
                'id': r['id']?.toString() ?? '',
                'name': r['name']?.toString() ?? '',
                'wilaya_id': r['wilaya_id']?.toString() ?? '',
                'has_stop_desk': r['has_stop_desk']?.toString() ?? '',
                'stopdesk_id': r['stopdesk_id']?.toString() ?? '',
              },
            )
            .where((m) => m['name']!.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
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
      final trimmed = wilayaCode.trim();
      final padded = trimmed.length == 1 ? trimmed.padLeft(2, '0') : trimmed;
      final codes = <String>{
        trimmed,
        padded,
      }.where((v) => v.isNotEmpty).toList();
      final rows = await RateLimiter.instance.run(
        'communes.db',
        () => supabase
            .from(SupabaseTables.communes)
            .select('name_fr, name_ar')
            .inFilter('wilaya_code', codes)
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

  Future<bool> _validateEcotrack({required String token}) async {
    final uriWithParam = Uri.parse(
      'https://api.ecotrack.dz/api/v1/validate/token?api_token=${Uri.encodeQueryComponent(token.trim())}',
    );
    final uriNoParam = Uri.parse(
      'https://api.ecotrack.dz/api/v1/validate/token',
    );
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
      _ecotrackFeesCache[cacheKey] = _CacheItem(
        data,
        DateTime.now().add(_cacheTtl),
      );
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
    final uri = Uri.parse(
      'https://api.ecotrack.dz/api/v1/create/order',
    ).replace(queryParameters: params);
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
      'nom_client': '${selection['familyname']} ${selection['firstname']}'
          .trim(),
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
        final msg =
            results[safeOrderId]['message']?.toString() ?? 'Ecotrack error';
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

    final locale = _localeCode();
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
            'title': _labelEventTitle(locale),
            'description': _labelEventDesc(locale, 'Ecotrack'),
            'at': DateTime.now().toIso8601String(),
          },
        ],
      }),
    );

    await RateLimiter.instance.run(
      'orders.update.label.ecotrack',
      () => supabase
          .from(SupabaseTables.orders)
          .update({'tracking_number': tracking, 'label_url': labelUrl})
          .eq('id', safeOrderId),
    );

    final labelKey = 'order.system.shipped';
    await _postOrderSystemMessage(
      orderId: safeOrderId,
      text: L10n.trLocale(locale, labelKey),
      i18nKey: labelKey,
      status: 'shipped',
      statusI18n: 'order.status.shipped',
      trackingNumber: tracking,
      labelUrl: labelUrl,
      courierName: 'Ecotrack',
      dedupeKey: 'order:$safeOrderId:shipped',
    );

    return {'tracking': tracking, 'label_url': labelUrl};
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
                    'id, seller_id, courier_name, courier_id, shipping_cost, shipping_option, delivery_method, created_at',
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
          'courier_id': order['courier_id'] as String?,
          'shipping_option': order['shipping_option'] as String?,
          'delivery_method': order['delivery_method'] as String?,
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

      return result.take(30).toList();
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
    final safeOwnerId = ownerId == null
        ? null
        : InputSanitizer.sanitizeId(ownerId, maxLength: 64);
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
    if (safeOwnerId == null && current != null) {
      query = query.eq('owner_id', current);
    }

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
    final extra = map['extra'] is Map
        ? Map<String, dynamic>.from(map['extra'] as Map)
        : null;
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
    final safeCourierName = InputSanitizer.sanitizeText(
      courierName,
      maxLength: 80,
    );
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
    final safeCourierName = InputSanitizer.sanitizeText(
      courierName,
      maxLength: 80,
    );
    final lowerName = safeCourierName.toLowerCase();
    final isEcotrack = lowerName.contains('ecotrack');
    final isZrExpress = isZrExpressCourier(courierName: lowerName);
    final isGuepex = isGuepexCourier(courierName: lowerName);
    final safeApiKey = InputSanitizer.sanitizeText(
      apiKey,
      maxLength: (isEcotrack || isZrExpress || isGuepex) ? 200 : 120,
    );
    final safeApiSecret = isEcotrack || apiSecret.trim().isEmpty
        ? ''
        : InputSanitizer.sanitizeText(
            apiSecret,
            maxLength: (isZrExpress || isGuepex) ? 200 : 120,
          );
    final safeSenderId = InputSanitizer.sanitizeOptionalText(
      senderId,
      maxLength: 80,
    );
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
        'extra': isEcotrack
            ? {'base_url': 'https://api.ecotrack.dz'}
            : isGuepex
            ? {'base_url': 'https://api.guepex.app'}
            : null,
      }, onConflict: 'owner_id,courier_id'),
    );
  }

  Future<void> deleteSellerDeliverySettingsByName(String courierName) async {
    final safeCourierName = InputSanitizer.sanitizeText(
      courierName,
      maxLength: 80,
    );
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
