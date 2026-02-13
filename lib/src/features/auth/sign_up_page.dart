import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _setLocale(String code) async {
    await LocaleService.instance.setLocale(code);
    if (mounted) setState(() {});
  }

  Future<void> _signUp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = InputSanitizer.sanitizeEmail(_emailController.text);
      final password = InputSanitizer.sanitizePassword(_passwordController.text);
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
          throw FormatException(L10n.tr(context, 'auth.phone_invalid'));
        }
      }
      await AuthService.instance.signUp(
        email,
        password,
        fullName: fullName,
        phone: phone,
      );
      if (!mounted) return;
      final from = GoRouterState.of(context).uri.queryParameters['from'];
      if (from != null && from.isNotEmpty) {
        final target = Uri.tryParse(from);
        context.go(target?.toString() ?? '/');
      } else {
        context.go('/');
      }
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                  SvgPicture.asset(
                    'assets/branding/dzmarket_logo_ui.svg',
                    height: 72,
                    width: 72,
                    fit: BoxFit.contain,
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
                    L10n.tr(context, 'auth.brand.tagline'),
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
                          L10n.tr(context, 'profile.lang_fr'),
                          style: TextStyle(
                            fontWeight:
                                lang == 'fr' ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      const Text('•'),
                      TextButton(
                        onPressed: () => _setLocale('ar'),
                        child: Text(
                          L10n.tr(context, 'profile.lang_ar'),
                          style: TextStyle(
                            fontWeight:
                                lang == 'ar' ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    L10n.tr(context, 'auth.sign_up.subtitle'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    L10n.tr(context, 'auth.email_only_note'),
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
                            decoration: InputDecoration(
                              labelText: L10n.tr(context, 'auth.full_name'),
                              prefixIcon: const Icon(Icons.person_outline),
                              helperText: L10n.tr(context, 'common.optional'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: L10n.tr(context, 'auth.email'),
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: L10n.tr(context, 'auth.phone_optional'),
                              helperText: L10n.tr(context, 'auth.phone_helper'),
                              prefixIcon: const Icon(Icons.phone_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: L10n.tr(context, 'auth.password'),
                              prefixIcon: const Icon(Icons.lock_outline),
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
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loading ? null : _signUp,
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
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(L10n.tr(context, 'auth.sign_up.cta')),
                          ),
                          TextButton(
                            onPressed:
                                _loading ? null : () => context.go('/sign-in'),
                            child:
                                Text(L10n.tr(context, 'auth.sign_up.have_account')),
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
                        child: Text(L10n.tr(context, 'legal.privacy.title')),
                      ),
                      const Text('·'),
                      TextButton(
                        onPressed: () => context.push('/legal/terms'),
                        child: Text(L10n.tr(context, 'legal.terms.title')),
                      ),
                      const Text('·'),
                      TextButton(
                        onPressed: () => context.push('/legal/imprint'),
                        child: Text(L10n.tr(context, 'legal.imprint.title')),
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
