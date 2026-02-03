import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/test_env.dart';
import '../test/test_supabase.dart';

List<String> _missingLiveRequirements() {
  final missing = <String>[];
  if (!TestEnv.hasSupabaseCreds) {
    missing.add('SUPABASE_URL + SUPABASE_ANON_KEY');
  }
  if (!TestEnv.hasAuthCreds) {
    missing.add('TEST_USER_EMAIL + TEST_USER_PASSWORD');
  }
  if (!TestEnv.hasCourierCreds) {
    missing.add('TEST_COURIER_NAME + TEST_COURIER_API_KEY');
  }
  final hasSellerCreds =
      TestEnv.hasSellerAuthCreds || TestEnv.hasOtherAuthCreds;
  if (!hasSellerCreds) {
    missing.add(
      'TEST_SELLER_USER_EMAIL + TEST_SELLER_USER_PASSWORD (or TEST_OTHER_*)',
    );
  }
  final allowLive =
      (TestEnv.testCourierCreateParcel ?? '').toLowerCase() == 'true';
  if (!allowLive) {
    missing.add('TEST_COURIER_CREATE_PARCEL=true');
  }
  if ((TestEnv.testShipmentSelectionJson ?? '').isEmpty) {
    missing.add('TEST_SHIPMENT_SELECTION_JSON');
  }
  if ((TestEnv.testOrderId ?? '').isEmpty &&
      (TestEnv.testProductId ?? '').isEmpty) {
    missing.add('TEST_ORDER_ID (or TEST_PRODUCT_ID to auto-create)');
  }
  return missing;
}

bool _shouldSkipLive() {
  final missing = _missingLiveRequirements();
  if (missing.isEmpty) return false;
  developer.log('Skipping live courier label test; missing:');
  for (final item in missing) {
    developer.log(' - $item');
  }
  return true;
}

Map<String, dynamic> _parseSelection(String raw) {
  String escapeForJsonString(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  dynamic current = raw.trim();
  for (var i = 0; i < 6; i++) {
    if (current is Map<String, dynamic>) return current;
    if (current is String) {
      var normalized = current.trim();
      try {
        final decoded = jsonDecode(normalized);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is String) {
          current = decoded;
          continue;
        }
      } catch (_) {}

      if (normalized.startsWith('"') && normalized.endsWith('"')) {
        normalized = normalized.substring(1, normalized.length - 1);
      }

      if (normalized.contains(r'\\') || normalized.contains(r'\"')) {
        normalized = normalized.replaceAll(r'\\\"', '"');
        normalized = normalized.replaceAll(r'\\\\', r'\');
      }

      try {
        final unescaped =
            jsonDecode('"${escapeForJsonString(normalized)}"');
        if (unescaped is String) {
          current = unescaped;
          continue;
        }
      } catch (_) {}

      current = normalized;
      continue;
    }
    break;
  }

  throw StateError('TEST_SHIPMENT_SELECTION_JSON must be a JSON object');
}

List<String> _validateSelection(Map<String, dynamic> selection) {
  final errors = <String>[];
  final phone = selection['phone'] ?? selection['phone_main'];
  void requireField(String key) {
    if (selection[key] == null || selection[key].toString().trim().isEmpty) {
      errors.add(key);
    }
  }

  requireField('firstname');
  requireField('familyname');
  if (phone == null || phone.toString().trim().isEmpty) {
    errors.add('phone/phone_main');
  }
  requireField('address');
  requireField('receiverCommune');
  requireField('wilayaCode');
  requireField('price');
  requireField('productList');
  requireField('weight');
  requireField('deliveryType');
  return errors;
}

String? _sellerEmail() =>
    TestEnv.testSellerEmail ?? TestEnv.testOtherEmail;

String? _sellerPassword() =>
    TestEnv.testSellerPassword ?? TestEnv.testOtherPassword;

String _normalizeCourierId(String value) => value.trim().toLowerCase();

Future<String?> _resolveCourierId({
  required String? courierId,
  required String? courierName,
}) async {
  if (courierId != null && courierId.trim().isNotEmpty) {
    return _normalizeCourierId(courierId);
  }
  final name = courierName?.trim();
  if (name == null || name.isEmpty) return null;
  try {
    final rows = await Supabase.instance.client
        .from('couriers')
        .select('code,name')
        .ilike('name', name)
        .limit(1);
    if (rows.isNotEmpty) {
      final code = rows.first['code']?.toString();
      if (code != null && code.isNotEmpty) {
        return _normalizeCourierId(code);
      }
    }
  } catch (_) {
    // ignore and fall back to slugify below
  }
  return _normalizeCourierId(name.replaceAll(' ', '-'));
}

Future<List<String>> _listCourierCodes() async {
  try {
    final rows = await Supabase.instance.client
        .from('couriers')
        .select('code')
        .limit(50);
    return rows
        .map((row) => row['code']?.toString())
        .whereType<String>()
        .toList();
  } catch (_) {}
  return const [];
}

Future<String?> _ensureOrderId() async {
  final existing = TestEnv.testOrderId;
  if (existing != null && existing.isNotEmpty) return existing;
  final productId = TestEnv.testProductId;
  if (productId == null || productId.isEmpty) return null;
  try {
    return await OrderService().createOrder(
      productId: productId,
      paymentMethod: 'cod',
      shippingOption: 'cod',
      deliveryMethod: 'home',
    );
  } catch (_) {
    final found = await _findExistingOrderId(productId);
    if (found != null) return found;
    rethrow;
  }
}

Future<String?> _findExistingOrderId(String productId) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return null;
  final rows = await Supabase.instance.client
      .from('orders')
      .select('id,created_at')
      .eq('product_id', productId)
      .eq('buyer_id', userId)
      .order('created_at', ascending: false)
      .limit(1);
  if (rows.isNotEmpty) {
    return rows.first['id']?.toString();
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Couriers: validate shipment selection payload', (tester) async {
    if ((TestEnv.testShipmentSelectionJson ?? '').isEmpty) {
      developer.log(
        'Skipping selection validation; missing TEST_SHIPMENT_SELECTION_JSON',
      );
      return;
    }
    final selection = _parseSelection(TestEnv.testShipmentSelectionJson!);
    final missing = _validateSelection(selection);
    expect(
      missing,
      isEmpty,
      reason: 'Missing selection fields: ${missing.join(', ')}',
    );
  }, skip: (TestEnv.testShipmentSelectionJson ?? '').isEmpty);

  testWidgets('Couriers: validate token success/failure', (tester) async {
    if (!TestEnv.hasCourierCreds) {
      return;
    }
    final courier = TestEnv.testCourierName!;
    final apiKey = TestEnv.testCourierApiKey!;
    final apiSecret = TestEnv.testCourierApiSecret ?? '';

    final service = ShippingService();
    final ok = await service.validateCredentialsDetailed(
      courierName: courier,
      apiKey: apiKey,
      apiSecret: apiSecret,
    );
    expect(ok['ok'], isTrue);

    final bad = await service.validateCredentialsDetailed(
      courierName: courier,
      apiKey: 'invalid-token',
      apiSecret: 'invalid-secret',
    );
    expect(bad['ok'], isFalse);
  }, skip: !TestEnv.hasCourierCreds);

  testWidgets('Couriers: create parcel + label (live)', (tester) async {
    await ensureSupabaseInitialized(
      url: TestEnv.supabaseUrl!,
      anonKey: TestEnv.supabaseAnonKey!,
    );

    await AuthService.instance.signIn(
      TestEnv.testEmail!,
      TestEnv.testPassword!,
    );

    if (TestEnv.testProductId != null && TestEnv.testProductId!.isNotEmpty) {
      final buyerId = Supabase.instance.client.auth.currentUser?.id ?? '';
      final productRow = await Supabase.instance.client
          .from('products')
          .select('id,owner_id')
          .eq('id', TestEnv.testProductId!)
          .maybeSingle();
      if (productRow != null) {
        final ownerId = productRow['owner_id']?.toString() ?? '';
        developer.log('Buyer ID: $buyerId');
        developer.log('Product owner ID: $ownerId');
      } else {
        developer.log('Product not found for TEST_PRODUCT_ID');
      }
    }

    final orderId = TestEnv.testOrderId ?? await _ensureOrderId();
    expect(orderId, isNotNull, reason: 'Missing order fixture for live test');
    final buyerOrder = await Supabase.instance.client
        .from('orders')
        .select('id,seller_id')
        .eq('id', orderId!)
        .maybeSingle();
    expect(
      buyerOrder,
      isNotNull,
      reason: 'Order not visible to buyer; check Supabase project/creds',
    );
    final selection = _parseSelection(TestEnv.testShipmentSelectionJson!);
    selection['remark'] ??= 'test-run-${DateTime.now().toIso8601String()}';
    final missing = _validateSelection(selection);
    expect(
      missing,
      isEmpty,
      reason: 'Missing selection fields: ${missing.join(', ')}',
    );
    final courierName = TestEnv.testCourierName!;
    final resolvedCourierId = await _resolveCourierId(
      courierId: TestEnv.testCourierId,
      courierName: courierName,
    );
    if (resolvedCourierId == null) {
      final codes = await _listCourierCodes();
      fail(
        'Unable to resolve courier id from name/slug. '
        'Set TEST_COURIER_ID or use a known courier name. '
        'Known codes: ${codes.isEmpty ? 'none' : codes.join(', ')}',
      );
    }
    final courierId = resolvedCourierId;

    await AuthService.instance.signOut();
    await AuthService.instance.signIn(
      _sellerEmail()!,
      _sellerPassword()!,
    );
    final sellerId = Supabase.instance.client.auth.currentUser?.id ?? '';
    developer.log('Seller ID: $sellerId');
    developer.log('Courier name: $courierName');
    developer.log('Resolved courier_id: $courierId');

    final sellerOrder = await Supabase.instance.client
        .from('orders')
        .select('id,seller_id')
        .eq('id', orderId)
        .maybeSingle();
    expect(
      sellerOrder,
      isNotNull,
      reason: 'Order not visible to seller; ensure seller owns product',
    );

    final settingsRows = await Supabase.instance.client
        .from('seller_delivery_settings')
        .select('id')
        .eq('owner_id', sellerId)
        .eq('courier_id', courierId)
        .limit(1);
    final hasSettings = settingsRows.isNotEmpty;
    developer.log('Seller courier settings present: $hasSettings');
    if (!hasSettings) {
      fail(
        'Missing courier settings for seller. '
        'Open the app as the seller and save courier settings for '
        '"$courierId" (ensure courier_id/slug matches).',
      );
    }

    final result = await ShippingService().createShipment(
      orderId: orderId,
      courierId: courierId,
      courierName: courierName,
      selection: selection,
    );

    expect(result['ok'], isNot(false));

    await AuthService.instance.signOut();
  }, skip: _shouldSkipLive());
}
