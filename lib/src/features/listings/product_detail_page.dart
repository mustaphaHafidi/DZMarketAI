// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/chat/chat_room_page.dart';
import 'package:dzmarket/src/features/chat/order_chat_gate_page.dart';
import 'package:dzmarket/src/models/offer.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/features/profile/public_profile_page.dart';
import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:dzmarket/src/services/favorite_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/offer_service.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/services/payment_labels.dart';
import 'package:dzmarket/src/services/phone_formatter.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/review_service.dart';
import 'package:dzmarket/src/services/location_data_service.dart';
import 'package:dzmarket/src/services/network_preferences_service.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/utils/bool_utils.dart';
import 'package:dzmarket/src/utils/detail_layout_utils.dart';
import 'package:dzmarket/src/utils/product_share_url.dart';
import 'package:dzmarket/src/widgets/user_avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({super.key, required this.productId});

  final String productId;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  bool _loaded = false;
  Product? _product;
  final _pageController = PageController();
  final _detailScrollController = ScrollController();
  final _offerService = OfferService();
  Offer? _acceptedOffer;
  String? _buyerWilaya;
  String? _sellerWilaya;
  Map<String, dynamic>? _buyerProfile;
  Map<String, dynamic>? _sellerProfile;
  bool _isOwner = false;
  int _webHeroIndex = 0;
  bool? _favoriteOverride;
  bool _favoriteBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _reportListing(BuildContext context, Product product) async {
    final reasonController = TextEditingController();
    const reasonOptions = [
      'report.reason.fake',
      'report.reason.scam',
      'report.reason.prohibited',
      'report.reason.wrong_category',
      'report.reason.duplicate',
    ];
    String? selectedReasonKey;
    bool showError = false;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(L10n.tr(context, 'report.title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.tr(context, 'report.reason')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in reasonOptions)
                    ChoiceChip(
                      label: Text(L10n.tr(context, option)),
                      selected: selectedReasonKey == option,
                      onSelected: (selected) {
                        setState(() {
                          selectedReasonKey = selected ? option : null;
                          showError = false;
                        });
                      },
                    ),
                ],
              ),
              if (showError)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    L10n.tr(context, 'report.reason_required'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: L10n.tr(context, 'report.details'),
                  hintText: L10n.tr(context, 'report.details_hint'),
                ),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L10n.tr(context, 'common.cancel')),
            ),
            TextButton(
              onPressed: () async {
                if (selectedReasonKey == null) {
                  setState(() => showError = true);
                  return;
                }
                final details = InputSanitizer.sanitizeText(
                  reasonController.text,
                  maxLength: 300,
                );
                final reasonLabel = L10n.tr(context, selectedReasonKey!);
                final reason = details.isEmpty
                    ? reasonLabel
                    : '[$reasonLabel] $details';
                final userId = supabase.auth.currentUser?.id;
                if (userId == null) return;
                final result = await RateLimiter.instance.run(
                  'reports.submit',
                  () => supabase.rpc(
                    'submit_listing_report',
                    params: {'p_product_id': product.id, 'p_reason': reason},
                  ),
                );
                if (context.mounted) Navigator.of(context).pop();
                if (context.mounted) {
                  final status = (result as Map?)?['status']?.toString() ?? '';
                  final isMasked = status == 'masked' || status == 'blocked';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isMasked
                            ? L10n.tr(context, 'report.sent_masked')
                            : L10n.tr(context, 'report.sent'),
                      ),
                    ),
                  );
                }
              },
              child: Text(L10n.tr(context, 'common.send')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _detailScrollController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _loadLastCheckout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('checkout.last_address.v1');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  Future<void> _saveLastCheckout(Map<String, dynamic> selection) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'firstname': selection['firstname'],
        'familyname': selection['familyname'],
        'phone': selection['phone'],
        'phone2': selection['phone2'],
        'address': selection['address'],
        'senderWilayaId': selection['senderWilayaId'],
        'senderWilaya': selection['senderWilaya'],
        'receiverWilaya': selection['receiverWilaya'],
        'receiverWilayaId': selection['receiverWilayaId'],
        'receiverCommune': selection['receiverCommune'],
        'receiverCommuneId': selection['receiverCommuneId'],
        'wilayaCode': selection['wilayaCode'],
        'zip': selection['zip'],
        'courierId': selection['courierId'],
        'courierName': selection['courierName'],
        'freeshipping': selection['freeshipping'],
        'estimatedFee': selection['estimatedFee'],
        'estimatedFeeSource': selection['estimatedFeeSource'],
        'hasExchange': selection['hasExchange'],
        'insuranceActive': selection['insuranceActive'],
      });
      await prefs.setString('checkout.last_address.v1', payload);
    } catch (_) {}
  }

  Future<void> _load() async {
    final userId = supabase.auth.currentUser?.id;
    final safeProductId = InputSanitizer.sanitizeId(
      widget.productId,
      maxLength: 64,
    );
    final data = await RateLimiter.instance.run(
      'products.detail.select',
      () => supabase
          .from('products')
          .select('*, categories(name_fr, name_ar, slug)')
          .eq('id', safeProductId)
          .maybeSingle(),
    );
    final isOwner =
        userId != null && data != null && data['owner_id'] == userId;
    final isArchived = data?['is_archived'] as bool? ?? false;
    final moderationStatus = data?['moderation_status']?.toString();
    final isPubliclyVisible =
        data != null && !isArchived && moderationStatus == 'approved';
    Map<String, dynamic>? buyerProfile;
    Map<String, dynamic>? seller;
    Offer? acceptedOffer;
    if (userId != null) {
      buyerProfile = await RateLimiter.instance.run(
        'profiles.buyer.select',
        () => supabase
            .from('profiles')
            .select('wilaya, daira, full_name, phone')
            .eq('id', userId)
            .maybeSingle(),
      );
    }
    if (data != null && !isOwner && !isPubliclyVisible) {
      if (!mounted) return;
      setState(() {
        _product = null;
        _buyerWilaya = buyerProfile?['wilaya']?.toString();
        _sellerWilaya = null;
        _buyerProfile = buyerProfile;
        _sellerProfile = null;
        _loaded = true;
        _acceptedOffer = null;
        _isOwner = false;
        _favoriteOverride = null;
        _favoriteBusy = false;
      });
      return;
    }
    if (data != null && data['owner_id'] != null) {
      seller = await RateLimiter.instance.run(
        'profiles.wilaya.seller',
        () => supabase
            .from('profiles')
            .select('wilaya, full_name, avatar_url, is_public')
            .eq('id', data['owner_id'])
            .maybeSingle(),
      );
      if (userId != null && userId != data['owner_id']) {
        try {
          final accepted = await RateLimiter.instance.run(
            'offers.accepted.select',
            () => supabase
                .from('offers')
                .select('*')
                .eq('product_id', safeProductId)
                .eq('buyer_id', userId)
                .eq('status', 'accepted')
                .order('responded_at', ascending: false)
                .limit(1)
                .maybeSingle(),
          );
          if (accepted != null) {
            acceptedOffer = Offer.fromJson(accepted);
          }
        } catch (_) {
          acceptedOffer = null;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _product = data != null ? Product.fromJson(data) : null;
      _buyerWilaya = buyerProfile?['wilaya']?.toString();
      _sellerWilaya = seller?['wilaya'] as String?;
      _buyerProfile = buyerProfile;
      _sellerProfile = seller;
      _loaded = true;
      _acceptedOffer = acceptedOffer;
      _isOwner = isOwner;
      _favoriteOverride = null;
      _favoriteBusy = false;
    });
  }

  Future<void> _contactSeller({bool sendIntroMessage = false}) async {
    final userId = supabase.auth.currentUser?.id;
    if (_product == null) return;
    if (userId == null) {
      _redirectGuestToSignIn();
      return;
    }
    final repo = ChatRepository();
    final conv = await repo.ensureConversation(
      productId: _product!.id,
      buyerId: userId,
      sellerId: _product!.ownerId,
    );
    if (!mounted) return;
    if (sendIntroMessage) {
      final newContactText = L10n.tr(context, 'chat.new_contact');
      // Try to send a hello message; ignore duplicate/race errors.
      try {
        await repo.sendMessage(conv.id, newContactText);
      } catch (_) {
        // If send failed (e.g., blocked), ignore for now; navigation still works.
      }
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatRoomPage(conversationId: conv.id, productId: _product!.id),
      ),
    );
  }

  String _resolveCategoryLabel(BuildContext context) {
    final fr = _product?.categoryNameFr ?? _product?.category ?? '';
    final ar = _product?.categoryNameAr ?? _product?.category ?? '';
    final slug = _product?.categorySlug ?? '';
    final locale = Localizations.localeOf(context).languageCode;
    final fallback = locale == 'ar'
        ? (_hasArabicLetters(ar) ? ar : (fr.isNotEmpty ? fr : ar))
        : (fr.isNotEmpty ? fr : ar);
    if (slug.isEmpty) return fallback;
    final translated = L10n.tr(context, 'category.$slug', fallback: fallback);
    return _looksMojibake(translated) ? fallback : translated;
  }

  String _deliveryLabelForOption(BuildContext context, String option) {
    return option == 'cod'
        ? L10n.tr(context, 'listing.detail.delivery_cod')
        : L10n.tr(context, 'listing.detail.delivery_pickup');
  }

  List<String> _buildDetailTags(BuildContext context) {
    if (_product == null) return const [];
    final tags = <String>[];
    final product = _product!;
    if (product.condition?.isNotEmpty ?? false) {
      tags.add(product.condition!);
    }
    if (product.brand?.isNotEmpty ?? false) {
      tags.add(
        L10n.tr(
          context,
          'listing.brand',
          params: {'value': product.brand ?? ''},
        ),
      );
    }
    if (product.size?.isNotEmpty ?? false) {
      tags.add(
        L10n.tr(context, 'listing.size', params: {'value': product.size ?? ''}),
      );
    }
    if (product.color?.isNotEmpty ?? false) {
      tags.add(
        L10n.tr(
          context,
          'listing.color',
          params: {'value': product.color ?? ''},
        ),
      );
    }
    if ((product.categoryNameFr?.isNotEmpty ?? false) ||
        (product.category?.isNotEmpty ?? false)) {
      tags.add(
        L10n.tr(
          context,
          'listing.category',
          params: {'value': _resolveCategoryLabel(context)},
        ),
      );
    }
    if (product.locationWilaya?.isNotEmpty ?? false) {
      tags.add(
        L10n.tr(
          context,
          'listing.detail.wilaya',
          params: {'value': product.locationWilaya!},
        ),
      );
    }
    if (product.locationDaira?.isNotEmpty ?? false) {
      tags.add(
        L10n.tr(
          context,
          'listing.detail.daira',
          params: {'value': product.locationDaira!},
        ),
      );
    }
    if (product.deliveryOptions.isNotEmpty) {
      tags.add(
        L10n.tr(
          context,
          'listing.detail.delivery',
          params: {
            'value': product.deliveryOptions
                .map((o) => _deliveryLabelForOption(context, o))
                .join(', '),
          },
        ),
      );
    }
    return tags;
  }

  List<String> _buildPrimaryTags(BuildContext context) {
    if (_product == null) return const [];
    final product = _product!;
    final tags = <String>[];
    if (product.condition?.isNotEmpty ?? false) {
      tags.add(product.condition!);
    }
    if (product.locationWilaya?.isNotEmpty ?? false) {
      tags.add(
        L10n.tr(
          context,
          'listing.detail.wilaya',
          params: {'value': product.locationWilaya!},
        ),
      );
    }
    if (product.deliveryOptions.isNotEmpty) {
      tags.add(
        L10n.tr(
          context,
          'listing.detail.delivery',
          params: {
            'value': product.deliveryOptions
                .map((o) => _deliveryLabelForOption(context, o))
                .join(', '),
          },
        ),
      );
    }
    return tags;
  }

  Future<void> _showAllTagsSheet(
    BuildContext context,
    List<String> tags,
  ) async {
    if (tags.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.tr(context, 'listing.details', fallback: 'Details'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final tag in tags) Chip(label: Text(tag))],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasArabicLetters(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }

  bool _looksMojibake(String value) {
    return value.contains('Ãƒ') ||
        value.contains('Ã‚') ||
        value.contains('ï¿½');
  }

  Widget _topOverlayIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    Color iconColor = Colors.white,
    Color? backgroundColor,
  }) {
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.black.withValues(alpha: 0.46),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor),
        onPressed: onPressed,
      ),
    );
  }

  Future<String?> _chooseDeliveryMode({
    required List<Map<String, dynamic>> enabledCouriers,
  }) async {
    String method = 'pickup';
    final deliveryOptions = _product?.deliveryOptions ?? const [];
    final sellerHasEnabledCouriers = enabledCouriers.isNotEmpty;
    final allowCod =
        sellerHasEnabledCouriers &&
        (deliveryOptions.isEmpty || deliveryOptions.contains('cod'));
    final courierNames = <String>[];
    for (final row in enabledCouriers) {
      final name = row['courier_name']?.toString().trim() ?? '';
      if (name.isEmpty || courierNames.contains(name)) continue;
      courierNames.add(name);
    }
    final codSubtitle = allowCod && courierNames.isNotEmpty
        ? L10n.tr(
            context,
            'checkout.delivery_cod_desc_with_couriers',
            params: {'couriers': courierNames.join(', ')},
          )
        : (!sellerHasEnabledCouriers
              ? L10n.tr(context, 'checkout.no_courier_enabled')
              : L10n.tr(context, 'checkout.delivery_cod_desc'));
    // "Arranged delivery" fallback is always possible.
    const allowPickup = true;
    if (allowCod) {
      method = 'cod';
    }
    if (deliveryOptions.isNotEmpty) {
      final preferred = deliveryOptions.first.toLowerCase();
      if (preferred == 'pickup' && allowPickup) {
        method = 'pickup';
      } else if (preferred == 'cod' && allowCod) {
        method = 'cod';
      }
    }
    if (!allowCod) {
      method = 'pickup';
    }

    Widget optionTile({
      required String value,
      required String title,
      required String subtitle,
      required bool enabled,
      required void Function(void Function()) setSheetState,
    }) {
      final selected = method == value;
      final scheme = Theme.of(context).colorScheme;
      final borderColor = selected
          ? scheme.primary
          : scheme.outlineVariant.withValues(alpha: 0.7);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
          color: selected
              ? scheme.primary.withValues(alpha: 0.06)
              : scheme.surface,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? () => setSheetState(() => method = value) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Radio<String>(
                  value: value,
                  groupValue: method,
                  onChanged: enabled
                      ? (v) {
                          setSheetState(() => method = v ?? method);
                        }
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Opacity(
                    opacity: enabled ? 1 : 0.55,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.tr(context, 'checkout.choose_delivery_mode'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  L10n.tr(
                    context,
                    'checkout.choose_delivery_mode_hint',
                    fallback:
                        'Choisissez une option simple. Vous pouvez finaliser les details ensuite.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                optionTile(
                  value: 'pickup',
                  title: L10n.tr(context, 'checkout.delivery_pickup_title'),
                  subtitle: L10n.tr(context, 'checkout.delivery_pickup_desc'),
                  enabled: true,
                  setSheetState: setSheetState,
                ),
                const SizedBox(height: 10),
                optionTile(
                  value: 'cod',
                  title: L10n.tr(context, 'checkout.delivery_cod_title'),
                  subtitle: codSubtitle,
                  enabled: allowCod,
                  setSheetState: setSheetState,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, method),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(L10n.tr(context, 'common.continue')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _buyNow() async {
    if (_isOwner) return;
    if (_product == null) return;
    if (supabase.auth.currentUser?.id == null) {
      _redirectGuestToSignIn();
      return;
    }
    if ((_product?.stockQuantity ?? 0) <= 0 || _product?.isArchived == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.tr(context, 'order.stock_unavailable'))),
        );
      }
      return;
    }

    final shippingService = ShippingService();
    final sellerId = _product!.ownerId;
    final enabledCouriers = await shippingService.fetchEnabledCouriersForSeller(
      sellerId,
    );
    final deliveryChoice = await _chooseDeliveryMode(
      enabledCouriers: enabledCouriers,
    );
    if (deliveryChoice == null) return;
    if (!mounted) return;
    if (deliveryChoice == 'pickup') {
      final agreed =
          _acceptedOffer?.agreedAmount ??
          _acceptedOffer?.amount ??
          _product?.price;
      final confirmed = await _confirmArrangedCheckoutSummary(
        price: agreed ?? 0,
      );
      if (!confirmed) return;
      final orderId = await OrderService().createOrder(
        productId: widget.productId,
        shippingOption: 'pickup',
        paymentMethod: 'cod',
        agreedPrice: agreed,
        deliveryMethod: 'pickup',
        shippingCost: 0,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.tr(context, 'order.created.pickup'))),
        );
      }
      if (orderId != null) {
        await _openOrderChat(orderId);
      }
      return;
    }

    final agreed =
        _acceptedOffer?.agreedAmount ??
        _acceptedOffer?.amount ??
        _product?.price;
    final selection = await _pickCourierAndAddress(
      sellerId,
      price: agreed ?? 0,
      productTitle: _product?.title ?? 'Article',
      preloadedEnabledCouriers: enabledCouriers,
    );
    if (selection == null) return;
    if (!mounted) return;
    final courierId = selection['courierId'] as String?;
    final courierName = selection['courierName'] as String?;
    final isYalidine =
        courierId?.toLowerCase().contains('yalidine') == true ||
        courierName?.toLowerCase().contains('yalidine') == true;
    final isEcotrack =
        courierId?.toLowerCase().contains('ecotrack') == true ||
        courierName?.toLowerCase().contains('ecotrack') == true;
    final isZrExpress = ShippingService.isZrExpressCourier(
      courierId: courierId,
      courierName: courierName,
    );
    final isGuepex = ShippingService.isGuepexCourier(
      courierId: courierId,
      courierName: courierName,
    );
    final shippingOption = courierName;
    final paymentMethod = 'cod';
    final deliveryMode = courierName;
    final freeShipping = _product?.shippingFree == true;
    double? shippingCost = freeShipping
        ? 0.0
        : (selection['estimatedFee'] as num?)?.toDouble();
    if (!freeShipping &&
        (isYalidine || isEcotrack || isZrExpress || isGuepex)) {
      final quote = await shippingService.estimateCheckoutShippingFee(
        sellerId: sellerId,
        courierId: courierId ?? '',
        courierName: courierName,
        productId: _product?.id,
        deliveryType: selection['deliveryType']?.toString() ?? 'home',
        senderWilayaId: selection['senderWilayaId']?.toString(),
        senderWilayaName: selection['senderWilaya']?.toString(),
        receiverWilayaId: selection['receiverWilayaId']?.toString(),
        receiverWilayaName: selection['receiverWilaya']?.toString(),
        receiverCommuneId: selection['receiverCommuneId']?.toString(),
        receiverCommuneName: selection['receiverCommune']?.toString(),
        price: (selection['price'] as num?)?.toDouble() ?? (agreed ?? 0),
        declaredValue: (selection['declaredValue'] as num?)?.toDouble(),
        weightKg:
            (selection['weight'] as num?)?.toInt() ?? (_product?.weightKg ?? 1),
        heightCm:
            (selection['height'] as num?)?.toInt() ?? (_product?.heightCm ?? 0),
        widthCm:
            (selection['width'] as num?)?.toInt() ?? (_product?.widthCm ?? 0),
        lengthCm:
            (selection['length'] as num?)?.toInt() ?? (_product?.lengthCm ?? 0),
      );
      if (quote != null) {
        shippingCost = quote.fee;
        selection['estimatedFee'] = quote.fee;
        selection['estimatedFeeSource'] = quote.source;
      }
    }
    if (!mounted) return;
    if (!freeShipping && shippingCost == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tr(context, 'checkout.fees_unavailable')),
          ),
        );
      }
      return;
    }
    final etaLabel = isYalidine
        ? L10n.tr(context, 'checkout.eta_yalidine')
        : isEcotrack
        ? L10n.tr(context, 'checkout.eta_ecotrack')
        : isZrExpress
        ? L10n.tr(context, 'checkout.eta_zrexpress')
        : isGuepex
        ? L10n.tr(context, 'checkout.eta_guepex')
        : shippingService.estimateEtaLabel(
            courierName: courierName,
            courierId: courierId,
          );
    final confirmed = await _confirmCheckoutSummary(
      price: agreed ?? 0,
      shippingOption: shippingOption ?? '',
      paymentMethod: paymentMethod,
      deliveryMode: deliveryMode,
      shippingCost: shippingCost,
      etaLabel: etaLabel,
    );
    if (!confirmed) return;

    final orderService = OrderService();
    String? orderId;
    try {
      orderId = await orderService.createOrder(
        productId: widget.productId,
        shippingOption: shippingOption,
        paymentMethod: paymentMethod,
        agreedPrice: agreed,
        courierId: courierId,
        courierName: courierName,
        deliveryMethod: deliveryMode,
        shippingCost: shippingCost,
        shippingSelection: selection,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tr(
                context,
                'order.create_error',
                params: {'error': e.toString()},
              ),
            ),
          ),
        );
      }
      return;
    }
    if (orderId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.tr(context, 'order.create_failed'))),
        );
      }
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          L10n.tr(
            context,
            'order.created.delivery',
            params: {
              'courier':
                  courierName ?? L10n.tr(context, 'order.delivery.generic'),
            },
          ),
        ),
      ),
    );
    await _openOrderChat(orderId);
  }

  Future<void> _openOrderChat(String orderId) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderChatGatePage(orderId: orderId)),
    );
  }

  Future<Map<String, dynamic>?> _pickCourierAndAddress(
    String sellerId, {
    required double price,
    required String productTitle,
    List<Map<String, dynamic>>? preloadedEnabledCouriers,
  }) async {
    final shippingService = ShippingService();
    final lastCheckout = await _loadLastCheckout();
    final enabled =
        preloadedEnabledCouriers ??
        await shippingService.fetchEnabledCouriersForSeller(sellerId);
    if (enabled.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tr(context, 'checkout.no_courier_enabled')),
          ),
        );
      }
      return null;
    }
    final courier = await _chooseCourier(enabled);
    if (courier == null) return null;
    if (!mounted) return null;
    final courierId = courier['courier_id']?.toString() ?? '';
    final courierName =
        courier['courier_name']?.toString() ??
        L10n.tr(context, 'checkout.courier_placeholder');
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => _CheckoutAddressSheet(
        product: _product,
        sellerId: sellerId,
        courierId: courierId,
        courierName: courierName,
        buyerProfile: _buyerProfile,
        buyerWilaya: _buyerWilaya,
        sellerWilaya: _sellerWilaya,
        lastCheckout: lastCheckout,
        onSaveLastCheckout: _saveLastCheckout,
        defaultPrice: price,
        productTitle: productTitle,
      ),
    );
  }

  Future<Map<String, dynamic>?> _chooseCourier(
    List<Map<String, dynamic>> enabled,
  ) async {
    if (enabled.length == 1) return enabled.first;
    if (!mounted) return null;
    var selectedIndex = 0;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final scheme = Theme.of(context).colorScheme;
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.tr(context, 'checkout.choose_courier'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    L10n.tr(
                      context,
                      'checkout.choose_courier_hint',
                      fallback:
                          'Le prix final de livraison depend du transporteur choisi.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: enabled.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final row = enabled[index];
                        final selected = index == selectedIndex;
                        final name =
                            row['courier_name']?.toString() ??
                            L10n.tr(context, 'checkout.courier_placeholder');
                        final coverage = row['coverage']?.toString().trim();
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () =>
                              setSheetState(() => selectedIndex = index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? scheme.primary
                                    : scheme.outlineVariant.withValues(
                                        alpha: 0.7,
                                      ),
                                width: selected ? 1.5 : 1,
                              ),
                              color: selected
                                  ? scheme.primary.withValues(alpha: 0.06)
                                  : scheme.surface,
                            ),
                            child: Row(
                              children: [
                                Radio<int>(
                                  value: index,
                                  groupValue: selectedIndex,
                                  onChanged: (v) => setSheetState(
                                    () => selectedIndex = v ?? 0,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      if (coverage != null &&
                                          coverage.isNotEmpty)
                                        Text(
                                          coverage,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, enabled[selectedIndex]),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: Text(L10n.tr(context, 'common.continue')),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _confirmArrangedCheckoutSummary({required double price}) async {
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          builder: (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.tr(context, 'checkout.arranged_summary_title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  _SummaryRow(
                    label: L10n.tr(context, 'checkout.price'),
                    value: '${price.toStringAsFixed(0)} DA',
                  ),
                  _SummaryRow(
                    label: L10n.tr(context, 'checkout.shipping'),
                    value: L10n.tr(context, 'checkout.delivery_pickup_title'),
                  ),
                  _SummaryRow(
                    label: L10n.tr(context, 'checkout.payment'),
                    value: PaymentLabels.methodLabel(
                      context,
                      'cod',
                      includeCodSuffix: true,
                    ),
                  ),
                  _SummaryRow(
                    label: L10n.tr(context, 'checkout.eta'),
                    value: L10n.tr(context, 'checkout.eta_pickup'),
                  ),
                  _SummaryRow(
                    label: L10n.tr(context, 'checkout.total'),
                    value: '${price.toStringAsFixed(0)} DA',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    L10n.tr(
                      context,
                      'checkout.arranged_summary_note',
                      fallback:
                          'Le vendeur confirmera les details de remise via le chat. Aucun bordereau automatique.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(L10n.tr(context, 'common.cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(
                            L10n.tr(
                              context,
                              'checkout.arranged_primary_cta',
                              fallback: 'Envoyer la demande',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
  }

  Future<bool> _confirmCheckoutSummary({
    required double price,
    required String shippingOption,
    required String paymentMethod,
    String? deliveryMode,
    double? shippingCost,
    String? etaLabel,
  }) async {
    final normalizedPayment = paymentMethod.trim().toLowerCase();
    final isCod = normalizedPayment == 'cod';
    return await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          builder: (context) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.tr(context, 'checkout.summary'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _SummaryRow(
                      label: L10n.tr(context, 'checkout.price'),
                      value: '${price.toStringAsFixed(0)} DA',
                    ),
                    if (shippingCost != null)
                      _SummaryRow(
                        label: L10n.tr(context, 'checkout.shipping_fee'),
                        value: '${shippingCost.toStringAsFixed(0)} DA',
                      ),
                    _SummaryRow(
                      label: L10n.tr(context, 'checkout.shipping'),
                      value: shippingOption,
                    ),
                    _SummaryRow(
                      label: L10n.tr(context, 'checkout.mode'),
                      value:
                          deliveryMode ??
                          L10n.tr(context, 'checkout.delivery_standard'),
                    ),
                    _SummaryRow(
                      label: L10n.tr(context, 'checkout.payment'),
                      value: PaymentLabels.methodLabel(
                        context,
                        paymentMethod,
                        includeCodSuffix: true,
                      ),
                    ),
                    if (isCod)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          L10n.tr(context, 'checkout.cod_pay_on_delivery_note'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (etaLabel != null)
                      _SummaryRow(
                        label: L10n.tr(context, 'checkout.eta'),
                        value: etaLabel,
                      ),
                    if (shippingCost != null)
                      _SummaryRow(
                        label: L10n.tr(context, 'checkout.total'),
                        value:
                            '${(price + shippingCost).toStringAsFixed(0)} DA',
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close),
                            label: Text(L10n.tr(context, 'common.cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(context, true),
                            icon: Icon(
                              isCod ? Icons.check_circle : Icons.payment,
                            ),
                            label: Text(
                              isCod
                                  ? L10n.tr(context, 'checkout.confirm_order')
                                  : L10n.tr(context, 'checkout.pay_now'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;
  }

  Future<void> _makeOffer() async {
    if (_product == null || !_product!.isNegotiable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.tr(
              context,
              'offers.not_negotiable',
              fallback: 'Ce produit n\'accepte pas les offres.',
            ),
          ),
        ),
      );
      return;
    }
    if (supabase.auth.currentUser?.id == null) {
      _redirectGuestToSignIn();
      return;
    }
    final minOffer = InputSanitizer.offerMinAmountFromBasePrice(
      _product?.price,
    );
    final amountController = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.tr(context, 'offers.make_offer')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'offers.amount_label'),
                helperText: L10n.tr(
                  context,
                  'offers.min_50_percent',
                  fallback:
                      'Offre minimum: DA ${minOffer.toStringAsFixed(0)} (50%).',
                  params: {'amount': minOffer.toStringAsFixed(0)},
                ),
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L10n.tr(context, 'common.cancel')),
          ),
          TextButton(
            onPressed: () async {
              try {
                final normalized = amountController.text.trim().replaceAll(
                  ',',
                  '.',
                );
                final parsed = double.tryParse(normalized);
                if (parsed == null) {
                  throw FormatException(
                    L10n.tr(
                      context,
                      'payment.invalid_amount',
                      fallback: 'Montant invalide',
                    ),
                  );
                }
                if (parsed < minOffer) {
                  throw FormatException(
                    L10n.tr(
                      context,
                      'offers.min_50_percent',
                      fallback:
                          'Offre minimum: DA ${minOffer.toStringAsFixed(0)} (50%).',
                      params: {'amount': minOffer.toStringAsFixed(0)},
                    ),
                  );
                }
                final amount = InputSanitizer.parseAmount(
                  normalized,
                  min: minOffer,
                );
                await _offerService.makeOffer(
                  productId: widget.productId,
                  sellerId: _product!.ownerId,
                  amount: amount,
                );
                if (context.mounted) Navigator.of(context).pop(true);
              } on FormatException catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(e.message)));
              } catch (e) {
                if (!context.mounted) return;
                final lower = e.toString().toLowerCase();
                final isMinOfferError = lower.contains('offer_below_min_ratio');
                final isNotNegotiableError = lower.contains(
                  'offer_not_negotiable',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isMinOfferError
                          ? L10n.tr(
                              context,
                              'offers.min_50_percent',
                              fallback:
                                  'Offre minimum: DA ${minOffer.toStringAsFixed(0)} (50%).',
                              params: {'amount': minOffer.toStringAsFixed(0)},
                            )
                          : isNotNegotiableError
                          ? L10n.tr(
                              context,
                              'offers.not_negotiable',
                              fallback: 'Ce produit n\'accepte pas les offres.',
                            )
                          : e.toString(),
                    ),
                  ),
                );
              }
            },
            child: Text(L10n.tr(context, 'common.send')),
          ),
        ],
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.tr(context, 'offers.sent', fallback: 'Offre envoyee.'),
          ),
        ),
      );
      await _contactSeller(sendIntroMessage: false);
    }
  }

  void _showInfoSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _redirectGuestToSignIn() {
    final from = Uri.encodeComponent('/product/${widget.productId}');
    context.go('/sign-in?from=$from');
  }

  void _promptLoginForFavorites() {
    _redirectGuestToSignIn();
  }

  Future<void> _toggleFavoriteWithFeedback(bool currentIsFavorite) async {
    final product = _product;
    if (product == null || _favoriteBusy) return;
    final nextIsFavorite = !currentIsFavorite;
    setState(() {
      _favoriteBusy = true;
      _favoriteOverride = nextIsFavorite;
    });
    try {
      await FavoriteService().toggleFavorite(
        productId: product.id,
        isFav: currentIsFavorite,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _favoriteOverride = currentIsFavorite;
      });
      _showInfoSnack(
        L10n.tr(context, 'common.error', fallback: 'Une erreur est survenue.'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _favoriteBusy = false;
        });
      }
    }
  }

  Future<void> _shareCurrentProduct() async {
    final product = _product;
    if (product == null) return;
    final uri = buildProductShareUri(
      productId: product.id,
      currentUri: Uri.base,
    );
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    _showInfoSnack(
      L10n.tr(
        context,
        'listing.share_link_copied',
        fallback: 'Lien du produit copie.',
      ),
    );
  }

  Future<void> _handleBackNavigation() async {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    if (!mounted) return;
    context.go('/?tab=listings');
  }

  Future<void> _openFullscreenGallery(
    List<String> images, {
    int initialIndex = 0,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _FullscreenGallery(images: images, initialIndex: initialIndex),
      ),
    );
  }

  Future<void> _openSellerProfile() async {
    final product = _product;
    if (product == null) return;
    if (supabase.auth.currentUser?.id == null) {
      _redirectGuestToSignIn();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicProfilePage(userId: product.ownerId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA');
    final screenSize = MediaQuery.sizeOf(context);
    final screenWidth = screenSize.width;
    final wideDesktopLayout = screenWidth >= 1200;
    final useWideDetailLayout = shouldUseWideDetailLayout(
      screenSize: screenSize,
      isWeb: kIsWeb,
    );
    final centeredContentWidth = wideDesktopLayout
        ? 1080.0
        : useWideDetailLayout
        ? 920.0
        : double.infinity;
    final heroExpandedHeight = wideDesktopLayout
        ? 320.0
        : useWideDetailLayout
        ? 340.0
        : 390.0;

    Widget contentShell(Widget child, {required EdgeInsetsGeometry padding}) {
      final paddedChild = Padding(padding: padding, child: child);
      if (!useWideDetailLayout) {
        return paddedChild;
      }
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: centeredContentWidth),
          child: paddedChild,
        ),
      );
    }

    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_product == null) {
      return Scaffold(
        body: Center(child: Text(L10n.tr(context, 'listing.not_found'))),
      );
    }

    const fallbackImage =
        'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=900&q=80';
    final heroImages = _product!.displayableImageUrls(fallback: fallbackImage);
    final selectedHeroIndex = _webHeroIndex.clamp(0, heroImages.length - 1);
    final agreedPrice =
        _acceptedOffer?.agreedAmount ??
        _acceptedOffer?.amount ??
        _product!.price;
    final isOwner = _isOwner;
    final outOfStock =
        (_product?.stockQuantity ?? 0) <= 0 || _product?.isArchived == true;
    final buyLabel = _acceptedOffer != null
        ? L10n.tr(
            context,
            'cta.buy_agreed',
            params: {'price': agreedPrice.toStringAsFixed(0)},
          )
        : isOwner
        ? L10n.tr(context, 'cta.own_listing')
        : outOfStock
        ? L10n.tr(context, 'cta.out_of_stock')
        : L10n.tr(context, 'cta.buy_now');
    final statusLabel = outOfStock
        ? L10n.tr(context, 'cta.out_of_stock')
        : L10n.tr(context, 'chat.room.status_available');
    final statusColor = outOfStock
        ? Colors.red.shade600
        : Theme.of(context).colorScheme.primary;
    final isNegotiable = _product!.isNegotiable;
    final primaryTags = _buildPrimaryTags(context);
    final allTags = _buildDetailTags(context);
    final sellerIsPublic = isTruthyFlag(_sellerProfile?['is_public']);
    final viewSellerProfile = _isOwner ? null : () => _openSellerProfile();

    Widget buildFavoriteButton() {
      if (supabase.auth.currentUser?.id != null) {
        return StreamBuilder<Set<String>>(
          stream: FavoriteService().streamFavorites(
            supabase.auth.currentUser!.id,
          ),
          builder: (context, snapshot) {
            final streamIsFav =
                snapshot.data?.contains(_product?.id ?? '') ?? false;
            final isFav = _favoriteOverride ?? streamIsFav;
            return _topOverlayIconButton(
              icon: isFav ? Icons.favorite : Icons.favorite_border,
              iconColor: Colors.white,
              backgroundColor: isFav
                  ? Colors.redAccent.withValues(alpha: 0.95)
                  : null,
              onPressed: _product == null || _favoriteBusy
                  ? null
                  : () => _toggleFavoriteWithFeedback(isFav),
            );
          },
        );
      }
      return _topOverlayIconButton(
        icon: Icons.favorite_border,
        onPressed: _promptLoginForFavorites,
      );
    }

    Widget buildReportMenuButton() {
      return Container(
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.46),
          shape: BoxShape.circle,
        ),
        child: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (v) {
            if (v == 'report') _reportListing(context, _product!);
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'report',
              child: Text(L10n.tr(context, 'report.menu')),
            ),
          ],
        ),
      );
    }

    Widget buildHeroCounter() {
      return Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '${selectedHeroIndex + 1}/${heroImages.length}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    List<Widget> buildHeroActions() {
      return [
        if (useWideDetailLayout && heroImages.length > 1) buildHeroCounter(),
        _topOverlayIconButton(
          icon: Icons.share,
          onPressed: _shareCurrentProduct,
        ),
        buildFavoriteButton(),
        buildReportMenuButton(),
      ];
    }

    Widget buildHeroSection() {
      final imagePrefs = NetworkPreferencesService.instance;
      final heroChild = useWideDetailLayout
          ? Stack(
              fit: StackFit.expand,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _openFullscreenGallery(
                      heroImages,
                      initialIndex: selectedHeroIndex,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: CachedNetworkImage(
                        key: ValueKey(heroImages[selectedHeroIndex]),
                        imageUrl: heroImages[selectedHeroIndex],
                        fit: BoxFit.cover,
                        memCacheWidth: imagePrefs.detailImageMemCacheWidth,
                        fadeInDuration: imagePrefs.imageFadeInDuration,
                        fadeOutDuration: imagePrefs.imageFadeOutDuration,
                        imageRenderMethodForWeb:
                            ImageRenderMethodForWeb.HttpGet,
                        errorWidget: (_, __, ___) => const ColoredBox(
                          color: Colors.black12,
                          child: Center(child: Icon(Icons.image_not_supported)),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.10),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (heroImages.length > 1)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.32),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: SizedBox(
                            height: 56,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: heroImages.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final active = index == selectedHeroIndex;
                                return InkWell(
                                  onTap: () =>
                                      setState(() => _webHeroIndex = index),
                                  borderRadius: BorderRadius.circular(12),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 56,
                                    height: 56,
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: active
                                            ? Colors.white
                                            : Colors.white.withValues(
                                                alpha: 0.45,
                                              ),
                                        width: active ? 2 : 1,
                                      ),
                                      color: Colors.black.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: CachedNetworkImage(
                                        imageUrl: heroImages[index],
                                        fit: BoxFit.cover,
                                        memCacheWidth: 160,
                                        fadeInDuration:
                                            imagePrefs.imageFadeInDuration,
                                        fadeOutDuration:
                                            imagePrefs.imageFadeOutDuration,
                                        imageRenderMethodForWeb:
                                            ImageRenderMethodForWeb.HttpGet,
                                        errorWidget: (_, __, ___) =>
                                            const ColoredBox(
                                              color: Colors.black12,
                                              child: Icon(
                                                Icons.image_not_supported,
                                                size: 18,
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : _ImageCarousel(controller: _pageController, images: heroImages);
      return SizedBox(
        height: heroExpandedHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            heroChild,
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 8,
              child: _topOverlayIconButton(
                icon: Icons.arrow_back,
                onPressed: _handleBackNavigation,
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: buildHeroActions(),
              ),
            ),
          ],
        ),
      );
    }

    // ignore: unused_local_variable
    final detailBodyContent = contentShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _product!.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                formatter.format(agreedPrice),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_acceptedOffer != null)
                Chip(
                  label: Text(L10n.tr(context, 'offer.agreed')),
                  visualDensity: VisualDensity.compact,
                ),
              if (isNegotiable)
                Chip(
                  label: Text(
                    L10n.tr(
                      context,
                      'listing.negotiable',
                      fallback: 'Prix negociable',
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (primaryTags.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final tag in primaryTags) Chip(label: Text(tag))],
            ),
          if (allTags.length > primaryTags.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ActionChip(
                avatar: const Icon(Icons.tune, size: 16),
                label: Text(
                  L10n.tr(context, 'listing.details', fallback: 'Details'),
                ),
                onPressed: () => _showAllTagsSheet(context, allTags),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(
                  L10n.tr(
                    context,
                    'listing.detail.stock',
                    params: {'value': _product!.stockQuantity.toString()},
                  ),
                ),
              ),
              if (_product!.soldCount > 0)
                Chip(
                  label: Text(
                    L10n.tr(
                      context,
                      'listing.detail.sold',
                      params: {'value': _product!.soldCount.toString()},
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _SellerRowFixed(
            ownerId: _product!.ownerId,
            sellerName: _sellerProfile?['full_name']?.toString(),
            sellerAvatar: _sellerProfile?['avatar_url']?.toString(),
            sellerIsPublic: sellerIsPublic,
            onContact: _contactSeller,
            onViewProfile: viewSellerProfile,
          ),
          const SizedBox(height: 16),
          Divider(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            _product!.description ?? L10n.tr(context, 'listing.no_description'),
          ),
          const SizedBox(height: 100),
        ],
      ),
      padding: const EdgeInsets.all(16),
    );

    final webDetailBodyContent = contentShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _product!.title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            formatter.format(agreedPrice),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (primaryTags.isNotEmpty)
                for (final tag in primaryTags) Chip(label: Text(tag)),
              Chip(
                label: Text(
                  L10n.tr(
                    context,
                    'listing.detail.stock',
                    params: {'value': _product!.stockQuantity.toString()},
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _isOwner || outOfStock ? null : _buyNow,
                icon: const Icon(Icons.shopping_bag_outlined),
                label: Text(buyLabel),
              ),
              if (isNegotiable)
                OutlinedButton.icon(
                  onPressed: _isOwner || outOfStock ? null : _makeOffer,
                  icon: const Icon(Icons.handshake_outlined),
                  label: Text(L10n.tr(context, 'offers.make_offer')),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _product!.description ?? L10n.tr(context, 'listing.no_description'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 18),
          _SellerRowFixed(
            ownerId: _product!.ownerId,
            sellerName: _sellerProfile?['full_name']?.toString(),
            sellerAvatar: _sellerProfile?['avatar_url']?.toString(),
            sellerIsPublic: sellerIsPublic,
            onContact: _contactSeller,
            onViewProfile: viewSellerProfile,
          ),
          const SizedBox(height: 100),
        ],
      ),
      padding: const EdgeInsets.all(16),
    );

    return Scaffold(
      body: useWideDetailLayout
          ? SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                controller: _detailScrollController,
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [buildHeroSection(), webDetailBodyContent],
                ),
              ),
            ) /*
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _product!.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            formatter.format(agreedPrice),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (_acceptedOffer != null)
                            Chip(
                              label: Text(L10n.tr(context, 'offer.agreed')),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (isNegotiable)
                            Chip(
                              label: Text(
                                L10n.tr(
                                  context,
                                  'listing.negotiable',
                                  fallback: 'Prix negociable',
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (primaryTags.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in primaryTags) Chip(label: Text(tag)),
                          ],
                        ),
                      if (allTags.length > primaryTags.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ActionChip(
                            avatar: const Icon(Icons.tune, size: 16),
                            label: Text(
                              L10n.tr(
                                context,
                                'listing.details',
                                fallback: 'Details',
                              ),
                            ),
                            onPressed: () => _showAllTagsSheet(context, allTags),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(
                              L10n.tr(
                                context,
                                'listing.detail.stock',
                                params: {
                                  'value': _product!.stockQuantity.toString(),
                                },
                              ),
                            ),
                          ),
                          if (_product!.soldCount > 0)
                            Chip(
                              label: Text(
                                L10n.tr(
                                  context,
                                  'listing.detail.sold',
                                  params: {
                                    'value': _product!.soldCount.toString(),
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
          _SellerRowFixed(
            ownerId: _product!.ownerId,
            sellerName: _sellerProfile?['full_name']?.toString(),
            sellerAvatar: _sellerProfile?['avatar_url']?.toString(),
            sellerIsPublic: sellerIsPublic,
            onContact: _contactSeller,
            onViewProfile: viewSellerProfile,
          ),
                      const SizedBox(height: 16),
                      Divider(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _product!.description ??
                            L10n.tr(context, 'listing.no_description'),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                ),
              ],
            ) */
          : CustomScrollView(
              controller: _detailScrollController,
              primary: false,
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: heroExpandedHeight,
                  leading: _topOverlayIconButton(
                    icon: Icons.arrow_back,
                    onPressed: _handleBackNavigation,
                  ),
                  actions: buildHeroActions(),
                  flexibleSpace: FlexibleSpaceBar(
                    background: _ImageCarousel(
                      controller: _pageController,
                      images: heroImages,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: contentShell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _product!.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              formatter.format(agreedPrice),
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                statusLabel,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: statusColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            if (_acceptedOffer != null)
                              Chip(
                                label: Text(L10n.tr(context, 'offer.agreed')),
                                visualDensity: VisualDensity.compact,
                              ),
                            if (isNegotiable)
                              Chip(
                                label: Text(
                                  L10n.tr(
                                    context,
                                    'listing.negotiable',
                                    fallback: 'Prix negociable',
                                  ),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (primaryTags.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final tag in primaryTags)
                                Chip(label: Text(tag)),
                            ],
                          ),
                        if (allTags.length > primaryTags.length)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ActionChip(
                              avatar: const Icon(Icons.tune, size: 16),
                              label: Text(
                                L10n.tr(
                                  context,
                                  'listing.details',
                                  fallback: 'Details',
                                ),
                              ),
                              onPressed: () =>
                                  _showAllTagsSheet(context, allTags),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                              label: Text(
                                L10n.tr(
                                  context,
                                  'listing.detail.stock',
                                  params: {
                                    'value': _product!.stockQuantity.toString(),
                                  },
                                ),
                              ),
                            ),
                            if (_product!.soldCount > 0)
                              Chip(
                                label: Text(
                                  L10n.tr(
                                    context,
                                    'listing.detail.sold',
                                    params: {
                                      'value': _product!.soldCount.toString(),
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _SellerRowFixed(
                          ownerId: _product!.ownerId,
                          sellerName: _sellerProfile?['full_name']?.toString(),
                          sellerAvatar: _sellerProfile?['avatar_url']
                              ?.toString(),
                          sellerIsPublic: sellerIsPublic,
                          onContact: _contactSeller,
                          onViewProfile: viewSellerProfile,
                        ),
                        const SizedBox(height: 16),
                        Divider(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _product!.description ??
                              L10n.tr(context, 'listing.no_description'),
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: useWideDetailLayout
          ? null
          : SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: contentShell(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatter.format(agreedPrice),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (_product!.stockQuantity > 0)
                            Text(
                              L10n.tr(
                                context,
                                'listing.detail.stock',
                                params: {
                                  'value': _product!.stockQuantity.toString(),
                                },
                              ),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isOwner || outOfStock
                                  ? null
                                  : _buyNow,
                              icon: const Icon(Icons.shopping_bag_outlined),
                              label: Text(buyLabel),
                            ),
                          ),
                          if (isNegotiable) ...[
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: _isOwner || outOfStock
                                  ? null
                                  : _makeOffer,
                              icon: const Icon(Icons.handshake_outlined),
                              label: Text(
                                L10n.tr(context, 'offers.make_offer'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                ),
              ),
            ),
    );
  }
}

class _CheckoutAddressSheet extends StatefulWidget {
  const _CheckoutAddressSheet({
    required this.product,
    required this.sellerId,
    required this.courierId,
    required this.courierName,
    required this.buyerProfile,
    required this.buyerWilaya,
    required this.sellerWilaya,
    required this.lastCheckout,
    required this.onSaveLastCheckout,
    required this.defaultPrice,
    required this.productTitle,
  });

  final Product? product;
  final String sellerId;
  final String courierId;
  final String courierName;
  final Map<String, dynamic>? buyerProfile;
  final String? buyerWilaya;
  final String? sellerWilaya;
  final Map<String, dynamic>? lastCheckout;
  final Future<void> Function(Map<String, dynamic>) onSaveLastCheckout;
  final double defaultPrice;
  final String productTitle;

  @override
  State<_CheckoutAddressSheet> createState() => _CheckoutAddressSheetState();
}

class _CheckoutAddressSheetState extends State<_CheckoutAddressSheet> {
  final _formKey = GlobalKey<FormState>();
  final _shippingService = ShippingService();

  List<Map<String, String>> _wilayas = [];
  List<Map<String, String>> _communes = [];
  List<Map<String, String>> _stopdeskCommunes = [];

  bool _loadingWilayas = false;
  bool _loadingCommunes = false;
  String? _loadError;

  String? _senderWilayaId;
  String? _senderWilayaName;
  String? _receiverWilayaId;
  String? _receiverWilayaName;
  String? _receiverCommuneId;
  String? _receiverCommuneName;
  String? _stopdeskCommuneName;
  String? _stopdeskId;

  String _deliveryType = 'home';
  bool _acceptTerms = false;
  bool _exchangeAfterDelivery = false;
  bool _freeShipping = false;
  bool _insuranceActive = false;
  bool _allowStopdesk = true;
  bool _isEcotrack = false;
  bool _isZrExpress = false;
  bool _supportsStopdeskList = true;
  late CourierParcelRules _parcelRules;
  double? _estimatedFee;
  bool _estimatingFee = false;
  String? _estimateError;
  String? _feeSource;
  Timer? _feeRefreshDebounce;

  late TextEditingController _firstNameCtrl;
  late TextEditingController _familyNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _phone2Ctrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _dairaCtrl;
  late TextEditingController _zipCtrl;
  late TextEditingController _productListCtrl;
  late TextEditingController _orderNumberCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _declaredValueCtrl;
  late TextEditingController _weightCtrl;
  late TextEditingController _heightCtrl;
  late TextEditingController _widthCtrl;
  late TextEditingController _lengthCtrl;

  @override
  void initState() {
    super.initState();
    _isEcotrack =
        widget.courierId.toLowerCase().contains('ecotrack') ||
        widget.courierName.toLowerCase().contains('ecotrack');
    _isZrExpress = ShippingService.isZrExpressCourier(
      courierId: widget.courierId,
      courierName: widget.courierName,
    );
    _parcelRules = ShippingService.parcelRulesFor(
      courierId: widget.courierId,
      courierName: widget.courierName,
    );
    _loadParcelRules();
    final product = widget.product;
    _freeShipping = product?.shippingFree ?? false;
    _exchangeAfterDelivery = product?.exchangeAfterDelivery ?? false;
    _insuranceActive = product?.insuranceActive ?? false;
    _allowStopdesk = product?.allowStopdesk ?? true;
    _supportsStopdeskList = !_isEcotrack;
    final fullName = widget.buyerProfile?['full_name']?.toString() ?? '';
    final nameParts = fullName
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final familyName = nameParts.length > 1
        ? nameParts.sublist(1).join(' ')
        : '';
    _firstNameCtrl = TextEditingController(
      text: widget.lastCheckout?['firstname']?.toString() ?? firstName,
    );
    _familyNameCtrl = TextEditingController(
      text: widget.lastCheckout?['familyname']?.toString() ?? familyName,
    );
    _phoneCtrl = TextEditingController(
      text:
          widget.buyerProfile?['phone']?.toString() ??
          widget.lastCheckout?['phone']?.toString() ??
          '',
    );
    _phone2Ctrl = TextEditingController(
      text: widget.lastCheckout?['phone2']?.toString() ?? '',
    );
    _addressCtrl = TextEditingController(
      text: widget.lastCheckout?['address']?.toString() ?? '',
    );
    _dairaCtrl = TextEditingController(
      text:
          widget.lastCheckout?['receiverDaira']?.toString() ??
          widget.buyerProfile?['daira']?.toString() ??
          '',
    );
    _zipCtrl = TextEditingController(
      text: widget.lastCheckout?['zip']?.toString() ?? '',
    );
    _productListCtrl = TextEditingController(text: widget.productTitle);
    _orderNumberCtrl = TextEditingController(text: 'auto');
    _priceCtrl = TextEditingController(
      text: widget.defaultPrice.toStringAsFixed(0),
    );
    final declaredValue = product?.declaredValue ?? widget.defaultPrice;
    _declaredValueCtrl = TextEditingController(
      text: declaredValue.toStringAsFixed(0),
    );
    final weightValue = product?.weightKg ?? 1;
    _weightCtrl = TextEditingController(text: weightValue.toString());
    final heightValue = product?.heightCm ?? 0;
    _heightCtrl = TextEditingController(text: heightValue.toString());
    final widthValue = product?.widthCm ?? 0;
    _widthCtrl = TextEditingController(text: widthValue.toString());
    final lengthValue = product?.lengthCm ?? 0;
    _lengthCtrl = TextEditingController(text: lengthValue.toString());
    if (_freeShipping) {
      _estimatedFee = 0;
      _feeSource = 'free_shipping';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadWilayas();
      }
    });
  }

  Future<void> _loadParcelRules() async {
    try {
      final remoteRules = await ShippingService.parcelRulesForAsync(
        courierId: widget.courierId,
        courierName: widget.courierName,
      );
      if (!mounted) return;
      setState(() {
        _parcelRules = remoteRules;
      });
    } catch (_) {
      // Keep default fallback rules if DB/rules fetch is unavailable.
    }
  }

  @override
  void dispose() {
    _feeRefreshDebounce?.cancel();
    _firstNameCtrl.dispose();
    _familyNameCtrl.dispose();
    _phoneCtrl.dispose();
    _phone2Ctrl.dispose();
    _addressCtrl.dispose();
    _dairaCtrl.dispose();
    _zipCtrl.dispose();
    _productListCtrl.dispose();
    _orderNumberCtrl.dispose();
    _priceCtrl.dispose();
    _declaredValueCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _widthCtrl.dispose();
    _lengthCtrl.dispose();
    super.dispose();
  }

  void _scheduleFeeRefresh({
    Duration delay = const Duration(milliseconds: 350),
  }) {
    _feeRefreshDebounce?.cancel();
    _feeRefreshDebounce = Timer(delay, () {
      if (!mounted) return;
      unawaited(_refreshEstimatedFee());
    });
  }

  String _wilayaName(Map<String, String> w) => w['name'] ?? '';
  String _wilayaId(Map<String, String> w) => w['id'] ?? w['code'] ?? '';
  String _wilayaDisplayName(Map<String, String> w) {
    final name = _wilayaName(w);
    final rawId = _wilayaId(w).trim();
    final numeric = int.tryParse(rawId);
    if (numeric == null) return name;
    final normalized = rawId.padLeft(2, '0');
    return '$normalized - $name';
  }

  String _communeName(Map<String, String> c) => c['name'] ?? '';
  bool _communeHasStopdesk(Map<String, String> c) =>
      c['has_stop_desk'] == 'true' || c['has_stop_desk'] == '1';

  List<Map<String, String>> _mapFallbackWilayas(
    List<Map<String, String>> rows,
    String locale,
  ) {
    return rows
        .map(
          (r) => {
            'id': r['code'] ?? '',
            'code': r['code'] ?? '',
            'name':
                (locale == 'ar' ? r['name_ar'] : r['name_fr']) ??
                r['name_fr'] ??
                r['name_ar'] ??
                '',
          },
        )
        .where((m) => m['code']!.isNotEmpty && m['name']!.isNotEmpty)
        .toList();
  }

  List<Map<String, String>> _mapFallbackCommunes(
    List<Map<String, String>> rows,
    String wilayaCode,
    String locale,
  ) {
    return rows
        .map(
          (r) => {
            'id': r['id'] ?? r['name_fr'] ?? r['name_ar'] ?? '',
            'name':
                (locale == 'ar' ? r['name_ar'] : r['name_fr']) ??
                r['name_fr'] ??
                r['name_ar'] ??
                '',
            'wilaya_id': wilayaCode,
            'has_stop_desk': '0',
            'stopdesk_id': '',
          },
        )
        .where((m) => m['name']!.isNotEmpty)
        .toList();
  }

  Future<void> _loadWilayas() async {
    if (!mounted) return;
    final locale = Localizations.localeOf(context).languageCode;
    setState(() {
      _loadingWilayas = true;
      _loadError = null;
    });
    try {
      _wilayas = await _shippingService.fetchCourierWilayas(
        courierId: widget.courierId,
        sellerId: widget.sellerId,
      );
      if (_wilayas.isEmpty) {
        final fallback = await LocationDataService.instance.fetchWilayas();
        _wilayas = _mapFallbackWilayas(fallback, locale);
      }
      if (_wilayas.isNotEmpty) {
        _wilayas.sort((a, b) {
          final aNum = int.tryParse(_wilayaId(a));
          final bNum = int.tryParse(_wilayaId(b));
          if (aNum != null && bNum != null) {
            return aNum.compareTo(bNum);
          }
          if (aNum != null) return -1;
          if (bNum != null) return 1;
          return _wilayaName(a).compareTo(_wilayaName(b));
        });
      }
      if (_wilayas.isEmpty) {
        _loadError = _isZrExpress
            ? L10n.trLocale(locale, 'location.error_zr_locations')
            : L10n.trLocale(locale, 'location.error_no_wilayas');
      }
    } catch (_) {
      _loadError = _isZrExpress
          ? L10n.trLocale(locale, 'location.error_zr_locations')
          : L10n.trLocale(locale, 'location.error_wilayas_load');
    } finally {
      if (mounted) {
        setState(() {
          _loadingWilayas = false;
        });
      } else {
        _loadingWilayas = false;
      }
    }

    final senderPrefId = widget.lastCheckout?['senderWilayaId']?.toString();
    final senderPref =
        widget.lastCheckout?['senderWilaya']?.toString() ??
        widget.sellerWilaya ??
        widget.buyerWilaya;
    if (senderPref != null && _wilayas.isNotEmpty) {
      Map<String, String> match = {};
      if (senderPrefId != null && senderPrefId.isNotEmpty) {
        match = _wilayas.firstWhere(
          (w) => _wilayaId(w) == senderPrefId,
          orElse: () => {},
        );
      }
      if (match.isEmpty) {
        match = _wilayas.firstWhere(
          (w) => _wilayaName(w).toLowerCase() == senderPref.toLowerCase(),
          orElse: () => {},
        );
      }
      if (match.isNotEmpty) {
        _senderWilayaId = _wilayaId(match);
        _senderWilayaName = _wilayaName(match);
      }
    }

    final receiverPrefId = widget.lastCheckout?['receiverWilayaId']?.toString();
    final receiverPref =
        widget.lastCheckout?['receiverWilaya']?.toString() ??
        widget.buyerProfile?['wilaya']?.toString();
    if (_wilayas.isNotEmpty) {
      Map<String, String> match = {};
      if (receiverPrefId != null && receiverPrefId.isNotEmpty) {
        match = _wilayas.firstWhere(
          (w) => _wilayaId(w) == receiverPrefId,
          orElse: () => {},
        );
      }
      if (match.isEmpty && receiverPref != null) {
        match = _wilayas.firstWhere(
          (w) => _wilayaName(w).toLowerCase() == receiverPref.toLowerCase(),
          orElse: () => {},
        );
      }
      if (match.isNotEmpty) {
        _receiverWilayaId = _wilayaId(match);
        _receiverWilayaName = _wilayaName(match);
      }
    }

    if (_receiverWilayaId != null) {
      await _loadCommunes(_receiverWilayaId!);
    }

    if (mounted) {
      setState(() {});
      _scheduleFeeRefresh(delay: Duration.zero);
    }
  }

  Future<void> _loadCommunes(String wilayaId) async {
    if (!mounted) return;
    final locale = Localizations.localeOf(context).languageCode;
    setState(() {
      _loadingCommunes = true;
      _loadError = null;
      _communes = [];
      _stopdeskCommunes = [];
      _receiverCommuneName = null;
      _receiverCommuneId = null;
      _stopdeskCommuneName = null;
      _stopdeskId = null;
    });
    try {
      _communes = await _shippingService.fetchCourierCommunes(
        courierId: widget.courierId,
        wilayaCode: wilayaId,
        sellerId: widget.sellerId,
      );
      if (_communes.isEmpty) {
        final numeric = int.tryParse(wilayaId.trim());
        if (numeric != null) {
          final code = numeric.toString().padLeft(2, '0');
          final fallback = await LocationDataService.instance.fetchCommunes(
            code,
          );
          _communes = _mapFallbackCommunes(fallback, code, locale);
        }
      }
      _stopdeskCommunes = _supportsStopdeskList
          ? _communes.where(_communeHasStopdesk).toList(growable: false)
          : _communes;
      if (_communes.isEmpty) {
        _loadError = _isZrExpress
            ? L10n.trLocale(locale, 'location.error_zr_locations')
            : L10n.trLocale(locale, 'location.error_no_communes');
      }
    } catch (_) {
      _loadError = _isZrExpress
          ? L10n.trLocale(locale, 'location.error_zr_locations')
          : L10n.trLocale(locale, 'location.error_communes_load');
    } finally {
      if (mounted) {
        setState(() {
          _loadingCommunes = false;
        });
      } else {
        _loadingCommunes = false;
      }
    }

    final preferredCommuneId = widget.lastCheckout?['receiverCommuneId']
        ?.toString();
    final preferredCommuneName = widget.lastCheckout?['receiverCommune']
        ?.toString();
    if (_communes.isNotEmpty) {
      Map<String, String> match = {};
      if (preferredCommuneId != null && preferredCommuneId.isNotEmpty) {
        match = _communes.firstWhere(
          (c) => (c['id']?.toString() ?? '') == preferredCommuneId,
          orElse: () => {},
        );
      }
      if (match.isEmpty &&
          preferredCommuneName != null &&
          preferredCommuneName.isNotEmpty) {
        match = _communes.firstWhere(
          (c) =>
              _communeName(c).toLowerCase() ==
              preferredCommuneName.toLowerCase(),
          orElse: () => {},
        );
      }
      if (match.isNotEmpty) {
        _receiverCommuneName = _communeName(match);
        _receiverCommuneId = match['id']?.toString();
      }
    }
    unawaited(_refreshEstimatedFee());
  }

  Future<void> _refreshEstimatedFee() async {
    if (!mounted) return;
    if (_freeShipping) {
      setState(() {
        _estimatedFee = 0;
        _estimateError = null;
        _feeSource = 'free_shipping';
        _estimatingFee = false;
      });
      return;
    }
    if (_senderWilayaId == null || _receiverWilayaId == null) {
      setState(() {
        _estimatedFee = null;
        _estimateError = null;
        _feeSource = null;
        _estimatingFee = false;
      });
      return;
    }
    final weight = int.tryParse(_weightCtrl.text.trim());
    final height = int.tryParse(_heightCtrl.text.trim());
    final width = int.tryParse(_widthCtrl.text.trim());
    final length = int.tryParse(_lengthCtrl.text.trim());
    final price = double.tryParse(_priceCtrl.text.trim());
    final declaredValue = double.tryParse(_declaredValueCtrl.text.trim());
    if (weight == null || height == null || width == null || length == null) {
      setState(() {
        _estimatedFee = null;
        _estimateError = null;
        _feeSource = null;
        _estimatingFee = false;
      });
      return;
    }
    setState(() {
      _estimatingFee = true;
      _estimateError = null;
    });
    try {
      final quote = await _shippingService.estimateCheckoutShippingFee(
        sellerId: widget.sellerId,
        courierId: widget.courierId,
        courierName: widget.courierName,
        productId: widget.product?.id,
        deliveryType: _deliveryType,
        senderWilayaId: _senderWilayaId,
        senderWilayaName: _senderWilayaName,
        receiverWilayaId: _receiverWilayaId,
        receiverWilayaName: _receiverWilayaName,
        receiverCommuneId: _receiverCommuneId,
        receiverCommuneName: _receiverCommuneName,
        price: price ?? widget.defaultPrice,
        declaredValue: declaredValue,
        weightKg: weight,
        heightCm: height,
        widthCm: width,
        lengthCm: length,
      );
      if (!mounted) return;
      setState(() {
        _estimatedFee = quote?.fee;
        _feeSource = quote?.source;
        _estimatingFee = false;
        _estimateError = quote == null
            ? L10n.tr(context, 'checkout.fees_unavailable')
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _estimatedFee = null;
        _feeSource = null;
        _estimatingFee = false;
        _estimateError = L10n.tr(context, 'checkout.fees_unavailable');
      });
    }
  }

  bool _isPhoneValid(String value) =>
      RegExp(r'^(05|06|07)\d{8}$').hasMatch(value.trim());

  CourierParcelValidation? _parcelValidation() {
    final weight = int.tryParse(_weightCtrl.text.trim());
    final height = int.tryParse(_heightCtrl.text.trim());
    final width = int.tryParse(_widthCtrl.text.trim());
    final length = int.tryParse(_lengthCtrl.text.trim());
    final price = double.tryParse(_priceCtrl.text.trim());
    final declaredValue = double.tryParse(_declaredValueCtrl.text.trim());
    return ShippingService.validateParcel(
      rules: _parcelRules,
      weightKg: weight,
      heightCm: height,
      widthCm: width,
      lengthCm: length,
      declaredValue: declaredValue,
      codAmount: price,
      insuranceActive: _insuranceActive,
    );
  }

  String _parcelValidationMessage(CourierParcelValidation validation) {
    switch (validation.code) {
      case 'weight_range':
        return L10n.tr(
          context,
          'checkout.error_weight_range',
          params: validation.params,
        );
      case 'height_max':
        return L10n.tr(
          context,
          'checkout.error_height_max',
          params: validation.params,
          fallback: L10n.tr(context, 'checkout.error_height_invalid'),
        );
      case 'width_max':
        return L10n.tr(
          context,
          'checkout.error_width_max',
          params: validation.params,
          fallback: L10n.tr(context, 'checkout.error_width_invalid'),
        );
      case 'length_max':
        return L10n.tr(
          context,
          'checkout.error_length_max',
          params: validation.params,
          fallback: L10n.tr(context, 'checkout.error_length_invalid'),
        );
      case 'volume_max':
        return L10n.tr(
          context,
          'checkout.error_volume_max',
          params: validation.params,
          fallback: L10n.tr(context, 'checkout.error_length_invalid'),
        );
      case 'declared_value_max':
        return L10n.tr(
          context,
          'checkout.error_declared_value_max',
          params: validation.params,
          fallback: L10n.tr(context, 'checkout.error_price_required'),
        );
      case 'cod_amount_max':
        return L10n.tr(
          context,
          'checkout.error_cod_amount_max',
          params: validation.params,
          fallback: L10n.tr(context, 'checkout.error_price_required'),
        );
      default:
        return L10n.tr(context, 'common.error');
    }
  }

  Widget _buildParcelRulesCard(BuildContext context) {
    final chips = <Widget>[
      _buildRuleChip(
        context,
        L10n.tr(
          context,
          'checkout.parcel_limits_weight',
          params: {
            'min': _parcelRules.minWeightKg.toString(),
            'max': _parcelRules.maxWeightKg.toString(),
          },
        ),
      ),
      _buildRuleChip(
        context,
        L10n.tr(
          context,
          'checkout.parcel_limits_dimensions',
          params: {
            'h': _parcelRules.maxHeightCm.toString(),
            'w': _parcelRules.maxWidthCm.toString(),
            'l': _parcelRules.maxLengthCm.toString(),
          },
        ),
      ),
      _buildRuleChip(
        context,
        L10n.tr(
          context,
          'checkout.parcel_limits_volume',
          params: {'max': _parcelRules.maxVolumeCm3.toString()},
        ),
      ),
      _buildRuleChip(
        context,
        L10n.tr(
          context,
          'checkout.parcel_limits_overweight',
          params: {'kg': _parcelRules.overweightThresholdKg.toString()},
        ),
      ),
      _buildRuleChip(
        context,
        L10n.tr(
          context,
          'checkout.parcel_limits_declared_value',
          params: {'max': _parcelRules.maxDeclaredValue.toStringAsFixed(0)},
        ),
      ),
      _buildRuleChip(
        context,
        L10n.tr(
          context,
          'checkout.parcel_limits_cod',
          params: {'max': _parcelRules.maxCodAmount.toStringAsFixed(0)},
        ),
      ),
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.tr(context, 'checkout.parcel_limits_title'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }

  Widget _buildRuleChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  void _openParcelLimitsSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildParcelRulesCard(sheetContext),
          ),
        );
      },
    );
  }

  Widget _buildParcelRulesCta(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: _openParcelLimitsSheet,
        icon: const Icon(Icons.info_outline),
        label: Text(L10n.tr(context, 'checkout.view_limits')),
      ),
    );
  }

  bool get _canSubmit {
    final phoneOk = _isZrExpress
        ? PhoneFormatter.isZrExpressCompatible(_phoneCtrl.text)
        : _isPhoneValid(_phoneCtrl.text);
    final baseValid =
        !_loadingWilayas &&
        !_loadingCommunes &&
        _loadError == null &&
        _senderWilayaName != null &&
        _receiverWilayaName != null &&
        _receiverCommuneName != null &&
        _dairaCtrl.text.trim().isNotEmpty &&
        _firstNameCtrl.text.trim().isNotEmpty &&
        _familyNameCtrl.text.trim().isNotEmpty &&
        phoneOk &&
        _addressCtrl.text.trim().isNotEmpty &&
        _productListCtrl.text.trim().isNotEmpty &&
        _priceCtrl.text.trim().isNotEmpty &&
        _acceptTerms;
    if (!baseValid) return false;
    if (_parcelValidation() != null) return false;
    if (!_freeShipping && _estimatedFee == null) return false;
    if (_deliveryType == 'stopdesk') {
      if (_supportsStopdeskList) {
        return _stopdeskId != null && _stopdeskCommuneName != null;
      }
      return _stopdeskCommuneName != null;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final price = int.tryParse(_priceCtrl.text.trim());
    final weight = int.tryParse(_weightCtrl.text.trim());
    final height = int.tryParse(_heightCtrl.text.trim()) ?? 0;
    final width = int.tryParse(_widthCtrl.text.trim()) ?? 0;
    final length = int.tryParse(_lengthCtrl.text.trim()) ?? 0;
    if (price == null || weight == null) return;
    final declaredValue =
        double.tryParse(_declaredValueCtrl.text.trim()) ?? price.toDouble();
    final validation = _parcelValidation();
    if (validation != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_parcelValidationMessage(validation))),
        );
      }
      return;
    }
    if (!_freeShipping) {
      await _refreshEstimatedFee();
      if (!mounted) return;
      if (_estimatedFee == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tr(context, 'checkout.fees_unavailable')),
          ),
        );
        return;
      }
    }

    final phoneMain = _phoneCtrl.text.trim();
    final phone2 = _phone2Ctrl.text.trim();
    final phoneE164 = _isZrExpress
        ? PhoneFormatter.normalizeDzE164ForZr(phoneMain)
        : '';
    final phone2E164 = _isZrExpress && phone2.isNotEmpty
        ? PhoneFormatter.normalizeDzE164ForZr(phone2)
        : '';
    final phoneCombined = _isZrExpress
        ? phoneE164
        : (phone2.isEmpty ? phoneMain : '$phoneMain,$phone2');

    final selection = {
      'courierId': widget.courierId,
      'courierName': widget.courierName,
      'deliveryType': _deliveryType,
      'senderWilayaId': _senderWilayaId,
      'senderWilaya': _senderWilayaName,
      'receiverWilaya': _receiverWilayaName,
      'receiverWilayaId': _receiverWilayaId,
      'receiverDaira': _dairaCtrl.text.trim(),
      'receiverCommune': _receiverCommuneName,
      'receiverCommuneId': _receiverCommuneId,
      'wilayaCode': _receiverWilayaId,
      'stopdeskId': _stopdeskId,
      'stopdeskCommune': _stopdeskCommuneName,
      'firstname': _firstNameCtrl.text.trim(),
      'familyname': _familyNameCtrl.text.trim(),
      'phone': phoneCombined,
      'phone_main': phoneMain,
      if (_isZrExpress && phoneE164.isNotEmpty) 'phone_e164': phoneE164,
      if (_isZrExpress && phone2E164.isNotEmpty) 'phone2_e164': phone2E164,
      'phone_secondary': phone2,
      'phone2': phone2,
      'address': _addressCtrl.text.trim(),
      'zip': _zipCtrl.text.trim(),
      'productList': _productListCtrl.text.trim(),
      'price': price,
      'declaredValue': declaredValue,
      'weight': weight,
      'height': height,
      'width': width,
      'length': length,
      'freeshipping': _freeShipping,
      'hasExchange': _exchangeAfterDelivery,
      'insuranceActive': _insuranceActive,
      'insurance_active': _insuranceActive,
      'acceptTerms': _acceptTerms,
      'estimatedFee': _estimatedFee,
      'estimatedFeeSource': _feeSource,
    };

    await widget.onSaveLastCheckout(selection);
    if (!mounted) return;
    Navigator.of(context).pop(selection);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: media.viewInsets.bottom + media.padding.bottom + 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loadingWilayas || _loadingCommunes)
                  const LinearProgressIndicator(minHeight: 3),
                Text(
                  L10n.tr(context, 'checkout.delivery_type'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                RadioListTile<String>(
                  value: 'home',
                  groupValue: _deliveryType,
                  title: Text(L10n.tr(context, 'checkout.delivery_home')),
                  onChanged: (v) {
                    setState(() => _deliveryType = v ?? 'home');
                    _scheduleFeeRefresh(delay: Duration.zero);
                  },
                ),
                if (_allowStopdesk)
                  RadioListTile<String>(
                    value: 'stopdesk',
                    groupValue: _deliveryType,
                    title: Text(L10n.tr(context, 'checkout.delivery_stopdesk')),
                    onChanged: (v) {
                      setState(() => _deliveryType = v ?? 'stopdesk');
                      _scheduleFeeRefresh(delay: Duration.zero);
                    },
                  ),
                _buildParcelRulesCta(context),
                const SizedBox(height: 8),
                Text(
                  L10n.tr(context, 'checkout.sender'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                DropdownButtonFormField<String>(
                  value: _senderWilayaId,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.sender_wilaya_label'),
                  ),
                  items: _wilayas
                      .map(
                        (w) => DropdownMenuItem(
                          value: _wilayaId(w),
                          child: Text(_wilayaDisplayName(w)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    final match = _wilayas.firstWhere(
                      (w) => _wilayaId(w) == v,
                      orElse: () => {},
                    );
                    setState(() {
                      _senderWilayaId = v;
                      _senderWilayaName = _wilayaName(match);
                    });
                    _scheduleFeeRefresh();
                  },
                  validator: (_) => _senderWilayaId == null
                      ? L10n.tr(context, 'checkout.error_wilaya_required')
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  L10n.tr(context, 'checkout.receiver'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                TextFormField(
                  controller: _familyNameCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.first_name'),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? L10n.tr(context, 'checkout.error_name_required')
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _firstNameCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.last_name'),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? L10n.tr(context, 'checkout.error_name_required')
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.phone1'),
                    helperText: _isZrExpress
                        ? L10n.tr(context, 'checkout.zr_phone_hint')
                        : L10n.tr(context, 'checkout.phone_example'),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) {
                      return L10n.tr(context, 'checkout.error_phone_required');
                    }
                    final ok = RegExp(r'^(05|06|07)\d{8}$').hasMatch(value);
                    if (!ok) {
                      return L10n.tr(context, 'checkout.error_phone_invalid');
                    }
                    if (_isZrExpress &&
                        PhoneFormatter.normalizeDzE164ForZr(value).isEmpty) {
                      return L10n.tr(context, 'checkout.error_zr_phone');
                    }
                    return null;
                  },
                ),
                if (_isZrExpress)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      PhoneFormatter.normalizeDzE164ForZr(
                            _phoneCtrl.text,
                          ).isNotEmpty
                          ? L10n.tr(
                              context,
                              'checkout.zr_phone_preview',
                              params: {
                                'value': PhoneFormatter.normalizeDzE164ForZr(
                                  _phoneCtrl.text,
                                ),
                              },
                            )
                          : L10n.tr(context, 'checkout.zrexpress_notice'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phone2Ctrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.phone2_optional'),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty || !_isZrExpress) return null;
                    return PhoneFormatter.normalizeDzE164ForZr(value).isNotEmpty
                        ? null
                        : L10n.tr(context, 'checkout.error_zr_phone');
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _receiverWilayaId,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.receiver_wilaya'),
                  ),
                  items: _wilayas
                      .map(
                        (w) => DropdownMenuItem(
                          value: _wilayaId(w),
                          child: Text(_wilayaDisplayName(w)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) async {
                    final match = _wilayas.firstWhere(
                      (w) => _wilayaId(w) == v,
                      orElse: () => {},
                    );
                    setState(() {
                      _receiverWilayaId = v;
                      _receiverWilayaName = _wilayaName(match);
                      _receiverCommuneName = null;
                      _receiverCommuneId = null;
                      _stopdeskCommuneName = null;
                      _stopdeskId = null;
                    });
                    if (v != null) {
                      await _loadCommunes(v);
                    }
                  },
                  validator: (_) => _receiverWilayaId == null
                      ? L10n.tr(context, 'checkout.error_wilaya_required')
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _dairaCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.receiver_daira'),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? L10n.tr(context, 'checkout.error_daira_required')
                      : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _receiverCommuneName,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.receiver_commune'),
                  ),
                  items: _communes
                      .map(
                        (c) => DropdownMenuItem(
                          value: _communeName(c),
                          child: Text(_communeName(c)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    final match = _communes.firstWhere(
                      (c) => _communeName(c) == v,
                      orElse: () => {},
                    );
                    setState(() {
                      _receiverCommuneName = v;
                      _receiverCommuneId = match['id']?.toString();
                    });
                    _scheduleFeeRefresh();
                  },
                  validator: (_) => _receiverCommuneName == null
                      ? L10n.tr(context, 'checkout.error_commune_required')
                      : null,
                ),
                if (_allowStopdesk && _deliveryType == 'stopdesk') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _stopdeskCommuneName,
                    decoration: InputDecoration(
                      labelText: L10n.tr(context, 'checkout.stopdesk_agency'),
                    ),
                    items: _stopdeskCommunes
                        .map(
                          (c) => DropdownMenuItem(
                            value: _communeName(c),
                            child: Text(_communeName(c)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      final match = _stopdeskCommunes.firstWhere(
                        (c) => _communeName(c) == v,
                        orElse: () => {},
                      );
                      setState(() {
                        _stopdeskCommuneName = v;
                        _stopdeskId = _supportsStopdeskList
                            ? match['stopdesk_id']?.toString()
                            : null;
                        if (v != null && v.isNotEmpty) {
                          _receiverCommuneName = v;
                          _receiverCommuneId = match['id']?.toString();
                        }
                      });
                      _scheduleFeeRefresh();
                    },
                    validator: (_) => _stopdeskCommuneName == null
                        ? L10n.tr(context, 'checkout.error_agency_required')
                        : null,
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.address_full'),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? L10n.tr(context, 'checkout.error_address_required')
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _zipCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.zip_optional'),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  L10n.tr(context, 'checkout.package_details'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                TextFormField(
                  controller: _productListCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.product_list'),
                  ),
                  readOnly: true,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? L10n.tr(context, 'checkout.error_product_list_required')
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _orderNumberCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.order_number'),
                  ),
                  enabled: false,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _priceCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.cod_price'),
                  ),
                  readOnly: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  validator: (v) => v == null || v.trim().isEmpty
                      ? L10n.tr(context, 'checkout.error_price_required')
                      : null,
                ),
                const SizedBox(height: 8),
                _buildInfoCard(
                  context: context,
                  title: L10n.tr(
                    context,
                    'checkout.delivery_options_title',
                    fallback: 'Options de livraison',
                  ),
                  children: [
                    _SummaryRow(
                      label: L10n.tr(context, 'checkout.free_shipping'),
                      value: _freeShipping
                          ? L10n.tr(context, 'common.yes')
                          : L10n.tr(context, 'common.no'),
                    ),
                    _SummaryRow(
                      label: L10n.tr(
                        context,
                        'checkout.exchange_after_delivery',
                      ),
                      value: _exchangeAfterDelivery
                          ? L10n.tr(context, 'common.yes')
                          : L10n.tr(context, 'common.no'),
                    ),
                    _SummaryRow(
                      label: L10n.tr(context, 'listing.add.allow_stopdesk'),
                      value: _allowStopdesk
                          ? L10n.tr(context, 'common.yes')
                          : L10n.tr(context, 'common.no'),
                    ),
                  ],
                ),
                _buildInfoCard(
                  context: context,
                  title: L10n.tr(context, 'checkout.insurance'),
                  children: [
                    _SummaryRow(
                      label: L10n.tr(context, 'checkout.insurance_active'),
                      value: _insuranceActive
                          ? L10n.tr(context, 'common.yes')
                          : L10n.tr(context, 'common.no'),
                    ),
                    _SummaryRow(
                      label: L10n.tr(context, 'checkout.declared_value'),
                      value: _declaredValueCtrl.text.trim().isEmpty
                          ? '-'
                          : _declaredValueCtrl.text.trim(),
                    ),
                  ],
                ),
                _buildInfoCard(
                  context: context,
                  title: L10n.tr(context, 'checkout.dimensions_weight'),
                  children: [
                    _SummaryRow(
                      label: L10n.tr(context, 'checkout.weight_kg'),
                      value: _weightCtrl.text.trim().isEmpty
                          ? '-'
                          : _weightCtrl.text.trim(),
                    ),
                    _SummaryRow(
                      label: L10n.tr(context, 'checkout.height_cm'),
                      value: _heightCtrl.text.trim().isEmpty
                          ? '-'
                          : _heightCtrl.text.trim(),
                    ),
                    _SummaryRow(
                      label: L10n.tr(context, 'checkout.width_cm'),
                      value: _widthCtrl.text.trim().isEmpty
                          ? '-'
                          : _widthCtrl.text.trim(),
                    ),
                    _SummaryRow(
                      label: L10n.tr(context, 'checkout.length_cm'),
                      value: _lengthCtrl.text.trim().isEmpty
                          ? '-'
                          : _lengthCtrl.text.trim(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      L10n.tr(
                        context,
                        'checkout.overweight_label',
                        params: {
                          'value':
                              (int.tryParse(_weightCtrl.text.trim()) != null &&
                                  int.parse(_weightCtrl.text.trim()) >
                                      _parcelRules.overweightThresholdKg)
                              ? L10n.tr(context, 'common.yes')
                              : L10n.tr(context, 'common.no'),
                        },
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  L10n.tr(context, 'checkout.price_summary'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (_freeShipping)
                  Text(
                    L10n.tr(
                      context,
                      'checkout.fees_estimated',
                      params: {'amount': '0'},
                    ),
                  )
                else if (_estimatingFee)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_estimatedFee != null)
                  Text(
                    L10n.tr(
                      context,
                      'checkout.fees_estimated',
                      params: {'amount': _estimatedFee!.toStringAsFixed(0)},
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _estimateError ??
                            L10n.tr(context, 'checkout.fees_unavailable'),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _scheduleFeeRefresh(delay: Duration.zero),
                        icon: const Icon(Icons.refresh),
                        label: Text(L10n.tr(context, 'common.retry')),
                      ),
                    ],
                  ),
                if (!_freeShipping && _feeSource != null)
                  Text(
                    L10n.tr(
                      context,
                      'checkout.fees_by_carrier',
                      params: {'carrier': widget.courierName},
                      fallback: L10n.tr(context, 'checkout.fees_by_yalidine'),
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                CheckboxListTile(
                  value: _acceptTerms,
                  onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                  title: Text(L10n.tr(context, 'checkout.accept_terms')),
                ),
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _loadError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _canSubmit ? _submit : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      L10n.tr(
                        context,
                        'checkout.confirm_order',
                        fallback: L10n.tr(context, 'common.confirm'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageCarousel extends StatefulWidget {
  const _ImageCarousel({required this.controller, required this.images});

  final PageController controller;
  final List<String> images;

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  int _index = 0;

  Future<void> _openFullscreen(int initialIndex) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenGallery(
          images: widget.images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Future<void> _goTo(int page) async {
    if (!widget.controller.hasClients) return;
    await widget.controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final imagePrefs = NetworkPreferencesService.instance;
    return Stack(
      children: [
        PageView.builder(
          controller: widget.controller,
          onPageChanged: (i) => setState(() => _index = i),
          itemCount: widget.images.length,
          itemBuilder: (context, i) => GestureDetector(
            onTap: () => _openFullscreen(i),
            child: CachedNetworkImage(
              imageUrl: widget.images[i],
              fit: BoxFit.cover,
              memCacheWidth: imagePrefs.detailImageMemCacheWidth,
              fadeInDuration: imagePrefs.imageFadeInDuration,
              fadeOutDuration: imagePrefs.imageFadeOutDuration,
              imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
              errorWidget: (_, __, ___) => const ColoredBox(
                color: Colors.black12,
                child: Center(child: Icon(Icons.image_not_supported)),
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_index + 1}/${widget.images.length}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (widget.images.length > 1)
          Positioned(
            left: 12,
            right: 12,
            bottom: 48,
            child: SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final active = i == _index;
                  return InkWell(
                    onTap: () => _goTo(i),
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 52,
                      height: 52,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white.withValues(alpha: 0.7),
                          width: active ? 2 : 1,
                        ),
                        color: Colors.black.withValues(alpha: 0.18),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: widget.images[i],
                          fit: BoxFit.cover,
                          memCacheWidth: 140,
                          fadeInDuration: imagePrefs.imageFadeInDuration,
                          fadeOutDuration: imagePrefs.imageFadeOutDuration,
                          imageRenderMethodForWeb:
                              ImageRenderMethodForWeb.HttpGet,
                          errorWidget: (_, __, ___) => const ColoredBox(
                            color: Colors.black12,
                            child: Icon(Icons.image_not_supported, size: 16),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.images.length, (i) {
              final active = i == _index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({required this.images, required this.initialIndex});

  final List<String> images;
  final int initialIndex;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, i) => SafeArea(
              child: _ZoomableNetworkImage(imageUrl: widget.images[i]),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              color: Colors.white,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_index + 1}/${widget.images.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomableNetworkImage extends StatefulWidget {
  const _ZoomableNetworkImage({required this.imageUrl});

  final String imageUrl;

  @override
  State<_ZoomableNetworkImage> createState() => _ZoomableNetworkImageState();
}

class _ZoomableNetworkImageState extends State<_ZoomableNetworkImage> {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _panEnabled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    final currentScale = _controller.value.getMaxScaleOnAxis();
    if (currentScale > 1.01) {
      _controller.value = Matrix4.identity();
      setState(() => _panEnabled = false);
      return;
    }

    final targetScale = 2.5;
    final tap = _doubleTapDetails?.localPosition;
    if (tap == null) {
      _controller.value = Matrix4.identity()..scale(targetScale);
    } else {
      final dx = -tap.dx * (targetScale - 1);
      final dy = -tap.dy * (targetScale - 1);
      _controller.value = Matrix4.identity()
        ..translate(dx, dy)
        ..scale(targetScale);
    }
    setState(() => _panEnabled = true);
  }

  @override
  Widget build(BuildContext context) {
    final imagePrefs = NetworkPreferencesService.instance;
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 4,
        panEnabled: _panEnabled,
        boundaryMargin: const EdgeInsets.all(64),
        onInteractionEnd: (_) {
          final isZoomed = _controller.value.getMaxScaleOnAxis() > 1.01;
          if (_panEnabled != isZoomed) {
            setState(() => _panEnabled = isZoomed);
          }
        },
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.contain,
            memCacheWidth: imagePrefs.detailImageMemCacheWidth,
            fadeInDuration: imagePrefs.imageFadeInDuration,
            fadeOutDuration: imagePrefs.imageFadeOutDuration,
            imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
            errorWidget: (_, __, ___) => const Icon(
              Icons.image_not_supported,
              color: Colors.white70,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }
}

class _SellerRowFixed extends StatelessWidget {
  const _SellerRowFixed({
    required this.ownerId,
    this.sellerName,
    this.sellerAvatar,
    this.sellerIsPublic = false,
    this.onContact,
    this.onViewProfile,
  });

  final String ownerId;
  final String? sellerName;
  final String? sellerAvatar;
  final bool sellerIsPublic;
  final VoidCallback? onContact;
  final VoidCallback? onViewProfile;

  @override
  Widget build(BuildContext context) {
    final reviewService = ReviewService();
    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([
        reviewService.fetchAverageRating(ownerId),
        supabase
            .from('profiles')
            .select('is_public')
            .eq('id', ownerId)
            .maybeSingle(),
      ]),
      builder: (context, snapshot) {
        final rating = snapshot.data?[0] as double?;
        final profileRow = snapshot.data?[1] as Map<String, dynamic>?;
        final fallbackName = L10n.tr(context, 'seller.fallback');
        final canViewProfile =
            onViewProfile != null &&
            (sellerIsPublic || isTruthyFlag(profileRow?['is_public']));
        final displayName = (sellerName?.trim().isNotEmpty ?? false)
            ? sellerName!.trim()
            : fallbackName;
        final hasSellerName = sellerName?.trim().isNotEmpty ?? false;

        final card = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(
                    radius: 20,
                    avatarUrl: sellerAvatar,
                    fullName: hasSellerName ? sellerName : null,
                    fontSize: 12,
                    iconSize: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          L10n.tr(context, 'seller.label'),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (rating != null) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 18,
                              ),
                              Text(rating.toStringAsFixed(1)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          L10n.tr(
                            context,
                            'listing.seller_hint',
                            fallback: 'Reponse via chat',
                          ),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  if (canViewProfile)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canViewProfile)
                    OutlinedButton.icon(
                      onPressed: onViewProfile,
                      icon: const Icon(Icons.person_outline),
                      label: Text(L10n.tr(context, 'nav.profile')),
                    ),
                  TextButton.icon(
                    onPressed: onContact,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(L10n.tr(context, 'cta.contact')),
                  ),
                ],
              ),
            ],
          ),
        );

        if (!canViewProfile) return card;
        return InkWell(
          onTap: onViewProfile,
          borderRadius: BorderRadius.circular(14),
          child: card,
        );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
