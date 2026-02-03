import 'dart:io';

String? envSupabaseUrl() {
  const value = String.fromEnvironment('SUPABASE_URL');
  return value.isNotEmpty ? value : Platform.environment['SUPABASE_URL'];
}

String? envSupabaseAnonKey() {
  const value = String.fromEnvironment('SUPABASE_ANON_KEY');
  return value.isNotEmpty ? value : Platform.environment['SUPABASE_ANON_KEY'];
}

String? envTestUserEmail() {
  const value = String.fromEnvironment('TEST_USER_EMAIL');
  return value.isNotEmpty ? value : Platform.environment['TEST_USER_EMAIL'];
}

String? envTestUserPassword() {
  const value = String.fromEnvironment('TEST_USER_PASSWORD');
  return value.isNotEmpty ? value : Platform.environment['TEST_USER_PASSWORD'];
}

String? envTestRoomId() {
  const value = String.fromEnvironment('TEST_ROOM_ID');
  return value.isNotEmpty ? value : Platform.environment['TEST_ROOM_ID'];
}

String? envTestProductId() {
  const value = String.fromEnvironment('TEST_PRODUCT_ID');
  return value.isNotEmpty ? value : Platform.environment['TEST_PRODUCT_ID'];
}

String? envTestBuyerId() {
  const value = String.fromEnvironment('TEST_BUYER_ID');
  return value.isNotEmpty ? value : Platform.environment['TEST_BUYER_ID'];
}

String? envTestSellerId() {
  const value = String.fromEnvironment('TEST_SELLER_ID');
  return value.isNotEmpty ? value : Platform.environment['TEST_SELLER_ID'];
}

String? envTestOrderId() {
  const value = String.fromEnvironment('TEST_ORDER_ID');
  return value.isNotEmpty ? value : Platform.environment['TEST_ORDER_ID'];
}

String? envTestCourierName() {
  const value = String.fromEnvironment('TEST_COURIER_NAME');
  return value.isNotEmpty ? value : Platform.environment['TEST_COURIER_NAME'];
}

String? envTestCourierId() {
  const value = String.fromEnvironment('TEST_COURIER_ID');
  return value.isNotEmpty ? value : Platform.environment['TEST_COURIER_ID'];
}

String? envTestCourierApiKey() {
  const value = String.fromEnvironment('TEST_COURIER_API_KEY');
  return value.isNotEmpty
      ? value
      : Platform.environment['TEST_COURIER_API_KEY'];
}

String? envTestCourierApiSecret() {
  const value = String.fromEnvironment('TEST_COURIER_API_SECRET');
  return value.isNotEmpty
      ? value
      : Platform.environment['TEST_COURIER_API_SECRET'];
}

String? envTestOtherUserEmail() {
  const value = String.fromEnvironment('TEST_OTHER_USER_EMAIL');
  return value.isNotEmpty
      ? value
      : Platform.environment['TEST_OTHER_USER_EMAIL'];
}

String? envTestOtherUserPassword() {
  const value = String.fromEnvironment('TEST_OTHER_USER_PASSWORD');
  return value.isNotEmpty
      ? value
      : Platform.environment['TEST_OTHER_USER_PASSWORD'];
}

String? envTestOtherOrderId() {
  const value = String.fromEnvironment('TEST_OTHER_ORDER_ID');
  return value.isNotEmpty
      ? value
      : Platform.environment['TEST_OTHER_ORDER_ID'];
}

String? envTestSellerUserEmail() {
  const value = String.fromEnvironment('TEST_SELLER_USER_EMAIL');
  return value.isNotEmpty
      ? value
      : Platform.environment['TEST_SELLER_USER_EMAIL'];
}

String? envTestSellerUserPassword() {
  const value = String.fromEnvironment('TEST_SELLER_USER_PASSWORD');
  return value.isNotEmpty
      ? value
      : Platform.environment['TEST_SELLER_USER_PASSWORD'];
}

String? envTestRoomId2() {
  const value = String.fromEnvironment('TEST_ROOM_ID_2');
  return value.isNotEmpty ? value : Platform.environment['TEST_ROOM_ID_2'];
}

String? envTestProductId2() {
  const value = String.fromEnvironment('TEST_PRODUCT_ID_2');
  return value.isNotEmpty ? value : Platform.environment['TEST_PRODUCT_ID_2'];
}

String? envTestCourierCreateParcel() {
  const value = String.fromEnvironment('TEST_COURIER_CREATE_PARCEL');
  return value.isNotEmpty
      ? value
      : Platform.environment['TEST_COURIER_CREATE_PARCEL'];
}

String? envTestShipmentSelectionJson() {
  const value = String.fromEnvironment('TEST_SHIPMENT_SELECTION_JSON');
  return value.isNotEmpty
      ? value
      : Platform.environment['TEST_SHIPMENT_SELECTION_JSON'];
}
