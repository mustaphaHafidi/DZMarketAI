// ignore_for_file: deprecated_member_use
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/chat/chat_room_page.dart';
import 'package:dzmarket/src/models/offer.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/favorite_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/message_service.dart';
import 'package:dzmarket/src/services/chat_room_service.dart';
import 'package:dzmarket/src/services/offer_service.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/services/payment_labels.dart';
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
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _load();
  }
  Future<void> _reportListing(BuildContext context, Product product) async {
    final reasonController = TextEditingController();
    const reasonOptions = [
      'Faux article',
      'Arnaque',
      'Contenu interdit',
      'Mauvaise categorie',
      'Doublon',
    ];
    String? selectedReason;
    bool showError = false;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            L10n.t(context, 'Signaler l\'annonce', 'Signaler l\'annonce',
                key: 'report.title'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.t(context, 'Raison', 'Raison', key: 'report.reason'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in reasonOptions)
                    ChoiceChip(
                      label: Text(option),
                      selected: selectedReason == option,
                      onSelected: (selected) {
                        setState(() {
                          selectedReason = selected ? option : null;
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
                    'Choisissez une raison.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: L10n.t(context, 'Details', 'Details',
                      key: 'report.details'),
                  hintText: L10n.t(
                    context,
                    'Ajoutez des details (optionnel)',
                    'Ajoutez des details (optionnel)',
                    key: 'report.hint',
                  ),
                ),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L10n.t(context, 'Annuler', 'Annuler',
                  key: 'common.cancel')),
            ),
            TextButton(
              onPressed: () async {
                if (selectedReason == null) {
                  setState(() => showError = true);
                  return;
                }
                final details = InputSanitizer.sanitizeText(
                  reasonController.text,
                  maxLength: 300,
                );
                final reason = details.isEmpty
                    ? selectedReason!
                    : '[${selectedReason!}] $details';
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
                        L10n.t(
                          context,
                          'Signalement envoye. Merci.',
                          'Signalement envoye. Merci.',
                          key: 'report.sent',
                        ),
                      ),
                    ),
                  );
                }
              },
              child: Text(L10n.t(context, 'Envoyer', 'Envoyer',
                  key: 'common.send')),
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
        'receiverCommune': selection['receiverCommune'],
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
          .select('*, categories(name_fr, name_ar)')
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
            .select('wilaya')
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
      _loaded = true;
      _isOwner = userId != null && data != null && data['owner_id'] == userId;
    });
  }

  String _roomIdForProduct(String buyerId, String sellerId) {
    final safeProductId =
        InputSanitizer.sanitizeId(widget.productId, maxLength: 64);
    return 'product:$safeProductId:$buyerId:$sellerId';
  }

  Future<void> _contactSeller() async {
    final userId = supabase.auth.currentUser?.id;
    if (_product == null) return;
    if (userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous pour contacter le vendeur.')),
      );
      return;
    }
    final messageService = MessageService();
    final existing = await messageService.findExistingProductRoom(
      productId: _product!.id,
      buyerId: userId,
      sellerId: _product!.ownerId,
    );
    final roomId = existing ?? _roomIdForProduct(userId, _product!.ownerId);
    await ChatRoomService().ensureRoom(
      roomId: roomId,
      productId: _product!.id,
      buyerId: userId,
      sellerId: _product!.ownerId,
    );
    await messageService.ensureRoomWithHello(roomId);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomPage(
          roomId: roomId,
          productId: _product!.id,
          buyerId: userId,
          sellerId: _product!.ownerId,
        ),
      ),
    );
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
              'Choisir le mode de remise',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            RadioListTile<String>(
              value: 'pickup',
              groupValue: method,
              onChanged: allowPickup ? (v) => method = v ?? method : null,
              title: const Text('Remise en main propre'),
              subtitle:
                  const Text('Rencontrez l\'acheteur pour finaliser la vente.'),
              enabled: allowPickup,
            ),
            RadioListTile<String>(
              value: 'cod',
              groupValue: method,
              onChanged: allowCod ? (v) => method = v ?? 'cod' : null,
              title: const Text('Livraison avec paiement a la livraison (COD)'),
              subtitle:
                  const Text('Transporteurs partenaires (Yalidine, Chronorex, etc.)'),
              enabled: allowCod,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, method),
              child: const Text('Continuer'),
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
          const SnackBar(content: Text('Stock indisponible')),
        );
      }
      return;
    }

    final deliveryChoice = await _chooseDeliveryMode();
    if (deliveryChoice == null) return;
    if (deliveryChoice == 'pickup') {
      final agreed =
          _acceptedOffer?.agreedAmount ?? _acceptedOffer?.amount ?? _product?.price;
      final confirmed = await _confirmCheckoutSummary(
        price: agreed ?? 0,
        shippingOption: 'pickup',
        paymentMethod: 'cod',
        deliveryMode: 'pickup',
        shippingCost: 0,
        etaLabel: 'Remise en main propre',
      );
      if (!confirmed) return;
      await OrderService().createOrder(
        productId: widget.productId,
        shippingOption: 'pickup',
        paymentMethod: 'cod',
        agreedPrice: agreed,
        deliveryMethod: 'pickup',
        shippingCost: 0,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Commande creee: remise en main propre')),
        );
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
    final courierId = selection['courierId'] as String?;
    final courierName = selection['courierName'] as String?;
    final isYalidine = courierId?.toLowerCase().contains('yalidine') == true ||
        courierName?.toLowerCase().contains('yalidine') == true;
    final isEcotrack = courierId?.toLowerCase().contains('ecotrack') == true ||
        courierName?.toLowerCase().contains('ecotrack') == true;
    final shippingOption = courierName;
    final paymentMethod = 'cod';
    final deliveryMode = courierName;
    final shippingCost = isYalidine || isEcotrack
        ? selection['estimatedFee'] as double?
        : shippingService.estimateCost(
            buyerWilaya: _buyerWilaya,
            sellerWilaya: _sellerWilaya,
          );
    final etaLabel = isYalidine
        ? 'Calcule par Yalidine'
        : isEcotrack
            ? 'Calcule par Ecotrack'
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
    final orderId = await orderService.createOrder(
      productId: widget.productId,
      shippingOption: shippingOption,
      paymentMethod: paymentMethod,
      agreedPrice: agreed,
      courierId: courierId,
      courierName: courierName,
      deliveryMethod: deliveryMode,
      shippingCost: shippingCost,
    );
    if (orderId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur: creation commande impossible')),
        );
      }
      return;
    }

    if (courierId != null && courierName != null) {
      try {
        final response = await shippingService.createShipment(
          orderId: orderId,
          courierId: courierId,
          courierName: courierName,
          deliveryMode: deliveryMode,
          shippingOption: shippingOption,
          shippingCost: shippingCost,
          selection: {
            ...selection,
            'productTitle': _product?.title ?? 'Article',
            'price': selection['price'] ?? (agreed ?? 0),
          },
        );
        if (isYalidine && mounted) {
          final summary = response['summary'];
          if (summary is Map<String, dynamic>) {
            await _showYalidineSummary(summary);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur transporteur: $e')),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Commande creee: ${courierName ?? "livraison"}')),
    );
  }

  Future<void> _showYalidineSummary(Map<String, dynamic> summary) async {
    final fee = summary['delivery_fee'];
    final tax = summary['taxe_percentage'];
    final price = summary['price'];
    final declaredValue = summary['declared_value'];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recapitulatif Yalidine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (price != null) Text('Montant COD: $price DA'),
            if (declaredValue != null) Text('Valeur declaree: $declaredValue DA'),
            if (fee != null) Text('Frais livraison: $fee DA'),
            if (tax != null) Text('Taxe COD: $tax %'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
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
          const SnackBar(content: Text('Aucun transporteur active par le vendeur')),
        );
      }
      return null;
    }
    final courier = await _chooseCourier(enabled);
    if (courier == null) return null;
    final courierId = courier['courier_id']?.toString() ?? '';
    final courierName = courier['courier_name']?.toString() ?? 'Transporteur';
    if (!mounted) return null;
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
            const ListTile(
              title: Text('Choisir le transporteur'),
            ),
            ...enabled.map(
              (c) => ListTile(
                title: Text(c['courier_name']?.toString() ?? 'Transporteur'),
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
                      L10n.t(context, 'Récapitulatif', '????',
                          key: 'checkout.summary'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _SummaryRow(
                      label:
                          L10n.t(context, 'Prix', '?????', key: 'checkout.price'),
                      value: '${price.toStringAsFixed(0)} DA',
                    ),
                    if (shippingCost != null)
                      _SummaryRow(
                        label: 'Frais livraison',
                        value: '${shippingCost.toStringAsFixed(0)} DA',
                      ),
                    _SummaryRow(
                      label: L10n.t(context, 'Livraison', '???????',
                          key: 'checkout.shipping'),
                      value: shippingOption,
                    ),
                    _SummaryRow(
                      label: L10n.t(context, 'Mode', 'Mode',
                          key: 'checkout.mode'),
                      value: deliveryMode ??
                          L10n.t(
                            context,
                            'standard',
                            'standard',
                            key: 'checkout.delivery_standard',
                          ),
                    ),
                    _SummaryRow(
                      label: L10n.t(context, 'Paiement', 'Paiement',
                          key: 'checkout.payment'),
                      value: PaymentLabels.methodLabel(
                        context,
                        paymentMethod,
                        includeCodSuffix: true,
                      ),
                    ),
                    if (etaLabel != null)
                      _SummaryRow(
                        label: 'ETA',
                        value: etaLabel,
                      ),
                    if (shippingCost != null)
                      _SummaryRow(
                        label: 'Total',
                        value:
                            '${(price + shippingCost).toStringAsFixed(0)} DA',
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(L10n.t(context, 'Annuler', '?????',
                                key: 'common.cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(
                              L10n.t(context, 'Valider et payer', '????? ??????',
                                  key: 'checkout.confirm'),
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
        title: Text(L10n.t(context, 'Faire une offre', '??? ????',
            key: 'offer.make')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.t(context, 'Montant (DA)', '?????? (??)',
                    key: 'offer.amount'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: messageController,
              decoration: InputDecoration(
                labelText: L10n.t(context, 'Message (optionnel)',
                    '????? (???????)',
                    key: 'offer.message'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
                L10n.t(context, 'Annuler', '?????', key: 'common.cancel')),
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
            child: Text(L10n.t(context, 'Envoyer', '?????',
                key: 'common.send')),
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
            L10n.t(context, 'Annonce introuvable', '??????? ??? ?????',
                key: 'listing.not_found'),
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
        ? L10n.t(
            context,
            'Acheter ${agreedPrice.toStringAsFixed(0)} DA',
            'Acheter ${agreedPrice.toStringAsFixed(0)} DA',
            key: 'cta.buy_agreed',
          )
        : isOwner
            ? L10n.t(context, 'Votre annonce', 'Votre annonce',
                key: 'cta.own_listing')
            : outOfStock
                ? L10n.t(
                    context,
                    'Rupture de stock',
                    'Rupture de stock',
                    key: 'cta.out_of_stock',
                  )
                : L10n.t(context, 'Acheter', 'Acheter', key: 'cta.buy_now');

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
                      L10n.t(
                        context,
                        'Signaler l\'annonce',
                        '??????? ?? ???????',
                        key: 'report.menu',
                      ),
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
                              L10n.t(context, 'Prix négocié', '??? ?????? ????',
                                  key: 'offer.agreed'),
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
                            L10n.t(
                              context,
                              'Marque: ${_product!.brand}',
                              '???????: ${_product!.brand}',
                              key: 'listing.brand',
                            ),
                          ),
                        ),
                      if (_product!.size?.isNotEmpty ?? false)
                        Chip(
                          label: Text(
                            L10n.t(
                              context,
                              'Taille: ${_product!.size}',
                              '??????: ${_product!.size}',
                              key: 'listing.size',
                            ),
                          ),
                        ),
                      if (_product!.color?.isNotEmpty ?? false)
                        Chip(
                          label: Text(
                            L10n.t(
                              context,
                              'Couleur: ${_product!.color}',
                              '?????: ${_product!.color}',
                              key: 'listing.color',
                            ),
                          ),
                        ),
                      if ((_product!.categoryNameFr?.isNotEmpty ?? false) ||
                          (_product!.category?.isNotEmpty ?? false))
                        Chip(
                          label: Text(
                            L10n.t(
                              context,
                              'Categorie: ${_product!.categoryNameFr ?? _product!.category}',
                              '?????: ${_product!.categoryNameAr ?? _product!.category}',
                              key: 'listing.category',
                            ),
                          ),
                        ),
                      if (_product!.locationWilaya?.isNotEmpty ?? false)
                        Chip(
                          label: Text('Wilaya: ${_product!.locationWilaya}'),
                        ),
                      if (_product!.locationDaira?.isNotEmpty ?? false)
                        Chip(
                          label: Text('Daira: ${_product!.locationDaira}'),
                        ),
                      if (_product!.deliveryOptions.isNotEmpty)
                        Chip(
                          label: Text(
                            'Livraison: ${_product!.deliveryOptions.map((o) => o == 'cod' ? 'COD' : 'Pickup').join(", ")}',
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
                        label: Text('Stock: ${_product!.stockQuantity}'),
                      ),
                      const SizedBox(width: 8),
                      if (_product!.soldCount > 0)
                        Chip(
                          label: Text('Vendu: ${_product!.soldCount}'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _SellerRowFixed(
                    ownerId: _product!.ownerId,
                    onContact: _contactSeller,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _product!.description ??
                        L10n.t(context, 'Pas de description.', '?? ???? ???.',
                            key: 'listing.no_description'),
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
                    Text(L10n.t(context, 'Faire une offre', '??? ????',
                        key: 'cta.offer')),
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
  String? _receiverCommuneName;
  String? _stopdeskCommuneName;
  String? _stopdeskId;

  String _deliveryType = 'home';
  bool _acceptTerms = false;
  bool _exchangeAfterDelivery = false;
  bool _isEcotrack = false;
  bool _supportsStopdeskList = true;
  double? _estimatedFee;
  Map<String, dynamic>? _fees;

  late TextEditingController _firstNameCtrl;
  late TextEditingController _familyNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _phone2Ctrl;
  late TextEditingController _addressCtrl;
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
      _supportsStopdeskList &&
      (c['has_stop_desk'] == 'true' || c['has_stop_desk'] == '1');

  Future<void> _loadWilayas() async {
    if (!mounted) return;
    setState(() {
      _loadingWilayas = true;
      _loadError = null;
    });
    try {
      _wilayas = await _shippingService.fetchCourierWilayas(
        courierId: widget.courierId,
      );
      if (_wilayas.isEmpty) {
        _loadError = 'Aucune wilaya disponible.';
      }
    } catch (_) {
      _loadError = 'Erreur chargement wilayas.';
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

    final receiverPref = widget.lastCheckout?['receiverWilaya']?.toString() ??
        widget.buyerProfile?['wilaya']?.toString();
    if (receiverPref != null && _wilayas.isNotEmpty) {
      final match = _wilayas.firstWhere(
        (w) => _wilayaName(w).toLowerCase() == receiverPref.toLowerCase(),
        orElse: () => {},
      );
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
      _stopdeskCommuneName = null;
      _stopdeskId = null;
    });
    try {
      _communes = await _shippingService.fetchCourierCommunes(
        courierId: widget.courierId,
        wilayaCode: wilayaId,
      );
      _stopdeskCommunes = _supportsStopdeskList
          ? _communes.where(_communeHasStopdesk).toList(growable: false)
          : const [];
      if (_communes.isEmpty) {
        _loadError = 'Aucune commune disponible.';
      }
    } catch (_) {
      _loadError = 'Erreur chargement communes.';
    } finally {
      if (mounted) {
        setState(() {
          _loadingCommunes = false;
        });
      } else {
        _loadingCommunes = false;
      }
    }

    final preferredCommune =
        widget.lastCheckout?['receiverCommune']?.toString();
    if (preferredCommune != null && _communes.isNotEmpty) {
      final match = _communes.firstWhere(
        (c) => _communeName(c).toLowerCase() == preferredCommune.toLowerCase(),
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        _receiverCommuneName = _communeName(match);
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
    final baseValid = !_loadingWilayas &&
        !_loadingCommunes &&
        _loadError == null &&
        _senderWilayaName != null &&
        _receiverWilayaName != null &&
        _receiverCommuneName != null &&
        _firstNameCtrl.text.trim().isNotEmpty &&
        _familyNameCtrl.text.trim().isNotEmpty &&
        _isPhoneValid(_phoneCtrl.text) &&
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
      return true;
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

    final phone2 = _phone2Ctrl.text.trim();
    final phoneCombined = phone2.isEmpty
        ? _phoneCtrl.text.trim()
        : '${_phoneCtrl.text.trim()},$phone2';

    final selection = {
      'courierId': widget.courierId,
      'courierName': widget.courierName,
      'deliveryType': _deliveryType,
      'senderWilaya': _senderWilayaName,
      'receiverWilaya': _receiverWilayaName,
      'receiverCommune': _receiverCommuneName,
      'wilayaCode': _receiverWilayaId,
      'stopdeskId': _stopdeskId,
      'stopdeskCommune': _stopdeskCommuneName,
      'firstname': _firstNameCtrl.text.trim(),
      'familyname': _familyNameCtrl.text.trim(),
      'phone': phoneCombined,
      'phone_main': _phoneCtrl.text.trim(),
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
              Text('Type de livraison',
                  style: Theme.of(context).textTheme.titleSmall),
              RadioListTile<String>(
                value: 'home',
                groupValue: _deliveryType,
                title: const Text('Livraison a domicile'),
                onChanged: (v) {
                  setState(() => _deliveryType = v ?? 'home');
                  _updateEstimatedFee();
                },
              ),
              RadioListTile<String>(
                value: 'stopdesk',
                groupValue: _deliveryType,
                title: const Text('Livraison en point relais (stop desk)'),
                onChanged: (v) {
                  setState(() => _deliveryType = v ?? 'stopdesk');
                  _updateEstimatedFee();
                },
              ),
              const SizedBox(height: 8),
              Text('Expediteur',
                  style: Theme.of(context).textTheme.titleSmall),
              DropdownButtonFormField<String>(
                value: _senderWilayaId,
                decoration: const InputDecoration(labelText: 'Wilaya de depart'),
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
                validator: (_) => _senderWilayaId == null ? 'Wilaya requise' : null,
              ),
              const SizedBox(height: 12),
              Text('Destinataire',
                  style: Theme.of(context).textTheme.titleSmall),
              TextFormField(
                controller: _familyNameCtrl,
                decoration: const InputDecoration(labelText: 'Nom'),
                onChanged: (_) => setState(() {}),
                validator: (v) => v == null || v.trim().isEmpty ? 'Nom requis' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _firstNameCtrl,
                decoration: const InputDecoration(labelText: 'Prenom'),
                onChanged: (_) => setState(() {}),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Prenom requis' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Telephone 1',
                  helperText: 'Ex: 0661452684',
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Telephone requis';
                  final ok = RegExp(r'^(05|06|07)\d{8}$').hasMatch(value);
                  return ok ? null : 'Numero invalide (05/06/07 + 8 chiffres)';
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phone2Ctrl,
                decoration:
                    const InputDecoration(labelText: 'Telephone 2 (optionnel)'),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _receiverWilayaId,
                decoration: const InputDecoration(labelText: 'Wilaya'),
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
                    _stopdeskCommuneName = null;
                    _stopdeskId = null;
                  });
                  if (v != null) {
                    await _loadCommunes(v);
                  }
                },
                validator: (_) => _receiverWilayaId == null ? 'Wilaya requise' : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _receiverCommuneName,
                decoration: const InputDecoration(labelText: 'Commune / Daira'),
                items: _communes
                    .map(
                      (c) => DropdownMenuItem(
                        value: _communeName(c),
                        child: Text(_communeName(c)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _receiverCommuneName = v),
                validator: (_) =>
                    _receiverCommuneName == null ? 'Commune requise' : null,
              ),
              if (_deliveryType == 'stopdesk' && _supportsStopdeskList) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _stopdeskCommuneName,
                  decoration:
                      const InputDecoration(labelText: 'Agence / Bureau'),
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
                      _stopdeskId = match['stopdesk_id']?.toString();
                    });
                  },
                  validator: (_) => _stopdeskCommuneName == null
                      ? 'Agence requise'
                      : null,
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: 'Adresse complete'),
                onChanged: (_) => setState(() {}),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Adresse requise'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _zipCtrl,
                decoration: const InputDecoration(labelText: 'Code postal (optionnel)'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
              ),
              const SizedBox(height: 12),
              Text('Details du colis',
                  style: Theme.of(context).textTheme.titleSmall),
              TextFormField(
                controller: _productListCtrl,
                decoration: const InputDecoration(labelText: 'Produits'),
                onChanged: (_) => setState(() {}),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Produits requis' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _orderNumberCtrl,
                decoration: const InputDecoration(labelText: 'Numero de commande'),
                enabled: false,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _priceCtrl,
                decoration: const InputDecoration(labelText: 'Prix du colis (COD)'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (v) {
                  _declaredValueCtrl.text = v;
                  setState(() {});
                },
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Prix requis' : null,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: false,
                onChanged: null,
                title: const Text('Livraison gratuite'),
              ),
              CheckboxListTile(
                value: _exchangeAfterDelivery,
                onChanged: (v) => setState(() => _exchangeAfterDelivery = v ?? false),
                title: const Text('Echange apres livraison'),
              ),
              const SizedBox(height: 12),
              Text('Assurance',
                  style: Theme.of(context).textTheme.titleSmall),
              SwitchListTile(
                value: true,
                onChanged: null,
                title: const Text('Assurance active'),
              ),
              TextFormField(
                controller: _declaredValueCtrl,
                decoration: const InputDecoration(labelText: 'Valeur declaree'),
                enabled: false,
              ),
              const SizedBox(height: 12),
              Text('Dimensions & poids',
                  style: Theme.of(context).textTheme.titleSmall),
              TextFormField(
                controller: _weightCtrl,
                decoration: const InputDecoration(labelText: 'Poids (kg)'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (!_isWeightValid(v ?? '')) {
                    return 'Poids entre $_minWeightKg et $_maxWeightKg';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _heightCtrl,
                decoration: const InputDecoration(labelText: 'Hauteur (cm)'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) =>
                    _isDimensionValid(v ?? '') ? null : 'Hauteur invalide',
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _widthCtrl,
                decoration: const InputDecoration(labelText: 'Largeur (cm)'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) =>
                    _isDimensionValid(v ?? '') ? null : 'Largeur invalide',
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _lengthCtrl,
                decoration: const InputDecoration(labelText: 'Longueur (cm)'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) =>
                    _isDimensionValid(v ?? '') ? null : 'Longueur invalide',
              ),
              const SizedBox(height: 8),
              Text(
                'Depassement 5 kg: ${int.tryParse(_weightCtrl.text.trim()) != null && int.parse(_weightCtrl.text.trim()) > 5 ? 'Oui' : 'Non'}',
              ),
              const SizedBox(height: 12),
              Text('Resume du prix',
                  style: Theme.of(context).textTheme.titleSmall),
              if (_isEcotrack)
                Text(
                  _estimatedFee == null
                      ? 'Frais estimes indisponibles.'
                      : 'Frais livraison estimes: ${_estimatedFee!.toStringAsFixed(0)} DA',
                )
              else
                const Text(
                  'Les frais seront calcules par Yalidine apres validation.',
                ),
              CheckboxListTile(
                value: _acceptTerms,
                onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                title: const Text('J\'accepte les conditions generales'),
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
                  child: const Text('Confirmer'),
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
            Text(L10n.t(context, 'Offres', '????', key: 'offers.title'),
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
                            L10n.t(
                              context,
                              'Contre-offre: DA ${o.counterAmount!.toStringAsFixed(0)}',
                              '??? ????: ${o.counterAmount!.toStringAsFixed(0)} ??',
                              key: 'offer.counter',
                            ),
                          ),
                        ),
                      if (o.agreedAmount != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            L10n.t(
                              context,
                              'Prix accepté: DA ${o.agreedAmount!.toStringAsFixed(0)}',
                              '????? ???????: ${o.agreedAmount!.toStringAsFixed(0)} ??',
                              key: 'offer.accepted_amount',
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
                              child: Text(L10n.t(context, 'Accepter', '????',
                                  key: 'offer.accept')),
                            ),
                            TextButton(
                              onPressed: () => onReject(o),
                              child: Text(L10n.t(context, 'Refuser', '???',
                                  key: 'offer.reject')),
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
                                    title: Text(L10n.t(
                                      context,
                                      'Faire une contre-offre',
                                      '??? ???? ?????',
                                      key: 'offer.counter_title',
                                    )),
                                    content: TextField(
                                      controller: ctrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: L10n.t(context, 'Montant (DA)',
                                            '?????? (??)',
                                            key: 'offer.amount'),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(L10n.t(context, 'Annuler',
                                            '?????', key: 'common.cancel')),
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
                                        child: Text(L10n.t(context, 'Envoyer',
                                            '?????', key: 'common.send')),
                                      ),
                                    ],
                                  ),
                                );
                                if (val != null) {
                                  onCounter(o, val);
                                }
                              },
                              child: Text(L10n.t(context, 'Contre-offre', '??? ????',
                                  key: 'offer.counter_action')),
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
  const _SellerRowFixed({required this.ownerId, this.onContact});

  final String ownerId;
  final VoidCallback? onContact;

  @override
  Widget build(BuildContext context) {
    final reviewService = ReviewService();
    return FutureBuilder<double?>(
      future: reviewService.fetchAverageRating(ownerId),
      builder: (context, snapshot) {
        final rating = snapshot.data;
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
                    L10n.t(context, 'Vendeur', '??????', key: 'seller.label'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          ownerId,
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
              label: Text(
                  L10n.t(context, 'Contacter', '????', key: 'cta.contact')),
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



