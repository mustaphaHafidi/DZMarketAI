import 'dart:io';

class TestEnv {
  static String? get supabaseUrl => Platform.environment['SUPABASE_URL'];
  static String? get supabaseAnonKey => Platform.environment['SUPABASE_ANON_KEY'];
  static String? get testEmail => Platform.environment['TEST_USER_EMAIL'];
  static String? get testPassword => Platform.environment['TEST_USER_PASSWORD'];
  static String? get testRoomId => Platform.environment['TEST_ROOM_ID'];
  static String? get testProductId => Platform.environment['TEST_PRODUCT_ID'];
  static String? get testBuyerId => Platform.environment['TEST_BUYER_ID'];
  static String? get testSellerId => Platform.environment['TEST_SELLER_ID'];
  static String? get testOrderId => Platform.environment['TEST_ORDER_ID'];
  static String? get testCourierName => Platform.environment['TEST_COURIER_NAME'];
  static String? get testCourierId => Platform.environment['TEST_COURIER_ID'];
  static String? get testCourierApiKey =>
      Platform.environment['TEST_COURIER_API_KEY'];
  static String? get testCourierApiSecret =>
      Platform.environment['TEST_COURIER_API_SECRET'];
  static String? get testOtherEmail =>
      Platform.environment['TEST_OTHER_USER_EMAIL'];
  static String? get testOtherPassword =>
      Platform.environment['TEST_OTHER_USER_PASSWORD'];
  static String? get testOtherOrderId =>
      Platform.environment['TEST_OTHER_ORDER_ID'];
  static String? get testRoomId2 => Platform.environment['TEST_ROOM_ID_2'];
  static String? get testProductId2 => Platform.environment['TEST_PRODUCT_ID_2'];
  static String? get testCourierCreateParcel =>
      Platform.environment['TEST_COURIER_CREATE_PARCEL'];
  static String? get testShipmentSelectionJson =>
      Platform.environment['TEST_SHIPMENT_SELECTION_JSON'];

  static bool get hasSupabaseCreds =>
      (supabaseUrl ?? '').isNotEmpty && (supabaseAnonKey ?? '').isNotEmpty;

  static bool get hasAuthCreds =>
      hasSupabaseCreds &&
      (testEmail ?? '').isNotEmpty &&
      (testPassword ?? '').isNotEmpty;

  static bool get hasChatFixtures =>
      (testRoomId ?? '').isNotEmpty &&
      (testProductId ?? '').isNotEmpty &&
      (testBuyerId ?? '').isNotEmpty &&
      (testSellerId ?? '').isNotEmpty;

  static bool get hasOrderFixture => (testOrderId ?? '').isNotEmpty;

  static bool get hasCourierCreds =>
      (testCourierName ?? '').isNotEmpty &&
      (testCourierApiKey ?? '').isNotEmpty;

  static bool get hasOtherAuthCreds =>
      (testOtherEmail ?? '').isNotEmpty &&
      (testOtherPassword ?? '').isNotEmpty &&
      hasSupabaseCreds;

  static bool get hasSecondChatRoom =>
      (testRoomId2 ?? '').isNotEmpty && (testProductId2 ?? '').isNotEmpty;
}
