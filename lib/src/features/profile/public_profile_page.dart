// ignore_for_file: deprecated_member_use
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/network_preferences_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({super.key, required this.sellerId});

  final String sellerId;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  List<Product> _products = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await supabase
          .from('profiles')
          .select('id, full_name, avatar_url, is_public, wilaya')
          .eq('id', widget.sellerId)
          .maybeSingle();
      if (!mounted) return;
      _profile = profile;
      if (profile?['is_public'] == true) {
        final rows = await supabase
            .from('products')
            .select()
            .eq('owner_id', widget.sellerId)
            .eq('is_archived', false)
            .order('created_at', ascending: false)
            .limit(60);
        if (!mounted) return;
        _products = (rows as List)
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (!mounted) return;
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;
    final currency = NumberFormat.currency(
      locale: localeCode == 'ar' ? 'ar_DZ' : 'fr_DZ',
      symbol: 'DA',
    );

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.tr(context, 'profile.public'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.tr(context, 'profile.public'))),
        body: Center(child: Text(_error!)),
      );
    }

    final isPublic = _profile?['is_public'] == true;
    final name = (_profile?['full_name'] as String?)?.trim();
    final avatarUrl = (_profile?['avatar_url'] as String?)?.trim();
    final title = name?.isNotEmpty == true
        ? name!
        : L10n.tr(context, 'profile.public_profile_title');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: isPublic
          ? RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer,
                        backgroundImage:
                            (avatarUrl != null && avatarUrl.isNotEmpty)
                            ? CachedNetworkImageProvider(
                                avatarUrl,
                                imageRenderMethodForWeb:
                                    ImageRenderMethodForWeb.HtmlImage,
                              )
                            : null,
                        child: (avatarUrl == null || avatarUrl.isEmpty)
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            if ((_profile?['wilaya'] as String?)?.isNotEmpty ==
                                true)
                              Text(_profile!['wilaya'].toString()),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    L10n.tr(context, 'profile.public_profile_products'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (_products.isEmpty)
                    Text(L10n.tr(context, 'profile.public_profile_empty'))
                  else
                    ..._products.map(
                      (p) => Card(
                        child: ListTile(
                          leading: _ProductThumb(
                            url: p.imageUrls.isNotEmpty
                                ? p.imageUrls.first
                                : p.imageUrl,
                          ),
                          title: Text(p.title),
                          subtitle: Text(currency.format(p.price)),
                          onTap: () => context.push('/product/${p.id}'),
                        ),
                      ),
                    ),
                ],
              ),
            )
          : Center(
              child: Text(L10n.tr(context, 'profile.public_profile_hidden')),
            ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final imagePrefs = NetworkPreferencesService.instance;
    if (url == null || url!.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.image_not_supported));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        memCacheWidth: imagePrefs.listImageMemCacheWidth,
        memCacheHeight: imagePrefs.listImageMemCacheHeight,
        fadeInDuration: imagePrefs.imageFadeInDuration,
        fadeOutDuration: imagePrefs.imageFadeOutDuration,
        imageRenderMethodForWeb: ImageRenderMethodForWeb.HtmlImage,
        errorWidget: (_, __, ___) =>
            const CircleAvatar(child: Icon(Icons.image_not_supported)),
      ),
    );
  }
}
