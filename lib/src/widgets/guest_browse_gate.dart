import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/utils/ios_public_browse_policy.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GuestBrowseGate extends StatefulWidget {
  const GuestBrowseGate({
    super.key,
    required this.child,
    required this.returnPath,
  });

  final Widget child;
  final String returnPath;

  @override
  State<GuestBrowseGate> createState() => _GuestBrowseGateState();
}

class _GuestBrowseGateState extends State<GuestBrowseGate> {
  static const _prefsKey = 'ios_guest_browse_terms_ack.v1';

  bool _loading = true;
  bool _accepted = false;
  bool _agreeToTerms = false;

  bool get _shouldGate {
    return supabase.auth.currentSession == null && allowsIosAnonymousBrowse();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_shouldGate) {
      if (!mounted) return;
      setState(() {
        _accepted = true;
        _loading = false;
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(_prefsKey) ?? false;
    if (!mounted) return;
    setState(() {
      _accepted = accepted;
      _loading = false;
      _agreeToTerms = accepted;
    });
  }

  Future<void> _continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
    if (!mounted) return;
    setState(() {
      _accepted = true;
      _agreeToTerms = true;
    });
  }

  void _goToSignIn() {
    final from = Uri.encodeComponent(widget.returnPath);
    context.go('/sign-in?from=$from');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_shouldGate || _accepted) {
      return _loading && _shouldGate
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : widget.child;
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.storefront_outlined,
                        size: 36,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        L10n.tr(
                          context,
                          'guest_browse.title',
                          fallback: 'Parcourir DZMarket sans compte',
                        ),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        L10n.tr(
                          context,
                          'guest_browse.body',
                          fallback:
                              'Vous pouvez consulter les annonces sans compte sur iPhone et iPad. La connexion reste requise pour discuter, acheter, ajouter aux favoris et gérer votre profil.',
                        ),
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton(
                            onPressed: () => context.push('/legal/terms'),
                            child: Text(
                              L10n.tr(
                                context,
                                'guest_browse.terms',
                                fallback: 'Conditions d\'utilisation',
                              ),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => context.push('/legal/privacy'),
                            child: Text(
                              L10n.tr(
                                context,
                                'guest_browse.privacy',
                                fallback: 'Politique de confidentialité',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _agreeToTerms,
                        onChanged: (value) {
                          setState(() => _agreeToTerms = value ?? false);
                        },
                        title: Text(
                          L10n.tr(
                            context,
                            'guest_browse.agree',
                            fallback:
                                'J\'ai lu les conditions d\'utilisation et la politique de confidentialité.',
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _agreeToTerms ? _continueAsGuest : null,
                          child: Text(
                            L10n.tr(
                              context,
                              'guest_browse.continue',
                              fallback: 'Continuer sans compte',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _goToSignIn,
                          child: Text(
                            L10n.tr(
                              context,
                              'guest_browse.sign_in',
                              fallback: 'Se connecter',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
