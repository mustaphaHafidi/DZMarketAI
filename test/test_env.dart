import 'test_env_io.dart'
    if (dart.library.html) 'test_env_web.dart' as env;

String? _clean(String? value) {
  if (value == null || value.isEmpty) return null;
  return value;
}

class TestEnv {
  static String? get supabaseUrl => _clean(env.envSupabaseUrl());
  static String? get supabaseAnonKey => _clean(env.envSupabaseAnonKey());
  static String? get testEmail => _clean(env.envTestUserEmail());
  static String? get testPassword => _clean(env.envTestUserPassword());
  static String? get testRoomId => _clean(env.envTestRoomId());
  static String? get testProductId => _clean(env.envTestProductId());
  static String? get testBuyerId => _clean(env.envTestBuyerId());
  static String? get testSellerId => _clean(env.envTestSellerId());
  static String? get testOrderId => _clean(env.envTestOrderId());
  static String? get testCourierName => _clean(env.envTestCourierName());
  static String? get testCourierId => _clean(env.envTestCourierId());
  static String? get testCourierApiKey => _clean(env.envTestCourierApiKey());
  static String? get testCourierApiSecret =>
      _clean(env.envTestCourierApiSecret());
  static String? get testOtherEmail => _clean(env.envTestOtherUserEmail());
  static String? get testOtherPassword =>
      _clean(env.envTestOtherUserPassword());
  static String? get testOtherOrderId => _clean(env.envTestOtherOrderId());
  static String? get testRoomId2 => _clean(env.envTestRoomId2());
  static String? get testProductId2 => _clean(env.envTestProductId2());
  static String? get testCourierCreateParcel =>
      _clean(env.envTestCourierCreateParcel());
  static String? get testShipmentSelectionJson =>
      _clean(env.envTestShipmentSelectionJson());

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
