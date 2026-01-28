import 'package:dzmarket/src/models/address.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class AddressService {
  Stream<List<Address>> streamAddresses(String userId) {
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
    return RateLimiter.instance.stream(
      'addresses.stream',
      () => supabase
          .from('addresses')
          .stream(primaryKey: ['id'])
          .eq('user_id', safeUserId)
          .order('created_at')
          .map((rows) => rows.map(Address.fromJson).toList()),
    );
  }

  Future<void> addAddress({
    required String line1,
    String? line2,
    String? city,
    String? state,
    String? postalCode,
    String country = 'DZ',
    String? label,
    String? fullName,
    String? phone,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required');

    final safeLine1 = InputSanitizer.sanitizeText(line1, maxLength: 120);
    if (safeLine1.isEmpty) throw FormatException('Address line required.');
    final safeLine2 =
        InputSanitizer.sanitizeOptionalText(line2, maxLength: 120);
    final safeCity = InputSanitizer.sanitizeOptionalText(city, maxLength: 80);
    final safeState = InputSanitizer.sanitizeOptionalText(state, maxLength: 80);
    final safePostal =
        InputSanitizer.sanitizeOptionalText(postalCode, maxLength: 20);
    final safeCountry =
        InputSanitizer.sanitizeText(country, maxLength: 2).toUpperCase();
    final safeLabel = InputSanitizer.sanitizeOptionalText(label, maxLength: 50);
    final safeName =
        InputSanitizer.sanitizeOptionalText(fullName, maxLength: 80);
    final safePhone = InputSanitizer.sanitizePhone(phone);

    await RateLimiter.instance.run(
      'addresses.insert',
      () => supabase.from('addresses').insert({
        'user_id': userId,
        'line1': safeLine1,
        'line2': safeLine2,
        'city': safeCity,
        'state': safeState,
        'postal_code': safePostal,
        'country': safeCountry,
        'label': safeLabel,
        'full_name': safeName,
        'phone': safePhone,
      }),
    );
  }
}
