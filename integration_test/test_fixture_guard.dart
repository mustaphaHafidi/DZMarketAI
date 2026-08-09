import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> expectCurrentTestUserActive() async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  expect(userId, isNotNull, reason: 'Test user is not signed in.');

  final profile = await client
      .from('profiles')
      .select('status')
      .eq('id', userId!)
      .maybeSingle();
  final status = profile?['status']?.toString() ?? 'active';
  expect(
    status,
    'active',
    reason: 'TEST_USER_EMAIL must point to an active fixture account.',
  );
}

Future<void> expectOrderableProductFixture(String productId) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  expect(userId, isNotNull, reason: 'Test user is not signed in.');

  final product = await client
      .from('products')
      .select('owner_id,status,is_archived,stock_quantity')
      .eq('id', productId)
      .maybeSingle();
  expect(product, isNotNull, reason: 'TEST_PRODUCT_ID does not exist.');
  expect(
    product!['owner_id']?.toString(),
    isNot(userId),
    reason: 'TEST_PRODUCT_ID must not be owned by TEST_USER_EMAIL.',
  );
  expect(
    product['status']?.toString() ?? 'active',
    'active',
    reason: 'TEST_PRODUCT_ID must be active.',
  );
  expect(
    product['is_archived'] == true,
    isFalse,
    reason: 'TEST_PRODUCT_ID must not be archived.',
  );
  expect(
    (product['stock_quantity'] as num?)?.toInt() ?? 0,
    greaterThan(0),
    reason: 'TEST_PRODUCT_ID must have stock for order integration tests.',
  );
}
