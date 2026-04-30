import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class WebMarketingLandingPage extends StatelessWidget {
  const WebMarketingLandingPage({super.key});

  static final Uri _webAppUrl = Uri.parse('https://app.dzmarket.pro/');
  static final Uri _signUpUrl = Uri.parse('https://app.dzmarket.pro/sign-up');
  static final Uri _appStoreUrl = Uri.parse(
    'https://apps.apple.com/dz/app/dzmarket/id6760047432',
  );
  static final Uri _googlePlayUrl = Uri.parse(
    'https://play.google.com/store/apps/details?id=com.dzmarket.app',
  );
  static final Uri _facebookUrl = Uri.parse(
    'https://www.facebook.com/DZMarketpro',
  );
  static final Uri _youtubeUrl = Uri.parse(
    'https://www.youtube.com/@DZMarketpro',
  );

  Future<void> _open(Uri uri, {bool external = false}) async {
    await launchUrl(uri, webOnlyWindowName: external ? '_blank' : '_self');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAF5),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _Header(
                onOpenApp: () => _open(_webAppUrl),
                onSignUp: () => _open(_signUpUrl),
              ),
              _SectionShell(
                child: _HeroSection(
                  onOpenApp: () => _open(_webAppUrl),
                  onAppStore: () => _open(_appStoreUrl, external: true),
                  onGooglePlay: () => _open(_googlePlayUrl, external: true),
                ),
              ),
              const _SectionShell(child: _ProofStrip()),
              const _SectionShell(child: _UseCasesSection()),
              const _SectionShell(child: _ScreensSection()),
              _SectionShell(
                child: _FinalCta(
                  onOpenApp: () => _open(_webAppUrl),
                  onAppStore: () => _open(_appStoreUrl, external: true),
                  onGooglePlay: () => _open(_googlePlayUrl, external: true),
                  onFacebook: () => _open(_facebookUrl, external: true),
                  onYoutube: () => _open(_youtubeUrl, external: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpenApp, required this.onSignUp});

  final VoidCallback onOpenApp;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Transform.scale(
                    scale: 1.45,
                    child: Image.asset(
                      'marketing/google-play-assets/app-icon/dzmarket_app_icon_512.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'DZMarket',
                style: TextStyle(
                  color: _Colors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onSignUp,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Créer un compte'),
                style: _ButtonStyles.outline,
              ),
              FilledButton.icon(
                onPressed: onOpenApp,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text("Ouvrir l'app"),
                style: _ButtonStyles.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.onOpenApp,
    required this.onAppStore,
    required this.onGooglePlay,
  });

  final VoidCallback onOpenApp;
  final VoidCallback onAppStore;
  final VoidCallback onGooglePlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;
        final text = _HeroText(
          onOpenApp: onOpenApp,
          onAppStore: onAppStore,
          onGooglePlay: onGooglePlay,
        );
        final visual = const _HeroVisual();

        if (!isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [text, const SizedBox(height: 30), visual],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 11, child: text),
            const SizedBox(width: 42),
            Expanded(flex: 10, child: visual),
          ],
        );
      },
    );
  }
}

class _HeroText extends StatelessWidget {
  const _HeroText({
    required this.onOpenApp,
    required this.onAppStore,
    required this.onGooglePlay,
  });

  final VoidCallback onOpenApp;
  final VoidCallback onAppStore;
  final VoidCallback onGooglePlay;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final headlineSize = width < 520 ? 40.0 : 64.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Badge(label: 'Marketplace algérienne'),
        const SizedBox(height: 22),
        Text(
          'Achetez, vendez et livrez plus simplement en Algérie.',
          style: TextStyle(
            color: _Colors.ink,
            fontSize: headlineSize,
            fontWeight: FontWeight.w900,
            height: 0.98,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Une app pensée pour les vendeurs et acheteurs algériens : annonces, chat, commandes, livraison et suivi au même endroit.',
          style: TextStyle(
            color: _Colors.body,
            fontSize: 19,
            height: 1.55,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        const Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            'منصة جزائرية للبيع والشراء مع دردشة مدمجة، طلبات واضحة، وتوصيل أسهل متابعة.',
            style: TextStyle(
              color: _Colors.body,
              fontSize: 18,
              height: 1.7,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 26),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onOpenApp,
              icon: const Icon(Icons.travel_explore_rounded, size: 20),
              label: const Text("Ouvrir l'app web"),
              style: _ButtonStyles.primaryLarge,
            ),
            _StoreButton(
              icon: Icons.apple_rounded,
              label: 'App Store',
              onPressed: onAppStore,
            ),
            _StoreButton(
              icon: Icons.shop_2_rounded,
              label: 'Google Play',
              onPressed: onGooglePlay,
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroVisual extends StatelessWidget {
  const _HeroVisual();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.03,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFE7F5EB),
                borderRadius: BorderRadius.circular(46),
                border: Border.all(color: const Color(0xFFC8DDCE)),
              ),
            ),
          ),
          const Positioned(
            left: 28,
            right: 28,
            top: 28,
            child: _ShowcaseImage(
              asset:
                  'marketing/facebook-assets/dzmarket_android_launch_promo_v2.png',
              radius: 34,
            ),
          ),
          const Positioned(
            left: 22,
            bottom: 22,
            child: _MiniPanel(
              icon: Icons.local_shipping_rounded,
              title: 'Livraison intégrée',
              body: 'Yalidine, ZR, Ecotrack, Guepex',
            ),
          ),
          const Positioned(
            right: 22,
            bottom: 22,
            child: _MiniPanel(
              icon: Icons.language_rounded,
              title: 'FR / AR',
              body: 'Interface adaptée au marché algérien',
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofStrip extends StatelessWidget {
  const _ProofStrip();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 920
            ? (constraints.maxWidth - 36) / 4
            : constraints.maxWidth >= 560
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              width: itemWidth,
              icon: Icons.storefront_rounded,
              title: 'Annonces',
              body: 'Publier et parcourir plus clairement',
            ),
            _MetricCard(
              width: itemWidth,
              icon: Icons.chat_bubble_rounded,
              title: 'Chat',
              body: 'Discuter avec acheteurs et vendeurs',
            ),
            _MetricCard(
              width: itemWidth,
              icon: Icons.receipt_long_rounded,
              title: 'Commandes',
              body: 'Suivre les ventes sans tableur',
            ),
            _MetricCard(
              width: itemWidth,
              icon: Icons.route_rounded,
              title: 'Suivi',
              body: 'Gérer livraison et bordereaux',
            ),
          ],
        );
      },
    );
  }
}

class _UseCasesSection extends StatelessWidget {
  const _UseCasesSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          eyebrow: 'Pour acheter, vendre et expédier',
          title: 'Un parcours plus simple que les annonces dispersées.',
          body:
              'DZMarket centralise ce qui se perd souvent entre Facebook, messages privés, appels et livraison.',
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 920;
            final width = isWide ? (constraints.maxWidth - 32) / 3 : null;

            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _UseCaseCard(
                  width: width,
                  icon: Icons.search_rounded,
                  title: 'Acheter clairement',
                  body:
                      'Parcourez les annonces, ouvrez une fiche lisible et contactez le vendeur au bon moment.',
                ),
                _UseCaseCard(
                  width: width,
                  icon: Icons.add_business_rounded,
                  title: 'Vendre sans chaos',
                  body:
                      'Publiez vos produits, recevez les demandes et gardez vos ventes dans un seul espace.',
                ),
                _UseCaseCard(
                  width: width,
                  icon: Icons.fact_check_rounded,
                  title: 'Livrer avec suivi',
                  body:
                      'Configurez vos sociétés de livraison, générez vos bordereaux et suivez les statuts.',
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ScreensSection extends StatelessWidget {
  const _ScreensSection();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;
        const content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              eyebrow: 'Produit réel',
              title: 'Des écrans prêts pour les vendeurs algériens.',
              body:
                  'La page web, l’app mobile et le tableau de livraison gardent le même objectif : réduire les frictions au quotidien.',
            ),
            SizedBox(height: 18),
            _FeatureLine(
              icon: Icons.public_rounded,
              title: 'Web',
              body: 'Un point d’entrée simple pour découvrir DZMarket.',
            ),
            _FeatureLine(
              icon: Icons.smartphone_rounded,
              title: 'Mobile',
              body: 'iPhone et Android avec interface FR/AR.',
            ),
            _FeatureLine(
              icon: Icons.local_shipping_rounded,
              title: 'Transporteurs',
              body: 'Configuration vendeur et génération de bordereaux.',
            ),
          ],
        );

        const images = _ScreenshotGrid();

        if (!isWide) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [content, SizedBox(height: 24), images],
          );
        }

        return const Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 8, child: content),
            SizedBox(width: 36),
            Expanded(flex: 10, child: images),
          ],
        );
      },
    );
  }
}

class _ScreenshotGrid extends StatelessWidget {
  const _ScreenshotGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final smallWidth = (constraints.maxWidth - 14) / 2;
        return Column(
          children: [
            const _ShowcaseImage(
              asset: 'marketing/web-tutorial/final/fr/01_discover_fr.png',
              radius: 28,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: smallWidth,
                  child: const _ShowcaseImage(
                    asset:
                        'marketing/facebook-assets/dzmarket_iphone_launch_promo_v2.png',
                    radius: 24,
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: smallWidth,
                  child: const _ShowcaseImage(
                    asset: 'marketing/web-tutorial/final/fr/04_delivery_fr.png',
                    radius: 24,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _FinalCta extends StatelessWidget {
  const _FinalCta({
    required this.onOpenApp,
    required this.onAppStore,
    required this.onGooglePlay,
    required this.onFacebook,
    required this.onYoutube,
  });

  final VoidCallback onOpenApp;
  final VoidCallback onAppStore;
  final VoidCallback onGooglePlay;
  final VoidCallback onFacebook;
  final VoidCallback onYoutube;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: _Colors.ink,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SizedBox(
            width: 660,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Commencez avec DZMarket',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Disponible sur le web, iPhone et Android. Retrouvez aussi les tutoriels sur Facebook et YouTube.',
                  style: TextStyle(
                    color: Color(0xFFDDEBE2),
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DarkAction(
                label: 'Web',
                icon: Icons.open_in_new_rounded,
                onTap: onOpenApp,
              ),
              _DarkAction(
                label: 'App Store',
                icon: Icons.apple_rounded,
                onTap: onAppStore,
              ),
              _DarkAction(
                label: 'Google Play',
                icon: Icons.shop_2_rounded,
                onTap: onGooglePlay,
              ),
              _DarkAction(
                label: 'Facebook',
                icon: Icons.facebook_rounded,
                onTap: onFacebook,
              ),
              _DarkAction(
                label: 'YouTube',
                icon: Icons.play_circle_fill_rounded,
                onTap: onYoutube,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  const _SectionShell({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: child,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Badge(label: eyebrow),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: _Colors.ink,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              height: 1.06,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: _Colors.body,
              fontSize: 17,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShowcaseImage extends StatelessWidget {
  const _ShowcaseImage({required this.asset, required this.radius});

  final String asset;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0xFFC9DDD1)),
        ),
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox(
              height: 260,
              child: Center(child: Icon(Icons.image_not_supported_rounded)),
            );
          },
        ),
      ),
    );
  }
}

class _MiniPanel extends StatelessWidget {
  const _MiniPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E6DC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180E2A1E),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: _Colors.green, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _Colors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _Colors.body,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.body,
  });

  final double width;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(minHeight: 132),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFD7E6DC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _Colors.green, size: 28),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: _Colors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              body,
              style: const TextStyle(
                color: _Colors.body,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UseCaseCard extends StatelessWidget {
  const _UseCaseCard({
    required this.icon,
    required this.title,
    required this.body,
    this.width,
  });

  final IconData icon;
  final String title;
  final String body;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(minHeight: 196),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFD7E6DC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _Colors.green, size: 30),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: _Colors.ink,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              body,
              style: const TextStyle(
                color: _Colors.body,
                fontSize: 15.5,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFFDDF3E4),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _Colors.green, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _Colors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: _Colors.body,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreButton extends StatelessWidget {
  const _StoreButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      label: Text(label),
      style: _ButtonStyles.outlineLarge,
    );
  }
}

class _DarkAction extends StatelessWidget {
  const _DarkAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _Colors.ink,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE1F5E8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFB8DBC5)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _Colors.green,
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
    );
  }
}

abstract final class _ButtonStyles {
  static final ButtonStyle primary = FilledButton.styleFrom(
    backgroundColor: _Colors.green,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  static final ButtonStyle primaryLarge = FilledButton.styleFrom(
    backgroundColor: _Colors.green,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
  );

  static final ButtonStyle outline = OutlinedButton.styleFrom(
    foregroundColor: _Colors.ink,
    side: const BorderSide(color: Color(0xFF9DBBA9)),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  static final ButtonStyle outlineLarge = OutlinedButton.styleFrom(
    foregroundColor: _Colors.ink,
    side: const BorderSide(color: Color(0xFF9DBBA9)),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
  );
}

abstract final class _Colors {
  static const ink = Color(0xFF102D22);
  static const body = Color(0xFF465B51);
  static const green = Color(0xFF12834A);
}
