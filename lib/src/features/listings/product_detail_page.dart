// ignore_for_file: deprecated_member_use
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/chat/chat_room_page.dart';
import 'package:dzmarket/src/features/chat/order_chat_gate_page.dart';
import 'package:dzmarket/src/models/offer.dart';
import 'package:dzmarket/src/models/product.dart';
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
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _offerService = OfferService();
  Offer? _acceptedOffer;
  String? _buyerWilaya;
  String? _sellerWilaya;
  Map<String, dynamic>? _buyerProfile;
  Map<String, dynamic>? _sellerProfile;
  bool _isOwner = false;

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
                await RateLimiter.instance.run(
                  'reports.insert',
                  () => supabase.from('reports').insert({
                    'product_id': product.id,
                    'reporter_id': userId,
                    'reason': reason,
                  }),
                );
                if (context.mounted) Navigator.of(context).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        L10n.tr(context, 'report.sent'),
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
        'receiverWilaya': selection['receiverWilaya'],
        'receiverWilayaId': selection['receiverWilayaId'],
        'receiverCommune': selection['receiverCommune'],
        'receiverCommuneId': selection['receiverCommuneId'],
        'wilayaCode': selection['wilayaCode'],
        'zip': selection['zip'],
        'weight': selection['weight'],
        'height': selection['height'],
        'width': selection['width'],
        'length': selection['length'],
        'productList': selection['productList'],
        'price': selection['price'],
        'courierId': selection['courierId'],
        'courierName': selection['courierName'],
      });
      await prefs.setString('checkout.last_address.v1', payload);
    } catch (_) {}
  }

  Future<void> _load() async {
    final safeProductId =
        InputSanitizer.sanitizeId(widget.productId, maxLength: 64);
    final data = await RateLimiter.instance.run(
      'products.detail.select',
      () => supabase
          .from('products')
          .select('*, categories(name_fr, name_ar, slug)')
          .eq('id', safeProductId)
          .maybeSingle(),
    );
    final userId = supabase.auth.currentUser?.id;
    Map<String, dynamic>? buyerProfile;
    Map<String, dynamic>? seller;
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
    if (data != null && data['owner_id'] != null) {
      seller = await RateLimiter.instance.run(
        'profiles.wilaya.seller',
        () => supabase
            .from('profiles')
            .select('wilaya, full_name, avatar_url, email')
            .eq('id', data['owner_id'])
            .maybeSingle(),
      );
    }
    if (!mounted) return;
    setState(() {
      _product = data != null ? Product.fromJson(data) : null;
      _buyerWilaya = buyerProfile?['wilaya']?.toString();
      _sellerWilaya = seller?['wilaya'] as String?;
      _buyerProfile = buyerProfile;
      _sellerProfile = seller;
      _loaded = true;
      _isOwner = userId != null && data != null && data['owner_id'] == userId;
    });
  }

  Future<void> _contactSeller() async {
    final userId = supabase.auth.currentUser?.id;
    if (_product == null) return;
    if (userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.tr(context, 'chat.contact_login_required')),
        ),
      );
      return;
    }
    final newContactText = L10n.tr(context, 'chat.new_contact');
    final repo = ChatRepository();
    final conv = await repo.ensureConversation(
      productId: _product!.id,
      buyerId: userId,
      sellerId: _product!.ownerId,
    );
    // Try to send a hello message; ignore duplicate/race errors.
    try {
      await repo.sendMessage(conv.id, newContactText);
    } catch (_) {
      // If send failed (e.g., blocked), ignore for now; navigation still works.
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomPage(
          conversationId: conv.id,
          productId: _product!.id,
        ),
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

  bool _hasArabicLetters(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }

  bool _looksMojibake(String value) {
    return value.contains('Ã') || value.contains('Â') || value.contains('�');
  }

  Future<String?> _chooseDeliveryMode() async {
    String method = 'cod';
    final deliveryOptions = _product?.deliveryOptions ?? const [];
    final allowCod = deliveryOptions.isEmpty || deliveryOptions.contains('cod');
    final allowPickup = deliveryOptions.contains('pickup');
    if (!allowCod && allowPickup) {
      method = 'pickup';
    }
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.tr(context, 'checkout.choose_delivery_mode'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            RadioListTile<String>(
              value: 'pickup',
              groupValue: method,
              onChanged: allowPickup ? (v) => method = v ?? method : null,
              title: Text(L10n.tr(context, 'checkout.delivery_pickup_title')),
              subtitle:
                  Text(L10n.tr(context, 'checkout.delivery_pickup_desc')),
              enabled: allowPickup,
            ),
            RadioListTile<String>(
              value: 'cod',
              groupValue: method,
              onChanged: allowCod ? (v) => method = v ?? 'cod' : null,
              title: Text(L10n.tr(context, 'checkout.delivery_cod_title')),
              subtitle: Text(L10n.tr(context, 'checkout.delivery_cod_desc')),
              enabled: allowCod,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, method),
              child: Text(L10n.tr(context, 'common.continue')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _buyNow() async {
    if (_isOwner) return;
    if (_product == null) return;
    if ((_product?.stockQuantity ?? 0) <= 0 || _product?.isArchived == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.tr(context, 'order.stock_unavailable'))),
        );
      }
      return;
    }

    final deliveryChoice = await _chooseDeliveryMode();
    if (deliveryChoice == null) return;
    if (!mounted) return;
    if (deliveryChoice == 'pickup') {
      final agreed =
          _acceptedOffer?.agreedAmount ?? _acceptedOffer?.amount ?? _product?.price;
      final confirmed = await _confirmCheckoutSummary(
        price: agreed ?? 0,
        shippingOption: 'pickup',
        paymentMethod: 'cod',
        deliveryMode: 'pickup',
        shippingCost: 0,
        etaLabel: L10n.tr(context, 'checkout.eta_pickup'),
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
          SnackBar(
            content: Text(L10n.tr(context, 'order.created.pickup')),
          ),
        );
      }
      if (orderId != null) {
        await _openOrderChat(orderId);
      }
      return;
    }

    final shippingService = ShippingService();
    final sellerId = _product!.ownerId;
    final agreed =
        _acceptedOffer?.agreedAmount ?? _acceptedOffer?.amount ?? _product?.price;
    final selection = await _pickCourierAndAddress(
      sellerId,
      price: agreed ?? 0,
      productTitle: _product?.title ?? 'Article',
    );
    if (selection == null) return;
    if (!mounted) return;
    final courierId = selection['courierId'] as String?;
    final courierName = selection['courierName'] as String?;
    final isYalidine = courierId?.toLowerCase().contains('yalidine') == true ||
        courierName?.toLowerCase().contains('yalidine') == true;
    final isEcotrack = courierId?.toLowerCase().contains('ecotrack') == true ||
        courierName?.toLowerCase().contains('ecotrack') == true;
    final isZrExpress = ShippingService.isZrExpressCourier(
      courierId: courierId,
      courierName: courierName,
    );
    final shippingOption = courierName;
    final paymentMethod = 'cod';
    final deliveryMode = courierName;
    final shippingCost = isYalidine || isEcotrack || isZrExpress
        ? selection['estimatedFee'] as double?
        : shippingService.estimateCost(
            buyerWilaya: _buyerWilaya,
            sellerWilaya: _sellerWilaya,
          );
    final etaLabel = isYalidine
        ? L10n.tr(context, 'checkout.eta_yalidine')
        : isEcotrack
            ? L10n.tr(context, 'checkout.eta_ecotrack')
            : isZrExpress
                ? L10n.tr(context, 'checkout.eta_zrexpress')
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
              'courier': courierName ?? L10n.tr(context, 'order.delivery.generic'),
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
      MaterialPageRoute(
        builder: (_) => OrderChatGatePage(orderId: orderId),
      ),
    );
  }

  Future<Map<String, dynamic>?> _pickCourierAndAddress(
    String sellerId, {
    required double price,
    required String productTitle,
  }) async {
    final shippingService = ShippingService();
    final lastCheckout = await _loadLastCheckout();
    final enabled = await shippingService.fetchEnabledCouriersForSeller(sellerId);
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
    final courierName = courier['courier_name']?.toString() ??
        L10n.tr(context, 'checkout.courier_placeholder');
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => _CheckoutAddressSheet(
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
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(L10n.tr(context, 'checkout.choose_courier')),
            ),
            ...enabled.map(
              (c) => ListTile(
                title: Text(
                  c['courier_name']?.toString() ??
                      L10n.tr(context, 'checkout.courier_placeholder'),
                ),
                onTap: () => Navigator.pop(context, c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmCheckoutSummary({
    required double price,
    required String shippingOption,
    required String paymentMethod,
    String? deliveryMode,
    double? shippingCost,
    String? etaLabel,
  }) async {
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
                      value: deliveryMode ??
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
                              L10n.tr(context, 'checkout.confirm'),
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
    final amountController = TextEditingController();
    final messageController = TextEditingController();
    await showDialog(
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
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: messageController,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'offers.message_optional'),
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
                final amount =
                    InputSanitizer.parseAmount(amountController.text, min: 1);
                final message = InputSanitizer.sanitizeOptionalText(
                  messageController.text,
                  maxLength: 240,
                );
                await _offerService.makeOffer(
                  productId: widget.productId,
                  sellerId: _product!.ownerId,
                  amount: amount,
                  message: message,
                );
                if (context.mounted) Navigator.of(context).pop();
              } on FormatException catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)),
                );
              }
            },
            child: Text(L10n.tr(context, 'common.send')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA');

    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_product == null) {
      return Scaffold(
        body: Center(
          child: Text(
            L10n.tr(context, 'listing.not_found'),
          ),
        ),
      );
    }

    const fallbackImage =
        'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=900&q=80';
    final heroImages = _product!.imageUrls.isNotEmpty
        ? _product!.imageUrls
        : [_product!.imageUrl ?? fallbackImage];
    final agreedPrice =
        _acceptedOffer?.agreedAmount ?? _acceptedOffer?.amount ?? _product!.price;
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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 340,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.share), onPressed: () {}),
              if (supabase.auth.currentUser?.id != null)
                StreamBuilder<Set<String>>(
                  stream: FavoriteService()
                      .streamFavorites(supabase.auth.currentUser!.id),
                  builder: (context, snapshot) {
                    final isFav =
                        snapshot.data?.contains(_product?.id ?? '') ?? false;
                    return IconButton(
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav ? Colors.redAccent : null,
                      ),
                      onPressed: _product == null
                          ? null
                          : () => FavoriteService().toggleFavorite(
                                productId: _product!.id,
                                isFav: isFav,
                              ),
                    );
                  },
                )
              else
                IconButton(
                  icon: const Icon(Icons.favorite_border),
                  onPressed: null,
                ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'report') _reportListing(context, _product!);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'report',
                    child: Text(
                      L10n.tr(context, 'report.menu'),
                    ),
                  ),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _ImageCarousel(
                controller: _pageController,
                images: heroImages,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        formatter.format(agreedPrice),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (_acceptedOffer != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Chip(
                            label: Text(
                              L10n.tr(context, 'offer.agreed'),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_product!.condition?.isNotEmpty ?? false)
                        Chip(label: Text(_product!.condition!)),
                      if (_product!.brand?.isNotEmpty ?? false)
                        Chip(
                          label: Text(
                            L10n.tr(
                              context,
                              'listing.brand',
                              params: {'value': _product!.brand ?? ''},
                            ),
                          ),
                        ),
                      if (_product!.size?.isNotEmpty ?? false)
                        Chip(
                          label: Text(
                            L10n.tr(
                              context,
                              'listing.size',
                              params: {'value': _product!.size ?? ''},
                            ),
                          ),
                        ),
                      if (_product!.color?.isNotEmpty ?? false)
                        Chip(
                          label: Text(
                            L10n.tr(
                              context,
                              'listing.color',
                              params: {'value': _product!.color ?? ''},
                            ),
                          ),
                        ),
                      if ((_product!.categoryNameFr?.isNotEmpty ?? false) ||
                          (_product!.category?.isNotEmpty ?? false))
                        Chip(
                          label: Text(
                            L10n.tr(
                              context,
                              'listing.category',
                              params: {
                                'value': _resolveCategoryLabel(context),
                              },
                            ),
                          ),
                        ),
                      if (_product!.locationWilaya?.isNotEmpty ?? false)
                        Chip(
                          label: Text(
                            L10n.tr(
                              context,
                              'listing.detail.wilaya',
                              params: {'value': _product!.locationWilaya!},
                            ),
                          ),
                        ),
                      if (_product!.locationDaira?.isNotEmpty ?? false)
                        Chip(
                          label: Text(
                            L10n.tr(
                              context,
                              'listing.detail.daira',
                              params: {'value': _product!.locationDaira!},
                            ),
                          ),
                        ),
                      if (_product!.deliveryOptions.isNotEmpty)
                        Chip(
                          label: Text(
                            L10n.tr(
                              context,
                              'listing.detail.delivery',
                              params: {
                                'value': _product!.deliveryOptions
                                    .map(
                                      (o) => o == 'cod'
                                          ? L10n.tr(
                                              context,
                                              'listing.detail.delivery_cod',
                                            )
                                          : L10n.tr(
                                              context,
                                              'listing.detail.delivery_pickup',
                                            ),
                                    )
                                    .join(', ')
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _product!.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
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
                      const SizedBox(width: 8),
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
                  const SizedBox(height: 8),
                  _SellerRowFixed(
                    ownerId: _product!.ownerId,
                    sellerName: _sellerProfile?['full_name']?.toString(),
                    sellerEmail: _sellerProfile?['email']?.toString(),
                    onContact: _contactSeller,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _product!.description ??
                        L10n.tr(context, 'listing.no_description'),
                  ),
                  const SizedBox(height: 24),
                  _OffersSection(
                    productId: _product!.id,
                    sellerId: _product!.ownerId,
                    offerService: _offerService,
                    onAccept: (offer, price) => _offerService.acceptOffer(
                      offerId: offer.id,
                      agreedAmount: price ?? offer.amount,
                    ),
                    onReject: (offer) => _offerService.updateStatus(
                      offer.id,
                      OfferStatus.rejected,
                    ),
                    onCounter: (offer, amount) => _offerService.counterOffer(
                      offerId: offer.id,
                      counterAmount: amount,
                    ),
                    onAcceptedOfferChanged: (offer) {
                      setState(() => _acceptedOffer = offer);
                    },
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isOwner || outOfStock ? null : _buyNow,
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(buyLabel),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _makeOffer,
                icon: const Icon(Icons.handshake_outlined),
                label:
                    Text(L10n.tr(context, 'offers.make_offer')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutAddressSheet extends StatefulWidget {
  const _CheckoutAddressSheet({
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
  static const int _minWeightKg = 1;
  static const int _maxWeightKg = 60;

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
  bool _isEcotrack = false;
  bool _isZrExpress = false;
  bool _supportsStopdeskList = true;
  double? _estimatedFee;
  Map<String, dynamic>? _fees;

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
    _isEcotrack = widget.courierId.toLowerCase().contains('ecotrack') ||
        widget.courierName.toLowerCase().contains('ecotrack');
    _isZrExpress = ShippingService.isZrExpressCourier(
      courierId: widget.courierId,
      courierName: widget.courierName,
    );
    _supportsStopdeskList = !_isEcotrack;
    final fullName = widget.buyerProfile?['full_name']?.toString() ?? '';
    final nameParts =
        fullName.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final familyName =
        nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    _firstNameCtrl = TextEditingController(
      text: widget.lastCheckout?['firstname']?.toString() ??
          firstName,
    );
    _familyNameCtrl = TextEditingController(
      text: widget.lastCheckout?['familyname']?.toString() ??
          familyName,
    );
    _phoneCtrl = TextEditingController(
      text: widget.buyerProfile?['phone']?.toString() ??
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
      text: widget.lastCheckout?['receiverDaira']?.toString() ??
          widget.buyerProfile?['daira']?.toString() ??
          '',
    );
    _zipCtrl = TextEditingController(
      text: widget.lastCheckout?['zip']?.toString() ?? '',
    );
    _productListCtrl = TextEditingController(
      text: widget.lastCheckout?['productList']?.toString() ??
          widget.productTitle,
    );
    _orderNumberCtrl = TextEditingController(text: 'auto');
    _priceCtrl = TextEditingController(
      text: (widget.lastCheckout?['price']?.toString() ??
              widget.defaultPrice.toStringAsFixed(0))
          .toString(),
    );
    _declaredValueCtrl = TextEditingController(
      text: _priceCtrl.text,
    );
    _weightCtrl = TextEditingController(
      text: widget.lastCheckout?['weight']?.toString() ?? '1',
    );
    _heightCtrl = TextEditingController(
      text: widget.lastCheckout?['height']?.toString() ?? '0',
    );
    _widthCtrl = TextEditingController(
      text: widget.lastCheckout?['width']?.toString() ?? '0',
    );
    _lengthCtrl = TextEditingController(
      text: widget.lastCheckout?['length']?.toString() ?? '0',
    );

    _loadWilayas();
  }

  @override
  void dispose() {
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

  String _wilayaName(Map<String, String> w) => w['name'] ?? '';
  String _wilayaId(Map<String, String> w) => w['id'] ?? w['code'] ?? '';
  String _communeName(Map<String, String> c) => c['name'] ?? '';
  bool _communeHasStopdesk(Map<String, String> c) =>
      c['has_stop_desk'] == 'true' || c['has_stop_desk'] == '1';

  Future<void> _loadWilayas() async {
    if (!mounted) return;
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
          _loadError = _isZrExpress
              ? L10n.tr(context, 'location.error_zr_locations')
              : L10n.tr(context, 'location.error_no_wilayas');
      }
    } catch (_) {
      _loadError = _isZrExpress
          ? L10n.tr(context, 'location.error_zr_locations')
          : L10n.tr(context, 'location.error_wilayas_load');
    } finally {
      if (mounted) {
        setState(() {
          _loadingWilayas = false;
        });
      } else {
        _loadingWilayas = false;
      }
    }

    final senderPref = widget.sellerWilaya ?? widget.buyerWilaya;
    if (senderPref != null && _wilayas.isNotEmpty) {
      final match = _wilayas.firstWhere(
        (w) => _wilayaName(w).toLowerCase() == senderPref.toLowerCase(),
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        _senderWilayaId = _wilayaId(match);
        _senderWilayaName = _wilayaName(match);
      }
    }

    final receiverPrefId = widget.lastCheckout?['receiverWilayaId']?.toString();
    final receiverPref = widget.lastCheckout?['receiverWilaya']?.toString() ??
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

    if (mounted) setState(() {});
  }

  Future<void> _loadCommunes(String wilayaId) async {
    if (!mounted) return;
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
      _stopdeskCommunes = _supportsStopdeskList
          ? _communes.where(_communeHasStopdesk).toList(growable: false)
          : _communes;
      if (_communes.isEmpty) {
        _loadError = _isZrExpress
            ? L10n.tr(context, 'location.error_zr_locations')
            : L10n.tr(context, 'location.error_no_communes');
      }
    } catch (_) {
      _loadError = _isZrExpress
          ? L10n.tr(context, 'location.error_zr_locations')
          : L10n.tr(context, 'location.error_communes_load');
    } finally {
      if (mounted) {
        setState(() {
          _loadingCommunes = false;
        });
      } else {
        _loadingCommunes = false;
      }
    }

    final preferredCommuneId =
        widget.lastCheckout?['receiverCommuneId']?.toString();
    final preferredCommuneName =
        widget.lastCheckout?['receiverCommune']?.toString();
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
    _updateEstimatedFee();
  }

  void _updateEstimatedFee({Map<String, dynamic>? fees}) {
    if (!_isEcotrack || _receiverWilayaId == null) return;
    final data = fees ?? _fees;
    if (data == null) return;
    final livraison = data['livraison'];
    if (livraison is! List) return;
    final receiverId = int.tryParse(_receiverWilayaId ?? '');
    final entry = livraison.cast<Map>().firstWhere(
          (e) =>
              receiverId != null &&
              int.tryParse(e['wilaya_id']?.toString() ?? '') == receiverId,
          orElse: () => {},
        );
    if (entry.isEmpty) return;
    final raw = _deliveryType == 'stopdesk'
        ? entry['tarif_stopdesk']
        : entry['tarif'];
    final parsed = double.tryParse(raw?.toString() ?? '');
    if (parsed == null) return;
    if (mounted) {
      setState(() {
        _estimatedFee = parsed;
      });
    } else {
      _estimatedFee = parsed;
    }
  }

  bool _isPhoneValid(String value) =>
      RegExp(r'^(05|06|07)\d{8}$').hasMatch(value.trim());

  bool _isWeightValid(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return false;
    return parsed >= _minWeightKg && parsed <= _maxWeightKg;
  }

  bool _isDimensionValid(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return false;
    return parsed >= 0 && parsed <= 200;
  }

  bool get _canSubmit {
    final phoneOk = _isZrExpress
        ? PhoneFormatter.isZrExpressCompatible(_phoneCtrl.text)
        : _isPhoneValid(_phoneCtrl.text);
    final baseValid = !_loadingWilayas &&
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
        _isWeightValid(_weightCtrl.text) &&
        _isDimensionValid(_heightCtrl.text) &&
        _isDimensionValid(_widthCtrl.text) &&
        _isDimensionValid(_lengthCtrl.text) &&
        _acceptTerms;
    if (!baseValid) return false;
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

    final phoneMain = _phoneCtrl.text.trim();
    final phone2 = _phone2Ctrl.text.trim();
    final phoneE164 =
        _isZrExpress ? PhoneFormatter.normalizeDzE164ForZr(phoneMain) : '';
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
      'declaredValue': price,
      'weight': weight,
      'height': height,
      'width': width,
      'length': length,
      'hasExchange': _exchangeAfterDelivery,
      'acceptTerms': _acceptTerms,
      'estimatedFee': _estimatedFee,
    };

    await widget.onSaveLastCheckout(selection);
    if (!mounted) return;
    Navigator.of(context).pop(selection);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
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
                  _updateEstimatedFee();
                },
              ),
              RadioListTile<String>(
                value: 'stopdesk',
                groupValue: _deliveryType,
                title: Text(L10n.tr(context, 'checkout.delivery_stopdesk')),
                onChanged: (v) {
                  setState(() => _deliveryType = v ?? 'stopdesk');
                  _updateEstimatedFee();
                },
              ),
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
                        child: Text(_wilayaName(w)),
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
                },
                validator: (_) => _senderWilayaId == null ? L10n.tr(context, 'checkout.error_wilaya_required') : null,
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
                validator: (v) => v == null || v.trim().isEmpty ? L10n.tr(context, 'checkout.error_name_required') : null,
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
                    PhoneFormatter.normalizeDzE164(_phoneCtrl.text).isNotEmpty
                        ? L10n.tr(
                            context,
                            'checkout.zr_phone_preview',
                            params: {
                              'value':
                                  PhoneFormatter.normalizeDzE164(_phoneCtrl.text),
                            },
                          )
                        : L10n.tr(context, 'checkout.zrexpress_notice'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phone2Ctrl,
                decoration:
                    InputDecoration(
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
                        child: Text(_wilayaName(w)),
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
                validator: (_) => _receiverWilayaId == null ? L10n.tr(context, 'checkout.error_wilaya_required') : null,
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
                  },
                  validator: (_) =>
                      _receiverCommuneName == null ? L10n.tr(context, 'checkout.error_commune_required') : null,
                ),
              if (_deliveryType == 'stopdesk') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _stopdeskCommuneName,
                  decoration:
                      InputDecoration(
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
                onChanged: (_) => setState(() {}),
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
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (v) {
                  _declaredValueCtrl.text = v;
                  setState(() {});
                },
                validator: (v) => v == null || v.trim().isEmpty
                    ? L10n.tr(context, 'checkout.error_price_required')
                    : null,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: false,
                onChanged: null,
                title: Text(L10n.tr(context, 'checkout.free_shipping')),
              ),
              CheckboxListTile(
                value: _exchangeAfterDelivery,
                onChanged: (v) => setState(() => _exchangeAfterDelivery = v ?? false),
                title: Text(L10n.tr(context, 'checkout.exchange_after_delivery')),
              ),
              const SizedBox(height: 12),
              Text(
                L10n.tr(context, 'checkout.insurance'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SwitchListTile(
                value: true,
                onChanged: null,
                title: Text(L10n.tr(context, 'checkout.insurance_active')),
              ),
              TextFormField(
                controller: _declaredValueCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr(context, 'checkout.declared_value'),
                ),
                enabled: false,
              ),
              const SizedBox(height: 12),
              Text(
                L10n.tr(context, 'checkout.dimensions_weight'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              TextFormField(
                controller: _weightCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr(context, 'checkout.weight_kg'),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (!_isWeightValid(v ?? '')) {
                    return L10n.tr(
                      context,
                      'checkout.error_weight_range',
                      params: {
                        'min': _minWeightKg.toString(),
                        'max': _maxWeightKg.toString(),
                      },
                    );
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _heightCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr(context, 'checkout.height_cm'),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) => _isDimensionValid(v ?? '')
                    ? null
                    : L10n.tr(context, 'checkout.error_height_invalid'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _widthCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr(context, 'checkout.width_cm'),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) => _isDimensionValid(v ?? '')
                    ? null
                    : L10n.tr(context, 'checkout.error_width_invalid'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _lengthCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr(context, 'checkout.length_cm'),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) => _isDimensionValid(v ?? '')
                    ? null
                    : L10n.tr(context, 'checkout.error_length_invalid'),
              ),
              const SizedBox(height: 8),
              Text(
                L10n.tr(
                  context,
                  'checkout.overweight_label',
                  params: {
                    'value': (int.tryParse(_weightCtrl.text.trim()) != null &&
                            int.parse(_weightCtrl.text.trim()) > 5)
                        ? L10n.tr(context, 'common.yes')
                        : L10n.tr(context, 'common.no'),
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                L10n.tr(context, 'checkout.price_summary'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_isEcotrack)
                Text(
                  _estimatedFee == null
                      ? L10n.tr(context, 'checkout.fees_unavailable')
                      : L10n.tr(
                          context,
                          'checkout.fees_estimated',
                          params: {
                            'amount': _estimatedFee!.toStringAsFixed(0),
                          },
                        ),
                )
              else
                Text(L10n.tr(context, 'checkout.fees_by_yalidine')),
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
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: Text(L10n.tr(context, 'common.confirm')),
                  ),
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: widget.controller,
          onPageChanged: (i) => setState(() => _index = i),
          itemCount: widget.images.length,
          itemBuilder: (context, i) => CachedNetworkImage(
            imageUrl: widget.images[i],
            fit: BoxFit.cover,
            imageRenderMethodForWeb: ImageRenderMethodForWeb.HtmlImage,
            errorWidget: (_, __, ___) => const ColoredBox(
              color: Colors.black12,
              child: Center(child: Icon(Icons.image_not_supported)),
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

class _OffersSection extends StatelessWidget {
  const _OffersSection({
    required this.productId,
    required this.sellerId,
    required this.offerService,
    required this.onAccept,
    required this.onReject,
    required this.onCounter,
    required this.onAcceptedOfferChanged,
  });

  final String productId;
  final String sellerId;
  final OfferService offerService;
  final Future<void> Function(Offer, double?) onAccept;
  final void Function(Offer) onReject;
  final void Function(Offer, double) onCounter;
  final void Function(Offer?) onAcceptedOfferChanged;

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    final isSeller = userId == sellerId;

    return StreamBuilder<List<Offer>>(
      stream: offerService.streamOffersForProduct(productId),
      builder: (context, snapshot) {
        final offers = snapshot.data ?? const [];
        if (offers.isEmpty) return const SizedBox.shrink();
        final accepted = offers.firstWhere(
          (o) => o.status == OfferStatus.accepted,
          orElse: () => const Offer(
            id: '',
            productId: '',
            buyerId: '',
            sellerId: '',
            amount: 0,
          ),
        );
        if (accepted.id.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onAcceptedOfferChanged(accepted);
          });
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.tr(context, 'offers.title'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...offers.map((o) {
              final canRespond = isSeller && o.status == OfferStatus.pending;
              final statusLabel = o.statusLabel(context);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('DA ${o.amount.toStringAsFixed(0)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Chip(
                            label: Text(statusLabel),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      if (o.counterAmount != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            L10n.tr(
                              context,
                              'offer.counter',
                              params: {
                                'amount': o.counterAmount!.toStringAsFixed(0),
                              },
                            ),
                          ),
                        ),
                      if (o.agreedAmount != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            L10n.tr(
                              context,
                              'offer.accepted_amount',
                              params: {
                                'amount': o.agreedAmount!.toStringAsFixed(0),
                              },
                            ),
                          ),
                        ),
                      if (o.message?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(o.message!),
                        ),
                      if (canRespond) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => onAccept(o, o.amount),
                              child: Text(L10n.tr(context, 'offer.accept')),
                            ),
                            TextButton(
                              onPressed: () => onReject(o),
                              child: Text(L10n.tr(context, 'offer.reject')),
                            ),
                            TextButton(
                              onPressed: () async {
                                final ctrl = TextEditingController(
                                  text: o.counterAmount?.toStringAsFixed(0) ??
                                      o.amount.toStringAsFixed(0),
                                );
                                final val = await showDialog<double>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(
                                      L10n.tr(context, 'offer.counter_title'),
                                    ),
                                    content: TextField(
                                      controller: ctrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText:
                                            L10n.tr(context, 'offers.amount_label'),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(
                                          L10n.tr(context, 'common.cancel'),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          try {
                                            final v =
                                                InputSanitizer.parseAmount(
                                              ctrl.text,
                                              min: 1,
                                            );
                                            Navigator.pop(context, v);
                                          } on FormatException catch (e) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(content: Text(e.message)),
                                            );
                                          }
                                        },
                                        child:
                                            Text(L10n.tr(context, 'common.send')),
                                      ),
                                    ],
                                  ),
                                );
                                if (val != null) {
                                  onCounter(o, val);
                                }
                              },
                              child:
                                  Text(L10n.tr(context, 'offer.counter_action')),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _SellerRowFixed extends StatelessWidget {
  const _SellerRowFixed({
    required this.ownerId,
    this.sellerName,
    this.sellerEmail,
    this.onContact,
  });

  final String ownerId;
  final String? sellerName;
  final String? sellerEmail;
  final VoidCallback? onContact;

  @override
  Widget build(BuildContext context) {
    final reviewService = ReviewService();
    return FutureBuilder<double?>(
      future: reviewService.fetchAverageRating(ownerId),
      builder: (context, snapshot) {
        final rating = snapshot.data;
        final fallbackName = L10n.tr(context, 'seller.fallback');
        final displayName = (sellerName?.trim().isNotEmpty ?? false)
            ? sellerName!.trim()
            : (sellerEmail?.trim().isNotEmpty ?? false)
                ? sellerEmail!.trim()
                : fallbackName;
        return Row(
          children: [
            const CircleAvatar(child: Icon(Icons.person)),
            const SizedBox(width: 8),
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
                          style: Theme.of(context).textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (rating != null) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        Text(rating.toStringAsFixed(1)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onContact,
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(L10n.tr(context, 'cta.contact')),
            ),
          ],
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
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}





