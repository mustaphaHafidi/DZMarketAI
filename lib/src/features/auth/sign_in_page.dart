import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  bool _initializedFromQuery = false;
  bool _canResendConfirmation = false;
  String? _error;
  String? _status;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializedFromQuery) return;
    _initializedFromQuery = true;

    final query = GoRouterState.of(context).uri.queryParameters;
    final email = query['email'];
    if (email != null && email.isNotEmpty) {
      _emailController.text = email;
    }
    if (query['confirmed'] == '1') {
      _status = _t(
        'auth.sign_in.email_confirmed',
        fallback: 'Email confirme. Vous pouvez maintenant vous connecter.',
      );
    } else if (query['check_email'] == '1') {
      _status = _t(
        'auth.sign_in.check_email',
        fallback: 'Verifiez votre boite email pour confirmer votre compte.',
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _t(
    String key, {
    required String fallback,
    Map<String, String>? params,
  }) {
    return L10n.tr(context, key, fallback: fallback, params: params);
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _error = _t(
          'auth.error_email_required',
          fallback: 'Veuillez saisir votre email.',
        );
      });
      return;
    }
    if (password.isEmpty) {
      setState(() {
        _error = _t(
          'auth.error_password_required',
          fallback: 'Veuillez saisir votre mot de passe.',
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = null;
      _canResendConfirmation = false;
    });
    try {
      await AuthService.instance.signIn(email, password);
      if (!mounted) return;
      final from = GoRouterState.of(context).uri.queryParameters['from'];
      if (from != null && from.isNotEmpty) {
        final target = Uri.tryParse(from);
        context.go(target?.toString() ?? '/');
      } else {
        context.go('/');
      }
    } on FormatException catch (e) {
      final message = e.message;
      setState(() {
        _error = message;
        _canResendConfirmation = _isEmailNotConfirmed(message);
      });
    } on AuthException catch (e) {
      final message = e.message;
      setState(() {
        _error = message;
        _canResendConfirmation = _isEmailNotConfirmed(message);
      });
    } catch (e) {
      setState(() {
        _error = _mapUiError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  bool _isEmailNotConfirmed(String message) {
    final localized = _t(
      'auth.error_email_not_confirmed',
      fallback: 'Email non confirme. Verifiez votre boite mail.',
    );
    return message == localized ||
        message.toLowerCase().contains('email not confirmed') ||
        message.toLowerCase().contains('email_not_confirmed');
  }

  Future<void> _resendConfirmation() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _error = _t(
          'auth.error_email_required',
          fallback: 'Veuillez saisir votre email.',
        );
      });
      return;
    }

    setState(() {
      _resending = true;
      _error = null;
      _status = null;
    });

    try {
      await AuthService.instance.resendEmailConfirmation(
        email,
        locale: LocaleService.instance.locale.value?.languageCode,
      );
      if (!mounted) return;
      setState(() {
        _status = _t(
          'auth.sign_in.resend_sent',
          fallback: 'Email de confirmation renvoye a {email}.',
          params: {'email': email},
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mapUiError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _resending = false;
        });
      }
    }
  }

  Future<void> _setLocale(String code) async {
    await LocaleService.instance.setLocale(code);
    if (mounted) setState(() {});
  }

  String _mapUiError(Object error) {
    final message = error.toString().toLowerCase();
    final networkHints = <String>[
      'socketexception',
      'failed host lookup',
      'connection refused',
      'connection reset',
      'network is unreachable',
      'network unreachable',
      'clientexception',
      'timed out',
      'timeout',
      '502',
      '503',
      '504',
    ];
    if (networkHints.any(message.contains)) {
      return _t(
        'auth.error_server_unreachable',
        fallback:
            'Connexion au serveur impossible pour le moment. Verifiez internet puis reessayez.',
      );
    }
    return _t(
      'auth.error_login_failed',
      fallback: 'Connexion impossible. Reessayez.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'logos/logo_mark_ui.png',
                      height: 124,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'DZMarket',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(
                      'auth.brand.tagline',
                      fallback: 'Vendez, expediez, suivez - simplement.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => _setLocale('fr'),
                        child: Text(
                          _t('profile.lang_fr', fallback: 'Francais'),
                          style: TextStyle(
                            fontWeight: lang == 'fr'
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      const Text('|'),
                      TextButton(
                        onPressed: () => _setLocale('ar'),
                        child: Text(
                          _t('profile.lang_ar', fallback: 'Arabe (Algerie)'),
                          style: TextStyle(
                            fontWeight: lang == 'ar'
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _t(
                      'auth.sign_in.subtitle',
                      fallback: 'Connecte-toi pour acheter et vendre',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(
                      'auth.email_only_note',
                      fallback: 'Connexion par email uniquement (SMS bientot)',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: _t('auth.email', fallback: 'Email'),
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: _t(
                                'auth.password',
                                fallback: 'Mot de passe',
                              ),
                              prefixIcon: const Icon(Icons.lock_outline),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => context.go('/reset-password'),
                              child: Text(
                                _t(
                                  'auth.forgot_password',
                                  fallback: 'Mot de passe oublie ?',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_error != null)
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          if (_status != null)
                            Text(
                              _status!,
                              style: TextStyle(color: Colors.green.shade700),
                            ),
                          if (_canResendConfirmation)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: (_loading || _resending)
                                    ? null
                                    : _resendConfirmation,
                                child: Text(
                                  _resending
                                      ? _t(
                                          'auth.sign_in.resending',
                                          fallback: 'Envoi en cours...',
                                        )
                                      : _t(
                                          'auth.sign_in.resend_confirmation',
                                          fallback:
                                              "Renvoyer l'email de confirmation",
                                        ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loading ? null : _signIn,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _t(
                                      'auth.sign_in.cta',
                                      fallback: 'Se connecter',
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => context.go('/sign-up'),
                            child: Text(
                              _t(
                                'auth.sign_in.no_account',
                                fallback: 'Pas de compte ? Cree-le',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => context.push('/legal/privacy'),
                        child: Text(
                          _t(
                            'legal.privacy.title',
                            fallback: 'Politique de confidentialite',
                          ),
                        ),
                      ),
                      const Text('|'),
                      TextButton(
                        onPressed: () => context.push('/legal/terms'),
                        child: Text(
                          _t(
                            'legal.terms.title',
                            fallback: "Conditions d'utilisation",
                          ),
                        ),
                      ),
                      const Text('|'),
                      TextButton(
                        onPressed: () => context.push('/legal/imprint'),
                        child: Text(
                          _t(
                            'legal.imprint.title',
                            fallback: 'Mentions legales',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
