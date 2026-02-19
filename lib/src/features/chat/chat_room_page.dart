import 'package:cached_network_image/cached_network_image.dart';
import 'package:dzmarket/src/features/listings/product_detail_page.dart';
import 'package:dzmarket/src/models/chat_message.dart';
import 'package:dzmarket/src/models/offer.dart';
import 'package:dzmarket/src/services/app_error_service.dart';
import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:dzmarket/src/services/connectivity_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/network_preferences_service.dart';
import 'package:dzmarket/src/services/offer_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/utils/label_url_resolver.dart';
import 'package:dzmarket/src/widgets/refresh_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.conversationId,
    this.productId,
    this.orderId,
  });

  final String conversationId;
  final String? productId;
  final String? orderId;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _repo = ChatRepository();
  final _offerService = OfferService();
  final _controller = TextEditingController();
  final Map<String, Future<Offer?>> _offerLookupFutures = {};
  bool _sending = false;
  bool _offerActionBusy = false;
  String? _offerBusyMessageId;
  bool _isProductNegotiable = true;
  String? _buyerId;
  String? _sellerId;
  String? _productId;
  late Future<void> _conversationFuture;
  late Future<_ProductHeaderData?> _headerFuture;
  final RefreshController _refreshController = RefreshController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _conversationFuture = _loadConversationInfo();
    _headerFuture = _conversationFuture.then((_) => _loadHeader());
  }

  Future<void> _loadConversationInfo() async {
    try {
      final conv = await supabase
          .from('conversations')
          .select('product_id,seller_id,buyer_id,order_id')
          .eq('id', widget.conversationId)
          .maybeSingle();
      if (conv == null) return;
      var resolvedProductId = conv['product_id']?.toString();
      final orderId = widget.orderId ?? conv['order_id']?.toString();
      if (orderId != null && orderId.isNotEmpty) {
        try {
          final order = await supabase
              .from('orders')
              .select('product_id')
              .eq('id', orderId)
              .maybeSingle();
          if (order != null) {
            final orderProductId = order['product_id']?.toString();
            if (orderProductId != null && orderProductId.isNotEmpty) {
              resolvedProductId = orderProductId;
            }
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _productId = resolvedProductId;
        _buyerId = conv['buyer_id']?.toString();
        _sellerId = conv['seller_id']?.toString();
      });
    } catch (_) {}
  }

  Future<_ProductHeaderData?> _loadHeader() async {
    try {
      var productId = _productId ?? widget.productId;
      if (productId == null || productId.isEmpty) return null;

      final product = await supabase
          .from('products')
          .select('id,title,image_url,price,status,is_negotiable')
          .eq('id', productId)
          .maybeSingle();
      if (product == null) return null;
      final isNegotiable = product['is_negotiable'] as bool? ?? true;
      if (mounted && _isProductNegotiable != isNegotiable) {
        setState(() => _isProductNegotiable = isNegotiable);
      }

      return _ProductHeaderData(
        productId: product['id'].toString(),
        title: product['title']?.toString() ?? 'Produit',
        imageUrl: product['image_url']?.toString(),
        price: (product['price'] as num?)?.toDouble(),
        status: product['status']?.toString(),
        isNegotiable: isNegotiable,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> _sendMessage() async {
    final text = InputSanitizer.sanitizeText(
      _controller.text,
      maxLength: 800,
      allowNewlines: true,
    );
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _repo.sendMessage(widget.conversationId, text);
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _markRead(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final last = messages.last;
    try {
      await _repo.markRead(widget.conversationId, last.id);
    } catch (_) {}
  }

  bool _isOfferParticipant(Offer offer, String userId) {
    return userId == offer.buyerId || userId == offer.sellerId;
  }

  bool _canRespondOffer(Offer offer, String userId) {
    if (offer.status != OfferStatus.pending) return false;
    if (!_isOfferParticipant(offer, userId)) return false;
    final lastActor = (offer.counterBy?.isNotEmpty ?? false)
        ? offer.counterBy!
        : offer.buyerId;
    return userId != lastActor;
  }

  Future<void> _runOfferAction({
    required String messageId,
    required Future<void> Function() action,
  }) async {
    if (_offerActionBusy) return;
    setState(() {
      _offerActionBusy = true;
      _offerBusyMessageId = messageId;
    });
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      final lower = e.toString().toLowerCase();
      if (lower.contains('offer_below_min_ratio')) {
        final minOffer = await _minOfferAmountForCurrentProduct();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tr(
                context,
                'offers.min_50_percent',
                fallback:
                    'Offre minimum: DA ${minOffer.toStringAsFixed(0)} (50%).',
                params: {'amount': minOffer.toStringAsFixed(0)},
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _offerActionBusy = false;
          _offerBusyMessageId = null;
        });
      }
    }
  }

  Future<double> _minOfferAmountForCurrentProduct() async {
    final header = await _headerFuture;
    return InputSanitizer.offerMinAmountFromBasePrice(header?.price);
  }

  Future<void> _sendOfferFromChat() async {
    final currentUser = supabase.auth.currentUser?.id;
    if (currentUser == null || _productId == null || _sellerId == null) return;
    final header = await _headerFuture;
    final isNegotiable = header?.isNegotiable ?? _isProductNegotiable;
    if (!isNegotiable) {
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
    final minOffer = await _minOfferAmountForCurrentProduct();
    if (!mounted) return;
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
            onPressed: () => Navigator.of(context).pop(false),
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
                  productId: _productId!,
                  sellerId: _sellerId!,
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
    }
  }

  Future<Offer?> _lookupOfferById(String offerId) {
    return _offerLookupFutures.putIfAbsent(
      offerId,
      () => _offerService.fetchOfferById(offerId),
    );
  }

  Widget _buildSystemMessageForRole(
    ChatMessage msg, {
    required bool isSeller,
    required String? currentUserId,
    required Offer? relatedOffer,
    required String? latestOfferMessageId,
    bool allowOfferLookup = true,
  }) {
    final payload = msg.payload ?? const {};
    final offerId = payload['offer_id']?.toString();
    final offerEvent = payload['event']?.toString();
    final offerAmount = (payload['amount'] as num?)?.toDouble();
    final i18nKey = payload['i18n_key']?.toString();
    final status = payload['status']?.toString();
    final tracking = payload['tracking_number']?.toString();
    final labelUrl = normalizeLabelUrl(payload['label_url']?.toString());
    final hasOfferPayload = offerId != null && offerId.isNotEmpty;
    final isOfferEvent =
        hasOfferPayload || (i18nKey?.startsWith('offer.system.') ?? false);
    final offerIdValue = offerId;
    if (isOfferEvent &&
        relatedOffer == null &&
        offerIdValue != null &&
        offerIdValue.isNotEmpty &&
        allowOfferLookup) {
      return FutureBuilder<Offer?>(
        future: _lookupOfferById(offerIdValue),
        builder: (context, snapshot) {
          return _buildSystemMessageForRole(
            msg,
            isSeller: isSeller,
            currentUserId: currentUserId,
            relatedOffer: relatedOffer ?? snapshot.data,
            latestOfferMessageId: latestOfferMessageId,
            allowOfferLookup: false,
          );
        },
      );
    }
    final statusKey =
        payload['status_i18n']?.toString() ??
        (status == null ? null : 'order.status.$status');
    final hasLabel = labelUrl.isNotEmpty;
    final isShipmentLikeEvent =
        !isOfferEvent &&
        (hasLabel ||
            (tracking != null && tracking.isNotEmpty) ||
            (status != null && status.isNotEmpty) ||
            (i18nKey?.startsWith('order.') ?? false) ||
            (i18nKey?.startsWith('chat.order.') ?? false));
    final messageText = i18nKey != null && i18nKey.isNotEmpty
        ? L10n.tr(context, i18nKey, fallback: msg.text)
        : msg.text;
    final statusText = statusKey != null
        ? L10n.tr(context, statusKey, fallback: status ?? '')
        : status;
    final showPendingLabelHint =
        isShipmentLikeEvent &&
        isSeller &&
        !hasLabel &&
        i18nKey == 'order.system.label_reminder';
    final isLatestOfferMessage =
        !isOfferEvent ||
        offerIdValue == null ||
        offerIdValue.isEmpty ||
        latestOfferMessageId == null ||
        msg.id == latestOfferMessageId;
    final canRespond =
        currentUserId != null &&
        relatedOffer != null &&
        isLatestOfferMessage &&
        _canRespondOffer(relatedOffer, currentUserId);
    final waitingOtherParty =
        currentUserId != null &&
        relatedOffer != null &&
        isLatestOfferMessage &&
        relatedOffer.status == OfferStatus.pending &&
        _isOfferParticipant(relatedOffer, currentUserId) &&
        !canRespond;
    final effectiveAmount =
        relatedOffer?.counterAmount ?? relatedOffer?.amount ?? offerAmount ?? 0;
    final isBusyThisMessage = _offerActionBusy && _offerBusyMessageId == msg.id;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              messageText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (statusText != null && statusText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${L10n.tr(context, 'chat.room.system_status')}: $statusText',
                ),
              ),
            if (tracking != null && tracking.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${L10n.tr(context, 'chat.room.system_tracking')}: $tracking',
                ),
              ),
            if (isShipmentLikeEvent && isSeller)
              if (hasLabel)
                TextButton.icon(
                  onPressed: () async {
                    final uri = resolveLabelUri(labelUrl);
                    if (uri != null) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(L10n.tr(context, 'chat.room.label_open')),
                )
              else if (showPendingLabelHint)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(L10n.tr(context, 'chat.room.label_pending')),
                ),
            if (isOfferEvent && relatedOffer != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  relatedOffer.statusLabel(context),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (isLatestOfferMessage && relatedOffer.counterAmount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    L10n.tr(
                      context,
                      'offer.counter',
                      params: {
                        'amount': relatedOffer.counterAmount!.toStringAsFixed(
                          0,
                        ),
                      },
                    ),
                  ),
                ),
              if (isLatestOfferMessage && relatedOffer.agreedAmount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    L10n.tr(
                      context,
                      'offer.accepted_amount',
                      params: {
                        'amount': relatedOffer.agreedAmount!.toStringAsFixed(0),
                      },
                    ),
                  ),
                ),
              if (canRespond) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.tonal(
                      onPressed: isBusyThisMessage
                          ? null
                          : () => _runOfferAction(
                              messageId: msg.id,
                              action: () => _offerService.acceptOffer(
                                offerId: relatedOffer.id,
                                agreedAmount: effectiveAmount,
                              ),
                            ),
                      child: Text(L10n.tr(context, 'offer.accept')),
                    ),
                    OutlinedButton(
                      onPressed: isBusyThisMessage
                          ? null
                          : () => _runOfferAction(
                              messageId: msg.id,
                              action: () => _offerService.rejectOffer(
                                offerId: relatedOffer.id,
                              ),
                            ),
                      child: Text(L10n.tr(context, 'offer.reject')),
                    ),
                    OutlinedButton(
                      onPressed: isBusyThisMessage
                          ? null
                          : () async {
                              final minOffer =
                                  await _minOfferAmountForCurrentProduct();
                              if (!mounted) return;
                              final ctrl = TextEditingController(
                                text: effectiveAmount.toStringAsFixed(0),
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
                                      labelText: L10n.tr(
                                        context,
                                        'offers.amount_label',
                                      ),
                                      helperText: L10n.tr(
                                        context,
                                        'offers.min_50_percent',
                                        fallback:
                                            'Offre minimum: DA ${minOffer.toStringAsFixed(0)} (50%).',
                                        params: {
                                          'amount': minOffer.toStringAsFixed(0),
                                        },
                                      ),
                                      helperMaxLines: 2,
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
                                          final normalized = ctrl.text
                                              .trim()
                                              .replaceAll(',', '.');
                                          final parsed = double.tryParse(
                                            normalized,
                                          );
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
                                                params: {
                                                  'amount': minOffer
                                                      .toStringAsFixed(0),
                                                },
                                              ),
                                            );
                                          }
                                          final v = InputSanitizer.parseAmount(
                                            normalized,
                                            min: minOffer,
                                          );
                                          Navigator.pop(context, v);
                                        } on FormatException catch (e) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(content: Text(e.message)),
                                          );
                                        }
                                      },
                                      child: Text(
                                        L10n.tr(context, 'common.send'),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (val == null) return;
                              if (!mounted) return;
                              await _runOfferAction(
                                messageId: msg.id,
                                action: () => _offerService.counterOffer(
                                  offerId: relatedOffer.id,
                                  counterAmount: val,
                                ),
                              );
                            },
                      child: Text(L10n.tr(context, 'offer.counter_action')),
                    ),
                  ],
                ),
                if (isBusyThisMessage)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ] else if (waitingOtherParty) ...[
                const SizedBox(height: 8),
                Text(
                  L10n.tr(
                    context,
                    'offers.waiting_other_party',
                    fallback: 'En attente de la reponse de l\'autre partie.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (offerEvent == 'rejected' &&
                  currentUserId != null &&
                  currentUserId == _buyerId &&
                  _isProductNegotiable &&
                  isLatestOfferMessage &&
                  !canRespond)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: _sendOfferFromChat,
                    icon: const Icon(Icons.handshake_outlined, size: 18),
                    label: Text(L10n.tr(context, 'offers.make_offer')),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat.Hm();
    final currentUser = supabase.auth.currentUser?.id;
    final isSeller = currentUser != null && _sellerId == currentUser;
    final isBuyer = currentUser != null && _buyerId == currentUser;

    return Scaffold(
      appBar: AppBar(title: Text(L10n.tr(context, 'chat.room.title'))),
      body: Column(
        children: [
          FutureBuilder<_ProductHeaderData?>(
            future: _headerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              final data = snapshot.data;
              if (data == null) return const SizedBox.shrink();
              final status = (data.status ?? 'active').toLowerCase() == 'sold'
                  ? L10n.tr(context, 'chat.room.status_sold')
                  : L10n.tr(context, 'chat.room.status_available');
              final statusColor = (data.status ?? '').toLowerCase() == 'sold'
                  ? Colors.red.shade300
                  : Colors.green.shade400;
              return InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ProductDetailPage(productId: data.productId),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: (() {
                          final imageUrl = data.imageUrl;
                          final lowerUrl = imageUrl?.toLowerCase() ?? '';
                          final isHeic = lowerUrl.contains('.heic');
                          final isHeif = lowerUrl.contains('.heif');
                          if (imageUrl == null ||
                              imageUrl.isEmpty ||
                              isHeic ||
                              isHeif) {
                            return Container(
                              width: 56,
                              height: 56,
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.image_not_supported),
                            );
                          }
                          return CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            memCacheWidth: NetworkPreferencesService
                                .instance
                                .listImageMemCacheWidth,
                            memCacheHeight: NetworkPreferencesService
                                .instance
                                .listImageMemCacheHeight,
                            fadeInDuration: NetworkPreferencesService
                                .instance
                                .imageFadeInDuration,
                            fadeOutDuration: NetworkPreferencesService
                                .instance
                                .imageFadeOutDuration,
                            placeholder: (context, _) => Container(
                              width: 56,
                              height: 56,
                              color: Colors.grey.shade300,
                            ),
                            errorWidget: (context, _, __) {
                              return Container(
                                width: 56,
                                height: 56,
                                color: Colors.grey.shade300,
                                child: const Icon(Icons.image_not_supported),
                              );
                            },
                          );
                        })(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (data.price != null)
                                  Text(
                                    NumberFormat.currency(
                                      symbol: 'DZD ',
                                      decimalDigits: 0,
                                    ).format(data.price),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<List<Offer>>(
              stream: (_productId != null && _productId!.isNotEmpty)
                  ? _offerService.streamOffersForProduct(_productId!)
                  : const Stream<List<Offer>>.empty(),
              builder: (context, offersSnapshot) {
                final offersById = <String, Offer>{
                  for (final offer in (offersSnapshot.data ?? const <Offer>[]))
                    offer.id: offer,
                };
                return StreamBuilder<List<ChatMessage>>(
                  stream: _repo.watchMessages(widget.conversationId),
                  builder: (context, snapshot) {
                    final messages = snapshot.data ?? const [];
                    final latestOfferMessageByOfferId = <String, String>{};
                    for (final message in messages) {
                      final offerId = message.payload?['offer_id']?.toString();
                      if (offerId == null || offerId.isEmpty) continue;
                      latestOfferMessageByOfferId[offerId] = message.id;
                    }
                    if (snapshot.hasData) {
                      _markRead(messages);
                    }
                    if (messages.isEmpty) {
                      return Center(
                        child: Text(L10n.tr(context, 'chat.room.empty')),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () =>
                          _refreshController.run(context, _forceReload),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          if (msg.isSystem || msg.isLabel) {
                            final offerId = msg.payload?['offer_id']
                                ?.toString();
                            final offer = offerId == null
                                ? null
                                : offersById[offerId];
                            final latestOfferMessageId = offerId == null
                                ? null
                                : latestOfferMessageByOfferId[offerId];
                            return _buildSystemMessageForRole(
                              msg,
                              isSeller: isSeller,
                              currentUserId: currentUser,
                              relatedOffer: offer,
                              latestOfferMessageId: latestOfferMessageId,
                            );
                          }
                          final isMine = msg.senderId == currentUser;
                          return Align(
                            alignment: isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isMine
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.text,
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    msg.createdAt != null
                                        ? formatter.format(
                                            msg.createdAt!.toLocal(),
                                          )
                                        : '',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  if (isBuyer &&
                      _productId != null &&
                      _sellerId != null &&
                      _isProductNegotiable) ...[
                    IconButton(
                      onPressed: _sendOfferFromChat,
                      tooltip: L10n.tr(context, 'offers.make_offer'),
                      icon: const Icon(Icons.handshake_outlined),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: L10n.tr(context, 'chat.room.message_hint'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                      ),
                      onChanged: (_) {},
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _forceReload() async {
    await _headerFuture;
    try {
      await supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', widget.conversationId)
          .limit(1);
    } catch (e) {
      AppErrorService.instance.logError(
        e,
        StackTrace.current,
        context: 'chat_room.force_reload',
      );
      if (mounted) {
        final looksOffline =
            !ConnectivityService.instance.isOnline.value ||
            e.toString().toLowerCase().contains('socketexception') ||
            e.toString().toLowerCase().contains('failed host lookup');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              looksOffline
                  ? L10n.tr(context, 'chat.offline_reconnecting')
                  : L10n.tr(context, 'common.load_error'),
            ),
          ),
        );
      }
    }
  }
}

class _ProductHeaderData {
  const _ProductHeaderData({
    required this.productId,
    required this.title,
    required this.price,
    required this.imageUrl,
    required this.status,
    required this.isNegotiable,
  });

  final String productId;
  final String title;
  final double? price;
  final String? imageUrl;
  final String? status;
  final bool isNegotiable;
}
