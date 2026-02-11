import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
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
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() {
        _status = L10n.tr(context, 'auth.reset_password.email_sent');
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on AuthException catch (e) {
      setState(() => _error = _mapAuthError(e));
    } catch (e) {
      setState(() => _error = _mapErrorString(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updatePassword() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });
    try {
      final password = InputSanitizer.sanitizePassword(_passwordController.text);
      final confirm = InputSanitizer.sanitizePassword(_confirmController.text);
      if (password != confirm) {
        throw FormatException(L10n.tr(context, 'auth.reset_password.mismatch'));
      }
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (!mounted) return;
      setState(() {
        _status = L10n.tr(context, 'auth.reset_password.success');
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on AuthException catch (e) {
      setState(() => _error = _mapAuthError(e));
    } catch (e) {
      setState(() => _error = _mapErrorString(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapAuthError(AuthException e) {
    final message = e.message.toLowerCase();
    if (message.contains('email address') && message.contains('invalid')) {
      return L10n.tr(context, 'auth.reset_password.email_invalid_provider');
    }
    if (message.contains('smtp') || message.contains('mail')) {
      return L10n.tr(context, 'auth.reset_password.smtp_required');
    }
    return e.message;
  }

  String _mapErrorString(String message) {
    final lowered = message.toLowerCase();
    if (lowered.contains('email address') && lowered.contains('invalid')) {
      return L10n.tr(context, 'auth.reset_password.email_invalid_provider');
    }
    if (lowered.contains('smtp') || lowered.contains('mail')) {
      return L10n.tr(context, 'auth.reset_password.smtp_required');
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    final hasSession = session != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr(context, 'auth.reset_password.title')),
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
                    L10n.tr(context, 'auth.reset_password.subtitle'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (!hasSession) ...[
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: L10n.tr(context, 'auth.email'),
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
                          : Text(L10n.tr(context, 'auth.reset_password.send')),
                    ),
                  ] else ...[
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText:
                            L10n.tr(context, 'auth.reset_password.new_password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText:
                            L10n.tr(context, 'auth.reset_password.confirm_password'),
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
                          : Text(L10n.tr(context, 'auth.reset_password.update')),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
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
                    child: Text(L10n.tr(context, 'auth.sign_in.cta')),
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
