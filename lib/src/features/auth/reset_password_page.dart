import 'dart:async';

import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _status;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (!mounted) return;
      if (event.event == AuthChangeEvent.passwordRecovery ||
          event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.signedOut) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String _t(
    String key, {
    required String fallback,
    Map<String, String>? params,
  }) {
    return L10n.tr(context, key, fallback: fallback, params: params);
  }

  Future<void> _sendResetEmail() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });

    try {
      final email = InputSanitizer.sanitizeEmail(
        _emailController.text.trim().toLowerCase(),
      );
      await AuthService.instance.sendPasswordResetEmail(
        email,
        locale: LocaleService.instance.locale.value?.languageCode,
      );
      if (!mounted) return;
      setState(() {
        _status = _t(
          'auth.reset_password.email_sent',
          fallback:
              "Si l'email existe, un lien de reinitialisation vient d'etre envoye.",
        );
      });
    } on FormatException catch (e) {
      setState(() {
        _error = e.message;
      });
    } on AuthException catch (e) {
      setState(() {
        _error = _mapAuthError(e);
      });
    } catch (e) {
      setState(() {
        _error = _mapErrorString(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _updatePassword() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });

    try {
      final password = InputSanitizer.sanitizePassword(
        _passwordController.text,
      );
      final confirm = InputSanitizer.sanitizePassword(_confirmController.text);
      if (password != confirm) {
        throw FormatException(
          _t(
            'auth.reset_password.mismatch',
            fallback: 'Les mots de passe ne correspondent pas.',
          ),
        );
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );

      if (!mounted) return;
      setState(() {
        _status = _t(
          'auth.reset_password.success',
          fallback: 'Mot de passe mis a jour avec succes.',
        );
      });
    } on FormatException catch (e) {
      setState(() {
        _error = e.message;
      });
    } on AuthException catch (e) {
      setState(() {
        _error = _mapAuthError(e);
      });
    } catch (e) {
      setState(() {
        _error = _mapErrorString(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _mapAuthError(AuthException e) {
    final message = e.message.toLowerCase();
    if (message.contains('email address') && message.contains('invalid')) {
      return _t(
        'auth.reset_password.email_invalid_provider',
        fallback:
            'Email invalide ou envoi desactive. Verifiez la configuration SMTP.',
      );
    }
    if (message.contains('smtp') || message.contains('mail')) {
      return _t(
        'auth.reset_password.smtp_required',
        fallback: 'Envoi email non configure. Verifiez la configuration SMTP.',
      );
    }
    if (_looksLikeNetworkError(message)) {
      return _t(
        'auth.error_server_unreachable',
        fallback:
            'Connexion au serveur impossible pour le moment. Verifiez internet puis reessayez.',
      );
    }
    return e.message;
  }

  String _mapErrorString(String message) {
    final lowered = message.toLowerCase();
    if (_looksLikeNetworkError(lowered)) {
      return _t(
        'auth.error_server_unreachable',
        fallback:
            'Connexion au serveur impossible pour le moment. Verifiez internet puis reessayez.',
      );
    }
    return _t(
      'auth.reset_password.generic_error',
      fallback: 'Action impossible pour le moment. Reessayez.',
    );
  }

  bool _looksLikeNetworkError(String message) {
    final hints = <String>[
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
    return hints.any(message.contains);
  }

  @override
  Widget build(BuildContext context) {
    final hasSession = Supabase.instance.client.auth.currentSession != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t(
            'auth.reset_password.title',
            fallback: 'Reinitialiser le mot de passe',
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    hasSession
                        ? _t(
                            'auth.callback.recovery_success',
                            fallback:
                                'Lien valide. Vous pouvez maintenant definir un nouveau mot de passe.',
                          )
                        : _t(
                            'auth.reset_password.subtitle',
                            fallback:
                                'Nous envoyons un lien de reinitialisation par email.',
                          ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (!hasSession) ...[
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: _t('auth.email', fallback: 'Email'),
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loading ? null : _sendResetEmail,
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _t(
                                'auth.reset_password.send',
                                fallback: 'Envoyer le lien',
                              ),
                            ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _t(
                          'auth.reset_password.new_password',
                          fallback: 'Nouveau mot de passe',
                        ),
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _t(
                          'auth.reset_password.confirm_password',
                          fallback: 'Confirmer le mot de passe',
                        ),
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loading ? null : _updatePassword,
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _t(
                                'auth.reset_password.update',
                                fallback: 'Mettre a jour',
                              ),
                            ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _status!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.green.shade700),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go('/sign-in'),
                    child: Text(
                      _t('auth.sign_in.cta', fallback: 'Se connecter'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
