import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthCallbackPage extends StatefulWidget {
  const AuthCallbackPage({super.key, required this.uri});

  final Uri uri;

  @override
  State<AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends State<AuthCallbackPage> {
  bool _loading = true;
  String? _error;
  String _flow = '';
  String _target = '/';

  String _t(
    String key, {
    required String fallback,
    Map<String, String>? params,
  }) {
    return L10n.tr(context, key, fallback: fallback, params: params);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleCallback();
    });
  }

  OtpType? _otpTypeFromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'signup':
        return OtpType.signup;
      case 'recovery':
        return OtpType.recovery;
      case 'magiclink':
      case 'magic_link':
        return OtpType.magiclink;
      case 'invite':
        return OtpType.invite;
      case 'email_change':
      case 'emailchange':
        return OtpType.emailChange;
      default:
        return null;
    }
  }

  String _safeRedirectTarget(String? raw) {
    if (raw == null || raw.isEmpty) return '/';
    final decoded = Uri.decodeComponent(raw);
    final target = Uri.tryParse(decoded);
    if (target == null) return '/';
    if (target.hasScheme || target.hasAuthority) return '/';
    if (!target.toString().startsWith('/')) return '/';
    return target.toString();
  }

  Map<String, String> _extractAuthParams(Uri uri) {
    final merged = <String, String>{...uri.queryParameters};
    final fragment = uri.fragment;
    if (fragment.isEmpty) return merged;
    Map<String, String> parsedFragment = const {};
    try {
      parsedFragment = Uri.splitQueryString(fragment);
    } catch (_) {
      final queryIndex = fragment.indexOf('?');
      if (queryIndex >= 0 && queryIndex + 1 < fragment.length) {
        final afterQuestionMark = fragment.substring(queryIndex + 1);
        try {
          parsedFragment = Uri.splitQueryString(afterQuestionMark);
        } catch (_) {
          parsedFragment = const {};
        }
      }
    }
    merged.addAll(parsedFragment);
    return merged;
  }

  Future<void> _handleCallback() async {
    final auth = Supabase.instance.client.auth;
    final uri = widget.uri;
    final qp = _extractAuthParams(uri);

    final lang = qp['lang'];
    if (lang != null && lang.isNotEmpty) {
      await LocaleService.instance.setLocale(lang);
    }

    _flow = (qp['type'] ?? '').toLowerCase();
    final explicitTarget = _safeRedirectTarget(qp['next'] ?? qp['from']);
    _target = explicitTarget == '/'
        ? switch (_flow) {
            'recovery' => '/reset-password',
            'signup' => '/sign-in?confirmed=1',
            _ => '/',
          }
        : explicitTarget;

    final errorDescription =
        qp['error_description'] ?? qp['error'] ?? qp['message'];
    if (errorDescription != null && errorDescription.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorDescription;
      });
      return;
    }

    try {
      final code = qp['code'];
      final tokenHash = qp['token_hash'];
      final token = qp['token'];
      final refreshToken = qp['refresh_token'];
      final accessToken = qp['access_token'];
      final type = qp['type'];

      final fromUrlHandled = await _tryGetSessionFromUrl(auth, uri);

      if (!fromUrlHandled && code != null && code.isNotEmpty) {
        await auth.exchangeCodeForSession(code);
      } else if (!fromUrlHandled && tokenHash != null && tokenHash.isNotEmpty) {
        final otpType = _otpTypeFromString(type);
        if (otpType == null) {
          throw AuthException(
            _t(
              'auth.callback.error_invalid',
              fallback: 'Ce lien de verification est invalide.',
            ),
          );
        }
        await auth.verifyOTP(type: otpType, tokenHash: tokenHash);
      } else if (!fromUrlHandled &&
          token != null &&
          token.isNotEmpty &&
          (type == 'signup' || type == 'recovery')) {
        final otpType = _otpTypeFromString(type);
        if (otpType != null) {
          await auth.verifyOTP(type: otpType, tokenHash: token);
        }
      } else if (!fromUrlHandled &&
          refreshToken != null &&
          refreshToken.isNotEmpty) {
        await auth.setSession(refreshToken);
      } else if (!fromUrlHandled &&
          refreshToken == null &&
          accessToken != null &&
          accessToken.isNotEmpty &&
          auth.currentSession != null) {
        // Session may already be restored by Supabase SDK on web.
      } else if (auth.currentSession == null) {
        throw AuthException(
          _t(
            'auth.callback.error_invalid',
            fallback: 'Ce lien de verification est invalide.',
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _mapAuthException(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t(
          'auth.callback.generic_error',
          fallback: 'Le lien de validation est invalide ou expire.',
        );
      });
    }
  }

  Future<bool> _tryGetSessionFromUrl(GoTrueClient auth, Uri uri) async {
    try {
      await auth.getSessionFromUrl(uri);
      return true;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      final missingToken =
          msg.contains('no code detected') ||
          msg.contains('no access_token detected') ||
          msg.contains('no refresh_token detected');
      if (missingToken) return false;
      rethrow;
    } catch (_) {
      return false;
    }
  }

  String _mapAuthException(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('expired') || msg.contains('otp_expired')) {
      return _t(
        'auth.callback.error_expired',
        fallback: 'Ce lien a expire. Demandez un nouveau lien.',
      );
    }
    if (msg.contains('network') ||
        msg.contains('timeout') ||
        msg.contains('socket')) {
      return _t(
        'auth.error_server_unreachable',
        fallback:
            'Connexion au serveur impossible pour le moment. Reessayez dans quelques instants.',
      );
    }
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    final successMessage = switch (_flow) {
      'signup' => _t(
        'auth.callback.signup_success',
        fallback:
            'Adresse email confirmee avec succes. Vous pouvez vous connecter.',
      ),
      'recovery' => _t(
        'auth.callback.recovery_success',
        fallback:
            'Lien valide. Vous pouvez maintenant definir un nouveau mot de passe.',
      ),
      _ => _t('auth.callback.success', fallback: 'Adresse email validee.'),
    };
    final ctaLabel = switch (_flow) {
      'recovery' => _t(
        'auth.callback.open_reset',
        fallback: 'Definir un nouveau mot de passe',
      ),
      'signup' => _t(
        'auth.callback.open_sign_in',
        fallback: 'Aller a la connexion',
      ),
      _ => _t('auth.callback.open_app', fallback: 'Continuer'),
    };

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading)
                      const CircularProgressIndicator()
                    else if (_error == null)
                      Icon(
                        Icons.check_circle_outline,
                        size: 36,
                        color: Colors.green.shade700,
                      )
                    else
                      Icon(
                        Icons.error_outline,
                        size: 36,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    if (_loading) const SizedBox(height: 16),
                    Text(
                      _loading
                          ? _t(
                              'auth.callback.processing',
                              fallback: 'Validation de votre lien en cours...',
                            )
                          : (_error ?? successMessage),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (!_loading) ...[
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () =>
                            context.go(_error == null ? _target : '/sign-in'),
                        child: Text(
                          _error == null
                              ? ctaLabel
                              : _t(
                                  'auth.sign_in.cta',
                                  fallback: 'Se connecter',
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
