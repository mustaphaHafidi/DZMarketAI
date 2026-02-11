import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/models/profile.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  User? get currentUser => supabase.auth.currentUser;

  Stream<AuthState> get authChanges => supabase.auth.onAuthStateChange;

  Future<AuthResponse> signIn(String email, String password) async {
    final safeEmail = InputSanitizer.sanitizeEmail(email);
    final safePassword = InputSanitizer.sanitizePassword(password);
    final response = await RateLimiter.instance.run(
      'auth.signIn',
      () => supabase.auth.signInWithPassword(
        email: safeEmail,
        password: safePassword,
      ),
    );
    final user = response.user;
    if (user != null) {
      await _ensureProfile(user);
    }
    return response;
  }

  Future<AuthResponse> signUp(
    String email,
    String password, {
    String? fullName,
    String? phone,
  }) async {
    final safeEmail = InputSanitizer.sanitizeEmail(email);
    final safePassword = InputSanitizer.sanitizePassword(password);
    final safeFullName =
        InputSanitizer.sanitizeOptionalText(fullName, maxLength: 80);
    final safePhone = InputSanitizer.sanitizePhone(phone);
    final metadata = <String, dynamic>{};
    if (safeFullName != null) metadata['full_name'] = safeFullName;
    if (safePhone != null) metadata['phone'] = safePhone;
    final response = await RateLimiter.instance.run(
      'auth.signUp',
      () => supabase.auth.signUp(
        email: safeEmail,
        password: safePassword,
        data: metadata.isEmpty ? null : metadata,
      ),
    );
    final user = response.user;
    if (user != null) {
      await _ensureProfile(user);
      if (safeFullName != null || safePhone != null) {
        try {
          await updateProfile(
            id: user.id,
            fullName: safeFullName,
            phone: safePhone,
          );
        } catch (_) {
          // Ignore profile update errors (e.g., email confirmation required).
        }
      }
    }
    return response;
  }

  Future<void> signOut() =>
      RateLimiter.instance.run('auth.signOut', () => supabase.auth.signOut());

  Future<Profile?> fetchProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    try {
      // Ensure row exists; ignore errors.
      await ensureProfileExists();
      final response = await RateLimiter.instance.run(
        'profiles.select',
        () => supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle(),
      );
      if (response == null) {
        // Ensure a profile exists if missing
        await _ensureProfile(user);
        final retry = await RateLimiter.instance.run(
          'profiles.select.retry',
          () => supabase
              .from('profiles')
              .select()
              .eq('id', user.id)
              .maybeSingle(),
        );
        if (retry == null) return null;
        return _applyProfileLocale(Profile.fromJson(retry));
      }
      return _applyProfileLocale(Profile.fromJson(response));
    } on PostgrestException catch (e) {
      // If the session expired or schema cache failed, sign out to force a clean state.
      if (e.code == 'PGRST301' || e.message.contains('JWT') || e.message.contains('Expired')) {
        await RateLimiter.instance.run(
          'auth.signOut',
          () => supabase.auth.signOut(),
        );
        return null;
      }
      // Fallback if some columns (lang) are missing in schema cache.
      final response = await RateLimiter.instance.run(
        'profiles.select.fallback',
        () => supabase
            .from('profiles')
            .select(
                'id,email,full_name,avatar_url,role,phone,wilaya,daira,location_lat,location_lng,bio,is_public,is_seller,preferences')
            .eq('id', user.id)
            .maybeSingle(),
      );
      if (response == null) return null;
      return _applyProfileLocale(Profile.fromJson({
        ...response,
        'lang': LocaleService.instance.locale.value?.languageCode ?? 'fr',
        'role': response['role'] ?? 'buyer',
        'is_seller': response['is_seller'] ?? false,
      }));
    }
  }

  Future<void> updateProfile({
    required String id,
    String? fullName,
    String? avatarUrl,
    String? phone,
    String? wilaya,
    String? daira,
    double? locationLat,
    double? locationLng,
    String? bio,
    String? role,
    bool? isPublic,
    String? lang,
    bool? isSeller,
    Map<String, dynamic>? preferences,
  }) async {
    final safeId = InputSanitizer.sanitizeId(id, maxLength: 64);
    final payload = <String, dynamic>{
      'id': safeId,
      // Always keep email to satisfy NOT NULL on upsert.
      'email': supabase.auth.currentUser?.email ?? '',
    };
    final safeFullName =
        InputSanitizer.sanitizeOptionalText(fullName, maxLength: 80);
    final safeAvatar = InputSanitizer.sanitizeUrl(avatarUrl);
    final safePhone = InputSanitizer.sanitizePhone(phone);
    final safeWilaya =
        InputSanitizer.sanitizeOptionalText(wilaya, maxLength: 60);
    final safeDaira =
        InputSanitizer.sanitizeOptionalText(daira, maxLength: 60);
    final safeBio =
        InputSanitizer.sanitizeOptionalText(bio, maxLength: 240, allowNewlines: true);
    final safeRole =
        InputSanitizer.sanitizeOptionalText(role, maxLength: 20);
    final safeLang =
        InputSanitizer.sanitizeOptionalText(lang, maxLength: 8);
    if (safeFullName != null) payload['full_name'] = safeFullName;
    if (safeAvatar != null) payload['avatar_url'] = safeAvatar;
    if (safePhone != null) payload['phone'] = safePhone;
    if (safeWilaya != null) payload['wilaya'] = safeWilaya;
    if (safeDaira != null) payload['daira'] = safeDaira;
    if (locationLat != null) payload['location_lat'] = locationLat;
    if (locationLng != null) payload['location_lng'] = locationLng;
    if (safeBio != null) payload['bio'] = safeBio;
    if (safeRole != null) payload['role'] = safeRole;
    if (isPublic != null) payload['is_public'] = isPublic;
    if (safeLang != null) payload['lang'] = safeLang;
    if (isSeller != null) payload['is_seller'] = isSeller;
    // If caller provided seller flag but no role, align role with seller mode.
    if (safeRole == null && isSeller != null) {
      payload['role'] = isSeller ? 'seller' : 'buyer';
    }
    if (preferences != null) payload['preferences'] = preferences;
    if (payload.length == 1) return; // only id present
    Future<void> attempt(Map<String, dynamic> data) async {
      if (data.length <= 1) return; // only id
      await RateLimiter.instance.run(
        'profiles.upsert',
        () => supabase.from('profiles').upsert(data),
      );
    }

    try {
      await attempt(Map<String, dynamic>.from(payload));
    } on PostgrestException catch (e) {
      // If schema cache misses optional columns (is_seller, lang, daira...), retry without them.
      final fallback = Map<String, dynamic>.from(payload);
      if (e.message.contains('is_seller')) fallback.remove('is_seller');
      if (e.message.contains('lang')) fallback.remove('lang');
      if (e.message.contains('daira')) fallback.remove('daira');
      if (e.message.contains('location_lat')) fallback.remove('location_lat');
      if (e.message.contains('location_lng')) fallback.remove('location_lng');
      await attempt(fallback);
    } catch (_) {
      // last resort: try without lang
      final fallback = Map<String, dynamic>.from(payload)..remove('lang');
      await attempt(fallback);
    }
  }

  Future<void> _ensureProfile(User user) async {
    final existing = await RateLimiter.instance.run(
      'profiles.ensure.select',
      () => supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle(),
    );
    if (existing != null) return;

    await RateLimiter.instance.run(
      'profiles.ensure.insert',
      () => supabase.from('profiles').insert({
            'id': user.id,
            'email': user.email ?? '',
            'full_name': user.userMetadata?['full_name'] as String?,
            'phone': user.userMetadata?['phone'] as String?,
            'is_public': true,
            'lang': LocaleService.instance.locale.value?.languageCode ?? 'fr',
            'role': 'buyer',
            'is_seller': false,
            'daira': null,
            'location_lat': null,
            'location_lng': null,
            'preferences': <String, dynamic>{},
          }),
    );
  }

  /// Public helper to ensure profile row exists (used by UI when missing).
  Future<void> ensureProfilePublic(User user) => _ensureProfile(user);

  /// Upsert profile for current user (idempotent) to avoid "profil introuvable".
  Future<void> ensureProfileExists() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    // Avoid overriding existing seller flag: only insert if missing.
    final existing = await RateLimiter.instance.run(
      'profiles.exists.select',
      () => supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle(),
    );
    if (existing != null) return;
    await RateLimiter.instance.run(
      'profiles.exists.insert',
      () => supabase.from('profiles').insert({
      'id': user.id,
      'email': user.email ?? '',
      'full_name': user.userMetadata?['full_name'] as String?,
      'role': 'buyer',
      'is_public': true,
      'is_seller': false,
      'lang': LocaleService.instance.locale.value?.languageCode ?? 'fr',
      }),
    );
  }

  Future<Profile?> _applyProfileLocale(Profile? profile) async {
    if (profile == null) return null;
    final lang = profile.lang;
    if (lang != null && lang.isNotEmpty) {
      await LocaleService.instance.setLocale(lang);
    }
    return profile;
  }
}
