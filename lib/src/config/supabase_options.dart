class SupabaseOptions {
  // Do not ship secrets in source. Provide values at build/run time via --dart-define.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Defaults can be overridden with --dart-define for staging/prod.
  static const labelBucket = String.fromEnvironment(
    'LABEL_BUCKET',
    defaultValue: 'labels',
  );
  static const labelFunction = String.fromEnvironment(
    'LABEL_FUNCTION',
    defaultValue: 'generate-label',
  );
  static const createShipmentFunction = String.fromEnvironment(
    'CREATE_SHIPMENT_FUNCTION',
    defaultValue: 'create_shipment',
  );
}

class SupabaseTables {
  static const profiles = 'profiles';
  static const products = 'products';
  static const orders = 'orders';
  static const shipments = 'shipments';
  static const messages = 'messages';
  static const conversations = 'conversations';
  static const reads = 'reads';
  static const driverPositions = 'driver_positions';
  static const favorites = 'favorites';
  static const savedSearches = 'saved_searches';
  static const offers = 'offers';
  static const paymentIntents = 'payment_intents';
  static const addresses = 'addresses';
  static const reviews = 'reviews';
  static const reports = 'reports';
  static const notificationEvents = 'notification_events';
  static const notificationPreferences = 'notification_preferences';
  static const categories = 'categories';
  static const wilayas = 'wilayas';
  static const communes = 'communes';
  static const chatRooms = 'chat_rooms';
}
