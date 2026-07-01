import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _loading = false;
  bool _existingAccountError = false;
  String? _error;
  String? _status;
  String? _signupEmail;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  String _t(
    String key, {
    required String fallback,
    Map<String, String>? params,
  }) {
    final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
    return L10n.trLocale(locale, key, fallback: fallback, params: params);
  }

  Future<void> _setLocale(String code) async {
    await LocaleService.instance.setLocale(code);
  }

  Future<void> _signUp() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
      _existingAccountError = false;
    });
    try {
      final rawEmail = _emailController.text.trim();
      if (rawEmail.isEmpty) {
        throw FormatException(
          _t(
            'auth.error_email_required',
            fallback: 'Veuillez saisir votre email.',
          ),
        );
      }
      final email = InputSanitizer.sanitizeEmail(rawEmail);
      final rawPassword = _passwordController.text;
      if (rawPassword.trim().isEmpty) {
        throw FormatException(
          _t(
            'auth.error_password_required',
            fallback: 'Veuillez saisir votre mot de passe.',
          ),
        );
      }
      final password = InputSanitizer.sanitizePassword(rawPassword);
      final fullName = InputSanitizer.sanitizeOptionalText(
        _nameController.text,
        maxLength: 80,
      );
      String? phone;
      final rawPhone = _phoneController.text.trim();
      if (rawPhone.isNotEmpty) {
        try {
          phone = InputSanitizer.sanitizePhone(rawPhone);
        } on FormatException {
          throw FormatException(
            _t('auth.phone_invalid', fallback: 'Numero de telephone invalide.'),
          );
        }
      }
      final response = await AuthService.instance.signUp(
        email,
        password,
        fullName: fullName,
        phone: phone,
        locale: LocaleService.instance.locale.value?.languageCode,
      );
      if (!mounted) return;
      if (response.session != null) {
        final from = GoRouterState.of(context).uri.queryParameters['from'];
        if (from != null && from.isNotEmpty) {
          final target = Uri.tryParse(from);
          context.go(target?.toString() ?? '/');
        } else {
          context.go('/');
        }
        return;
      }
      setState(() {
        _signupEmail = email;
        _passwordController.clear();
        _status = _t(
          'auth.sign_up.email_sent',
          fallback:
              'Compte cree. Un email de confirmation a ete envoye a {email}.',
          params: {'email': email},
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'auth.sign_up.toast_thanks',
              fallback:
                  'Merci pour votre inscription sur DZMarket. Verifiez votre email pour confirmer votre compte.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    } on FormatException catch (e) {
      final message = _mapFormatError(e);
      setState(() {
        _error = message;
        _existingAccountError = _isExistingAccountError(message);
      });
    } on AuthException catch (e) {
      final message = e.message;
      setState(() {
        _error = message;
        _existingAccountError = _isExistingAccountError(message);
      });
    } catch (e) {
      setState(() => _error = _mapUiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isExistingAccountError(String message) {
    final localized = _t(
      'auth.sign_up.error_email_exists',
      fallback:
          'Cet email est deja utilise. Connectez-vous ou reinitialisez votre mot de passe.',
    );
    return message == localized ||
        message.toLowerCase().contains('already registered') ||
        message.toLowerCase().contains('already exists');
  }

  String _mapFormatError(FormatException error) {
    switch (error.message) {
      case 'Invalid email.':
        return _t('auth.error_invalid_email', fallback: 'Email invalide.');
      case 'Password too short.':
        return _t(
          'auth.error_password_too_short',
          fallback: 'Mot de passe trop court (minimum 8 caracteres).',
        );
      default:
        return error.message;
    }
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
      'auth.sign_up.error_failed',
      fallback: 'Impossible de creer le compte pour le moment. Reessayez.',
    );
  }

  void _goToSignInWithEmail(String email) {
    final query = Uri(path: '/sign-in', queryParameters: {'email': email});
    context.go(query.toString());
  }

  Future<void> _signInWithGoogle() async {
    if (!AuthService.instance.supportsGoogleSignIn) return;
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
      _existingAccountError = false;
    });
    try {
      final from = GoRouterState.of(context).uri.queryParameters['from'];
      await AuthService.instance.signInWithGoogle(nextPath: from);
      if (!mounted || kIsWeb) return;
      final target = (from != null && from.isNotEmpty)
          ? Uri.tryParse(from)
          : null;
      context.go(target?.toString() ?? '/');
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mapUiError(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleService.instance.locale,
      builder: (context, locale, _) {
        final lang = locale?.languageCode ?? 'fr';
        final isRtl = lang == 'ar';
        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
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
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
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
                                _t(
                                  'profile.lang_ar',
                                  fallback: 'Arabe (Algerie)',
                                ),
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
                            'auth.sign_up.subtitle',
                            fallback: 'Cree ton compte pour acheter et vendre',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _t(
                            'auth.email_only_note',
                            fallback:
                                'Connexion par email uniquement (SMS bientot)',
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
                                  controller: _nameController,
                                  focusNode: _nameFocusNode,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      _emailFocusNode.requestFocus(),
                                  decoration: InputDecoration(
                                    labelText: _t(
                                      'auth.full_name',
                                      fallback: 'Nom complet',
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                    helperText: _t(
                                      'common.optional',
                                      fallback: 'Optionnel',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _emailController,
                                  focusNode: _emailFocusNode,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      _phoneFocusNode.requestFocus(),
                                  textAlign: TextAlign.left,
                                  decoration: InputDecoration(
                                    labelText: _t(
                                      'auth.email',
                                      fallback: 'Email',
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.email_outlined,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _phoneController,
                                  focusNode: _phoneFocusNode,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      _passwordFocusNode.requestFocus(),
                                  decoration: InputDecoration(
                                    labelText: _t(
                                      'auth.phone_optional',
                                      fallback: 'Telephone (optionnel)',
                                    ),
                                    helperText: _t(
                                      'auth.phone_helper',
                                      fallback:
                                          'Utilise pour les notifications plus tard',
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.phone_outlined,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocusNode,
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) {
                                    if (!_loading) {
                                      _signUp();
                                    }
                                  },
                                  decoration: InputDecoration(
                                    labelText: _t(
                                      'auth.password',
                                      fallback: 'Mot de passe',
                                    ),
                                    prefixIcon: const Icon(Icons.lock_outline),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_error != null)
                                  Text(
                                    _error!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                if (_existingAccountError)
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: _loading
                                            ? null
                                            : () => _goToSignInWithEmail(
                                                _emailController.text.trim(),
                                              ),
                                        child: Text(
                                          _t(
                                            'auth.sign_in.cta',
                                            fallback: 'Se connecter',
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _loading
                                            ? null
                                            : () =>
                                                  context.go('/reset-password'),
                                        child: Text(
                                          _t(
                                            'auth.forgot_password',
                                            fallback: 'Mot de passe oublie ?',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (_status != null)
                                  Text(
                                    _status!,
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: _loading ? null : _signUp,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
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
                                            'auth.sign_up.cta',
                                            fallback: 'Creer un compte',
                                          ),
                                        ),
                                ),
                                if (AuthService.instance.supportsGoogleSignIn)
                                  OutlinedButton.icon(
                                    onPressed: _loading
                                        ? null
                                        : _signInWithGoogle,
                                    icon: const Icon(Icons.login),
                                    label: Text(
                                      _t(
                                        'auth.google_cta',
                                        fallback: 'Continuer avec Google',
                                      ),
                                    ),
                                  ),
                                TextButton(
                                  onPressed: _loading
                                      ? null
                                      : () {
                                          final email = _signupEmail;
                                          if (email == null || email.isEmpty) {
                                            context.go('/sign-in');
                                            return;
                                          }
                                          final query = Uri(
                                            path: '/sign-in',
                                            queryParameters: {
                                              'email': email,
                                              'check_email': '1',
                                            },
                                          );
                                          context.go(query.toString());
                                        },
                                  child: Text(
                                    _t(
                                      'auth.sign_up.have_account',
                                      fallback: 'Deja inscrit ? Se connecter',
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
          ),
        );
      },
    );
  }
}
