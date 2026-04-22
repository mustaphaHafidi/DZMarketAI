import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/models/profile.dart';
import 'package:dzmarket/src/services/network_preferences_service.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/utils/public_storage_url_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  User? get currentUser => supabase.auth.currentUser;

  Stream<AuthState> get authChanges => supabase.auth.onAuthStateChange;

  Future<AuthResponse> signIn(String email, String password) async {
    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    late final String safeEmail;
    late final String safePassword;

    try {
      safeEmail = InputSanitizer.sanitizeEmail(email);
    } on FormatException {
      throw FormatException(L10n.trLocale(locale, 'auth.error_invalid_email'));
    }

    try {
      safePassword = InputSanitizer.sanitizePassword(password);
    } on FormatException catch (e) {
      final lower = e.message.toLowerCase();
      if (lower.contains('too short')) {
        throw FormatException(
          L10n.trLocale(locale, 'auth.error_password_too_short'),
        );
      }
      throw FormatException(L10n.trLocale(locale, 'auth.error_login_failed'));
    }

    late final AuthResponse response;
    try {
      response = await RateLimiter.instance.run(
        'auth.signIn',
        () => supabase.auth.signInWithPassword(
          email: safeEmail,
          password: safePassword,
        ),
      );
    } on AuthException catch (e) {
      throw FormatException(_mapSignInAuthError(e, locale));
    } catch (e) {
      throw FormatException(
        _mapGenericAuthError(e, locale, fallbackKey: 'auth.error_login_failed'),
      );
    }

    final user = response.user;
    if (user != null) {
      await _ensureProfile(user);
      final profile = await fetchProfile();
      if (profile?.status == UserStatus.suspended) {
        await signOut();
        throw FormatException(L10n.trLocale(locale, 'auth.account_suspended'));
      }
      if (profile?.status == UserStatus.banned) {
        await signOut();
        throw FormatException(L10n.trLocale(locale, 'auth.account_banned'));
      }
    }
    return response;
  }

  String _mapSignInAuthError(AuthException e, String locale) {
    final message = e.message.toLowerCase();
    if (message.contains('invalid login credentials') ||
        message.contains('invalid_credentials') ||
        message.contains('email or password')) {
      return L10n.trLocale(locale, 'auth.error_invalid_credentials');
    }
    if (message.contains('email not confirmed') ||
        message.contains('email_not_confirmed')) {
      return L10n.trLocale(locale, 'auth.error_email_not_confirmed');
    }
    if (message.contains('too many requests') ||
        message.contains('rate limit')) {
      return L10n.trLocale(locale, 'auth.error_too_many_requests');
    }
    return L10n.trLocale(locale, 'auth.error_login_failed');
  }

  Future<AuthResponse> signUp(
    String email,
    String password, {
    String? fullName,
    String? phone,
    String? locale,
  }) async {
    final resolvedLocale = _normalizeLocale(locale);
    final safeEmail = InputSanitizer.sanitizeEmail(email);
    final safePassword = InputSanitizer.sanitizePassword(password);
    final safeFullName = InputSanitizer.sanitizeOptionalText(
      fullName,
      maxLength: 80,
    );
    final safePhone = InputSanitizer.sanitizePhone(phone);
    final metadata = <String, dynamic>{};
    if (safeFullName != null) metadata['full_name'] = safeFullName;
    if (safePhone != null) metadata['phone'] = safePhone;
    metadata['lang'] = resolvedLocale;
    late final AuthResponse response;
    try {
      response = await RateLimiter.instance.run(
        'auth.signUp',
        () => supabase.auth.signUp(
          email: safeEmail,
          password: safePassword,
          emailRedirectTo: buildEmailRedirectUrl(
            flow: 'signup',
            locale: resolvedLocale,
            next: '/sign-in?confirmed=1',
          ),
          data: metadata.isEmpty ? null : metadata,
        ),
      );
    } on AuthException catch (e) {
      throw FormatException(_mapSignUpAuthError(e, resolvedLocale));
    } catch (e) {
      throw FormatException(
        _mapGenericAuthError(
          e,
          resolvedLocale,
          fallbackKey: 'auth.sign_up.error_failed',
        ),
      );
    }
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

  String _mapSignUpAuthError(AuthException e, String locale) {
    final message = e.message.toLowerCase();
    if (message.contains('user already registered') ||
        message.contains('already registered') ||
        message.contains('already exists') ||
        message.contains('user_already_exists')) {
      return L10n.trLocale(locale, 'auth.sign_up.error_email_exists');
    }
    if (message.contains('password') && message.contains('at least')) {
      return L10n.trLocale(locale, 'auth.error_password_too_short');
    }
    if (message.contains('too many requests') ||
        message.contains('rate limit')) {
      return L10n.trLocale(locale, 'auth.error_too_many_requests');
    }
    return L10n.trLocale(locale, 'auth.sign_up.error_failed');
  }

  String _mapGenericAuthError(
    Object error,
    String locale, {
    required String fallbackKey,
  }) {
    final message = error.toString().toLowerCase();
    final networkHints = <String>[
      'socketexception',
      'clientexception',
      'failed host lookup',
      'connection refused',
      'connection reset',
      'network is unreachable',
      'network unreachable',
      'timed out',
      'timeout',
      '503',
      '502',
      '504',
    ];
    final isNetworkIssue = networkHints.any(message.contains);
    if (isNetworkIssue) {
      return L10n.trLocale(locale, 'auth.error_server_unreachable');
    }
    return L10n.trLocale(locale, fallbackKey);
  }

  Future<void> resendEmailConfirmation(String email, {String? locale}) async {
    final safeEmail = InputSanitizer.sanitizeEmail(email);
    final resolvedLocale = _normalizeLocale(locale);
    await RateLimiter.instance.run(
      'auth.resendConfirmation',
      () => supabase.auth.resend(
        type: OtpType.signup,
        email: safeEmail,
        emailRedirectTo: buildEmailRedirectUrl(
          flow: 'signup',
          locale: resolvedLocale,
          next: '/sign-in?confirmed=1',
        ),
      ),
    );
  }

  Future<void> sendPasswordResetEmail(String email, {String? locale}) async {
    final safeEmail = InputSanitizer.sanitizeEmail(email);
    final resolvedLocale = _normalizeLocale(locale);
    await RateLimiter.instance.run(
      'auth.resetPassword',
      () => supabase.auth.resetPasswordForEmail(
        safeEmail,
        redirectTo: buildEmailRedirectUrl(
          flow: 'recovery',
          locale: resolvedLocale,
          next: '/reset-password',
        ),
      ),
    );
  }

  String buildEmailRedirectUrl({
    required String flow,
    String? locale,
    String? next,
  }) {
    const fallbackBase = 'https://app.dzmarket.pro/auth/callback';
    const configuredBase = String.fromEnvironment(
      'AUTH_REDIRECT_URL',
      defaultValue: fallbackBase,
    );

    Uri? baseUri;
    final fromConfigured = Uri.tryParse(configuredBase);
    if (fromConfigured != null &&
        fromConfigured.hasScheme &&
        fromConfigured.hasAuthority) {
      baseUri = fromConfigured;
    } else if (kIsWeb) {
      final webBase = Uri.base.resolve('/auth/callback');
      if (webBase.hasScheme && webBase.hasAuthority) {
        baseUri = webBase;
      }
    }
    baseUri ??= Uri.parse(fallbackBase);

    final query = <String, String>{...baseUri.queryParameters};
    query['type'] = flow;
    final normalizedLocale = _normalizeLocale(locale);
    query['lang'] = normalizedLocale;
    if (next != null && next.isNotEmpty) {
      query['next'] = next;
    }
    return baseUri.replace(queryParameters: query).toString();
  }

  Future<void> signOut() =>
      RateLimiter.instance.run('auth.signOut', () => supabase.auth.signOut());

  Future<void> requestAccountDeletion({String? reason}) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('login_required');
    }
    final safeReason = InputSanitizer.sanitizeOptionalText(
      reason,
      maxLength: 500,
      allowNewlines: true,
    );
    try {
      await RateLimiter.instance.run(
        'auth.requestAccountDeletion',
        () => supabase.rpc(
          'submit_account_deletion_request',
          params: {if (safeReason != null) 'p_reason': safeReason},
        ),
      );
      return;
    } on PostgrestException catch (error) {
      final missingRpc =
          error.code == 'PGRST202' ||
          error.code == '42883' ||
          error.message.contains('submit_account_deletion_request');
      if (!missingRpc) rethrow;
    }

    await RateLimiter.instance.run(
      'auth.requestAccountDeletion.insert',
      () => supabase.from('account_deletion_requests').insert({
        'user_id': user.id,
        'email': user.email ?? '',
        if (safeReason != null) 'reason': safeReason,
        'status': 'pending',
      }),
    );
  }

  Future<Profile?> fetchProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    try {
      // Ensure row exists; ignore errors.
      await ensureProfileExists();
      final response = await RateLimiter.instance.run(
        'profiles.select',
        () =>
            supabase.from('profiles').select().eq('id', user.id).maybeSingle(),
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
      if (e.code == 'PGRST301' ||
          e.message.contains('JWT') ||
          e.message.contains('Expired')) {
        await RateLimiter.instance.run(
          'auth.signOut',
          () => supabase.auth.signOut(),
        );
        return null;
      }
      // Fallback if some columns (lang) are missing in schema cache.
      Map<String, dynamic>? response;
      try {
        response = await RateLimiter.instance.run(
          'profiles.select.fallback',
          () => supabase
              .from('profiles')
              .select(
                'id,email,full_name,avatar_url,role,status,phone,wilaya,daira,location_lat,location_lng,bio,is_public,is_seller,preferences',
              )
              .eq('id', user.id)
              .maybeSingle(),
        );
      } on PostgrestException catch (fallbackError) {
        if (!fallbackError.message.contains('preferences')) rethrow;
        response = await RateLimiter.instance.run(
          'profiles.select.fallback.legacy',
          () => supabase
              .from('profiles')
              .select(
                'id,email,full_name,avatar_url,role,status,phone,wilaya,daira,location_lat,location_lng,bio,is_public,is_seller',
              )
              .eq('id', user.id)
              .maybeSingle(),
        );
      }
      if (response == null) return null;
      return _applyProfileLocale(
        Profile.fromJson({
          ...response,
          'lang': LocaleService.instance.locale.value?.languageCode ?? 'fr',
          'role': response['role'] ?? 'buyer',
          'status': response['status'] ?? 'active',
          'is_seller': response['is_seller'] ?? false,
          'preferences': response['preferences'] ?? const <String, dynamic>{},
        }),
      );
    }
  }

  Future<void> updateProfile({
    required String id,
    String? fullName,
    String? avatarUrl,
    bool avatarTouched = false,
    String? phone,
    String? wilaya,
    String? daira,
    double? locationLat,
    double? locationLng,
    String? bio,
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
    final safeFullName = InputSanitizer.sanitizeOptionalText(
      fullName,
      maxLength: 80,
    );
    final rawAvatar = InputSanitizer.sanitizeUrl(avatarUrl);
    final safeAvatar = rawAvatar == null
        ? null
        : normalizePublicStorageUrl(rawAvatar);
    final safePhone = InputSanitizer.sanitizePhone(phone);
    final safeWilaya = InputSanitizer.sanitizeOptionalText(
      wilaya,
      maxLength: 60,
    );
    final safeDaira = InputSanitizer.sanitizeOptionalText(daira, maxLength: 60);
    final safeBio = InputSanitizer.sanitizeOptionalText(
      bio,
      maxLength: 240,
      allowNewlines: true,
    );
    final safeLang = InputSanitizer.sanitizeOptionalText(lang, maxLength: 8);
    if (safeFullName != null) payload['full_name'] = safeFullName;
    if (avatarTouched || safeAvatar != null) payload['avatar_url'] = safeAvatar;
    if (safePhone != null) payload['phone'] = safePhone;
    if (safeWilaya != null) payload['wilaya'] = safeWilaya;
    if (safeDaira != null) payload['daira'] = safeDaira;
    if (locationLat != null) payload['location_lat'] = locationLat;
    if (locationLng != null) payload['location_lng'] = locationLng;
    if (safeBio != null) payload['bio'] = safeBio;
    if (isPublic != null) payload['is_public'] = isPublic;
    if (safeLang != null) payload['lang'] = safeLang;
    if (isSeller != null) payload['is_seller'] = isSeller;
    if (preferences != null) payload['preferences'] = preferences;
    if (payload.length == 1) return; // only id present
    Future<bool> attemptUpdate(Map<String, dynamic> data) async {
      if (data.length <= 1) return true; // only id
      final updatePayload = Map<String, dynamic>.from(data)..remove('id');
      if (updatePayload.isEmpty) return true;
      final response = await RateLimiter.instance.run(
        'profiles.update',
        () => supabase
            .from('profiles')
            .update(updatePayload)
            .eq('id', safeId)
            .select('id')
            .maybeSingle(),
      );
      return response != null;
    }

    Future<void> attemptInsert(Map<String, dynamic> data) async {
      if (data.length <= 1) return; // only id
      await RateLimiter.instance.run(
        'profiles.insert',
        () => supabase.from('profiles').insert(data),
      );
    }

    Future<void> attempt(Map<String, dynamic> data) async {
      final updated = await attemptUpdate(data);
      if (updated) return;
      await attemptInsert(data);
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
      if (e.message.contains('preferences')) fallback.remove('preferences');
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
    await NetworkPreferencesService.instance.applyProfilePreferences(
      profile.preferences,
    );
    return profile;
  }

  String _normalizeLocale(String? raw) {
    final candidate =
        (raw ?? LocaleService.instance.locale.value?.languageCode ?? 'fr')
            .toLowerCase();
    if (candidate == 'ar' ||
        candidate.startsWith('ar_') ||
        candidate.startsWith('ar-')) {
      return 'ar';
    }
    return 'fr';
  }
}
