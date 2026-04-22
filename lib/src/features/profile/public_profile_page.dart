// ignore_for_file: deprecated_member_use
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/network_preferences_service.dart';
import 'package:dzmarket/src/services/review_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/services/user_safety_service.dart';
import 'package:dzmarket/src/utils/bool_utils.dart';
import 'package:dzmarket/src/utils/public_storage_url_resolver.dart';
import 'package:dzmarket/src/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({super.key, required this.userId});

  final String userId;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  List<Product> _products = const [];
  double? _averageRating;
  final _safetyService = UserSafetyService();
  final _reviewService = ReviewService();
  bool _isBlocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _products = const [];
      _averageRating = null;
    });
    try {
      final profile = await supabase
          .from('profiles')
          .select(
            'id, full_name, avatar_url, is_public, wilaya, bio, role, is_seller, created_at',
          )
          .eq('id', widget.userId)
          .maybeSingle();
      if (!mounted) return;
      _profile = profile;
      if (isTruthyFlag(profile?['is_public'])) {
        final rows = await supabase
            .from('products')
            .select()
            .eq('owner_id', widget.userId)
            .eq('is_archived', false)
            .order('created_at', ascending: false)
            .limit(60);
        if (!mounted) return;
        _products = (rows as List)
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
        _averageRating = await _reviewService.fetchAverageRating(widget.userId);
      }
      await _refreshBlockState();
    } catch (e) {
      if (!mounted) return;
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? get _currentUserId => supabase.auth.currentUser?.id;

  bool get _canModerateUser =>
      _currentUserId != null && _currentUserId != widget.userId;

  bool get _isSellerProfile {
    final role = (_profile?['role'] as String?)?.toLowerCase();
    return isTruthyFlag(_profile?['is_seller']) ||
        role == 'seller' ||
        _products.isNotEmpty;
  }

  Future<void> _refreshBlockState() async {
    if (!_canModerateUser) {
      if (mounted) setState(() => _isBlocked = false);
      return;
    }
    final blocked = await _safetyService.isBlocked(widget.userId);
    if (mounted) setState(() => _isBlocked = blocked);
  }

  Future<void> _toggleBlockUser() async {
    final title = _isBlocked
        ? L10n.tr(
            context,
            'safety.unblock_user',
            fallback: 'Debloquer cet utilisateur',
          )
        : L10n.tr(
            context,
            'safety.block_user',
            fallback: 'Bloquer cet utilisateur',
          );
    final body = _isBlocked
        ? L10n.tr(
            context,
            'safety.unblock_user_body',
            fallback:
                'Vous pourrez de nouveau echanger avec cet utilisateur apres le deblocage.',
          )
        : L10n.tr(
            context,
            'safety.block_user_body',
            fallback:
                'Vous ne pourrez plus envoyer ni recevoir de messages avec cet utilisateur apres le blocage.',
          );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L10n.tr(dialogContext, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(title),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_isBlocked) {
      await _safetyService.unblockUser(widget.userId);
    } else {
      await _safetyService.blockUser(widget.userId);
    }
    final wasBlocked = _isBlocked;
    await _refreshBlockState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasBlocked
              ? L10n.tr(
                  context,
                  'safety.unblock_user_success',
                  fallback: 'Utilisateur debloque.',
                )
              : L10n.tr(
                  context,
                  'safety.block_user_success',
                  fallback: 'Utilisateur bloque.',
                ),
        ),
      ),
    );
  }

  Future<void> _reportUser() async {
    String? selectedReason;
    final detailsCtrl = TextEditingController();
    const reasonLabels = {
      'safety.reason.harassment': 'Harcelement',
      'report.reason.scam': 'Arnaque',
      'report.reason.prohibited': 'Contenu interdit',
      'safety.reason.spam': 'Spam',
      'safety.reason.other': 'Autre',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) => AlertDialog(
          title: Text(
            L10n.tr(
              dialogContext,
              'safety.report_user_title',
              fallback: 'Signaler cet utilisateur',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in reasonLabels.keys)
                    ChoiceChip(
                      label: Text(
                        L10n.tr(
                          dialogContext,
                          key,
                          fallback: reasonLabels[key],
                        ),
                      ),
                      selected: selectedReason == key,
                      onSelected: (selected) {
                        setModalState(() {
                          selectedReason = selected ? key : null;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: detailsCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: L10n.tr(
                    dialogContext,
                    'report.details',
                    fallback: 'Details',
                  ),
                  hintText: L10n.tr(
                    dialogContext,
                    'report.details_hint',
                    fallback: 'Ajoutez des details (optionnel)',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(L10n.tr(dialogContext, 'common.cancel')),
            ),
            FilledButton(
              onPressed: selectedReason == null
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: Text(L10n.tr(dialogContext, 'common.send')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedReason == null) {
      detailsCtrl.dispose();
      return;
    }
    if (!mounted) {
      detailsCtrl.dispose();
      return;
    }
    final reasonLabel = L10n.tr(
      context,
      selectedReason!,
      fallback: selectedReason!,
    );
    final details = detailsCtrl.text.trim();
    detailsCtrl.dispose();
    final reason = details.isEmpty ? reasonLabel : '[$reasonLabel] $details';
    await _safetyService.reportUser(
      reportedUserId: widget.userId,
      reason: reason,
      source: 'profile',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          L10n.tr(
            context,
            'safety.report_user_success',
            fallback: 'Signalement envoye. Merci.',
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (!_canModerateUser) return const [];
    final messenger = ScaffoldMessenger.of(this.context);
    final genericError = L10n.tr(this.context, 'common.error');
    return [
      PopupMenuButton<String>(
        onSelected: (value) async {
          try {
            switch (value) {
              case 'report':
                await _reportUser();
                break;
              case 'block':
                await _toggleBlockUser();
                break;
            }
          } catch (_) {
            messenger.showSnackBar(SnackBar(content: Text(genericError)));
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: 'report',
            child: Text(
              L10n.tr(
                context,
                'safety.report_user',
                fallback: 'Signaler cet utilisateur',
              ),
            ),
          ),
          PopupMenuItem<String>(
            value: 'block',
            child: Text(
              _isBlocked
                  ? L10n.tr(
                      context,
                      'safety.unblock_user',
                      fallback: 'Debloquer cet utilisateur',
                    )
                  : L10n.tr(
                      context,
                      'safety.block_user',
                      fallback: 'Bloquer cet utilisateur',
                    ),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;
    final currency = NumberFormat.currency(
      locale: localeCode == 'ar' ? 'ar_DZ' : 'fr_DZ',
      symbol: 'DA',
    );
    final memberSinceDate = DateTime.tryParse(
      _profile?['created_at']?.toString() ?? '',
    );
    final memberSinceLabel = memberSinceDate == null
        ? null
        : L10n.tr(
            context,
            'profile.member_since',
            fallback: 'Membre depuis {date}',
            params: {
              'date': DateFormat.yMMMd(
                localeCode == 'ar' ? 'ar_DZ' : 'fr_DZ',
              ).format(memberSinceDate),
            },
          );

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(L10n.tr(context, 'profile.public')),
          actions: _buildActions(context),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(L10n.tr(context, 'profile.public')),
          actions: _buildActions(context),
        ),
        body: Center(child: Text(_error!)),
      );
    }

    final isPublic = isTruthyFlag(_profile?['is_public']);
    final name = (_profile?['full_name'] as String?)?.trim();
    final avatarUrl = (_profile?['avatar_url'] as String?)?.trim();
    final bio = (_profile?['bio'] as String?)?.trim();
    final title = name?.isNotEmpty == true
        ? name!
        : L10n.tr(context, 'profile.public_profile_title');

    return Scaffold(
      appBar: AppBar(title: Text(title), actions: _buildActions(context)),
      body: isPublic
          ? RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        radius: 28,
                        avatarUrl: avatarUrl,
                        fullName: name,
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
                            if (memberSinceLabel != null &&
                                memberSinceLabel.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                memberSinceLabel,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_averageRating != null) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.star, size: 18),
                          label: Text(_averageRating!.toStringAsFixed(1)),
                        ),
                      ],
                    ),
                  ],
                  if (bio?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(bio!),
                    ),
                  ],
                  if (_isSellerProfile || _products.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      L10n.tr(
                        context,
                        'profile.public_profile_listings',
                        fallback: 'Annonces publiques',
                      ),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (_products.isEmpty)
                      Text(
                        L10n.tr(
                          context,
                          'profile.public_profile_no_listings',
                          fallback: 'Aucune annonce publique pour le moment.',
                        ),
                      )
                    else
                      ..._products.map(
                        (p) => Card(
                          child: ListTile(
                            leading: _ProductThumb(
                              url: p.firstDisplayableImageUrl(),
                            ),
                            title: Text(p.title),
                            subtitle: Text(currency.format(p.price)),
                            onTap: () => context.go('/product/${p.id}'),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            )
          : Center(
              child: Text(
                L10n.tr(
                  context,
                  'profile.public_profile_hidden_user',
                  fallback: 'Profil masque par l\'utilisateur.',
                ),
              ),
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
    final safeUrl = normalizePublicStorageUrl(url);
    if (safeUrl.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.image_not_supported));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: safeUrl,
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
