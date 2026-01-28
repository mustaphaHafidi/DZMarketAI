import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/services/conversation_meta_service.dart';
import 'package:dzmarket/src/models/message.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/models/offer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/label_service.dart';
import 'package:dzmarket/src/services/message_service.dart';
import 'package:dzmarket/src/services/offer_service.dart';
import 'package:dzmarket/src/services/storage_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/features/listings/product_detail_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.roomId,
    this.orderId,
    this.productId,
    this.buyerId,
    this.sellerId,
  });

  final String roomId;
  final String? orderId;
  final String? productId;
  final String? buyerId;
  final String? sellerId;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _controller = TextEditingController();
  final _service = MessageService();
  final _storage = StorageService();
  final _offerService = OfferService();
  final _metaService = ConversationMetaService();
  bool _sending = false;
  final Set<String> _typingUsers = {};
  RealtimeChannel? _typingChannel;
  Timer? _typingDebounce;
  String? _productId;
  String? _buyerId;
  String? _sellerId;
  bool _otherOnline = false;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _initRoomMeta();
    _initPresence();
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    if (_typingChannel != null && _userId != null) {
      _typingChannel!.untrack();
      _typingChannel!.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': _userId, 'typing': false},
      );
      _typingChannel!.unsubscribe();
    }
    _controller.dispose();
    super.dispose();
  }

  void _initPresence() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    _userId = userId;
    final channel = supabase.channel(
      'presence:${widget.roomId}',
      opts: RealtimeChannelConfig(self: true, ack: false, key: userId),
    );
    channel
        .onPresenceSync((payload) {
          _updatePresence(channel);
        })
        .onPresenceJoin((payload) {
          _updatePresence(channel);
        })
        .onPresenceLeave((payload) {
          _updatePresence(channel);
        })
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final sender = payload['user_id']?.toString();
            final typing = payload['typing'] == true;
            if (sender == null || sender == _userId) return;
            setState(() {
              if (typing) {
                _typingUsers.add(sender);
              } else {
                _typingUsers.remove(sender);
              }
            });
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            channel.track({'user_id': userId});
          }
        });
    _typingChannel = channel;
  }

  void _initRoomMeta() {
    _productId = widget.productId;
    _buyerId = widget.buyerId;
    _sellerId = widget.sellerId;
    if (_productId != null && _buyerId != null && _sellerId != null) return;
    if (!widget.roomId.startsWith('product:')) return;
    final parts = widget.roomId.split(':');
    if (parts.length >= 4) {
      _productId ??= parts[1];
      _buyerId ??= parts[2];
      _sellerId ??= parts[3];
    }
  }

  void _updatePresence(RealtimeChannel channel) {
    final currentUser = _userId;
    if (currentUser == null) return;
    final states = channel.presenceState();
    final otherOnline =
        states.any((state) => state.key.toString() != currentUser);
    if (!mounted) return;
    setState(() => _otherOnline = otherOnline);
  }

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.image,
    );
    final file = result?.files.first;
    if (file?.bytes == null) return;
    setState(() => _sending = true);
    try {
      final urls = await _storage.uploadImages(
        files: [file!.bytes as Uint8List],
        fileNames: [file.name],
        bucket: 'messages',
      );
      if (urls.isNotEmpty) {
        final url = urls.first;
        await _service.sendMessage(
          roomId: widget.roomId,
          content: url,
          type: MessageType.image,
          payload: {
            'type': 'image',
            'url': url,
            'name': file.name,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setTyping(bool typing) {
    if (_typingChannel == null || _userId == null) return;
    _typingDebounce?.cancel();
    _typingChannel!.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': _userId, 'typing': typing},
    );
    if (typing) {
      _typingDebounce = Timer(const Duration(seconds: 1), () {
        if (!mounted || _typingChannel == null) return;
        _typingChannel!.sendBroadcastMessage(
          event: 'typing',
          payload: {'user_id': _userId, 'typing': false},
        );
      });
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
      await _service.sendMessage(
        roomId: widget.roomId,
        content: text,
        type: MessageType.text,
      );
      _controller.clear();
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _makeOffer() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final productId = _productId;
    final sellerId = _sellerId;
    final buyerId = _buyerId;
    if (productId == null || sellerId == null || buyerId == null) return;
    if (userId == sellerId) return;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.t(context, 'Faire une offre', 'ØªÙ‚Ø¯ÙŠÙ… Ø¹Ø±Ø¶', key: 'offer.make')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.t(context, 'Montant (DA)', 'Ø§Ù„Ù…Ø¨Ù„Øº (Ø¯Ø¬)', key: 'offer.amount'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: L10n.t(context, 'Message (optionnel)', 'Ø±Ø³Ø§Ù„Ø© (Ø§Ø®ØªÙŠØ§Ø±ÙŠ)',
                    key: 'offer.message'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L10n.t(context, 'Annuler', 'Ø¥Ù„ØºØ§Ø¡', key: 'common.cancel')),
          ),
          TextButton(
            onPressed: () {
              try {
                final v = InputSanitizer.parseAmount(amountCtrl.text, min: 1);
                Navigator.pop(context, v);
              } on FormatException catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)),
                );
              }
            },
            child: Text(L10n.t(context, 'Envoyer', 'Ø¥Ø±Ø³Ø§Ù„', key: 'common.send')),
          ),
        ],
      ),
    );
    if (amount == null) return;
    setState(() => _sending = true);
    try {
      final offer = await _offerService.makeOffer(
        productId: productId,
        sellerId: sellerId,
        amount: amount,
        message: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      await _service.sendMessage(
        roomId: widget.roomId,
        content: 'Offer ${offer.amount.toStringAsFixed(0)}',
        payload: {
          'type': 'offer',
          'offer_id': offer.id,
          'amount': offer.amount.toStringAsFixed(0),
          'status': offer.status.name,
        },
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _generateLabel() async {
    if (widget.orderId == null) return;
    setState(() => _sending = true);
    try {
      await LabelService().generateLabel(widget.orderId!);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Label requested')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    final formatter = DateFormat.Hm();
    final isSeller = userId != null && _sellerId == userId;
    final canOffer = _productId != null && _sellerId != null && userId != _sellerId;
    final showMeta = widget.roomId.startsWith('product:');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.orderId != null ? 'Order ${widget.orderId}' : 'Conversation',
        ),
        actions: [
          if (canOffer)
            IconButton(
              onPressed: _sending ? null : _makeOffer,
              icon: const Icon(Icons.handshake_outlined),
              tooltip: L10n.t(context, 'Faire une offre', 'ØªÙ‚Ø¯ÙŠÙ… Ø¹Ø±Ø¶', key: 'offer.make'),
            ),
          if (widget.orderId != null)
            TextButton(
              onPressed: _sending ? null : _generateLabel,
              child: const Text('Generate label'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (showMeta)
            FutureBuilder(
              future: _metaService.fetch(widget.roomId),
              builder: (context, snapshot) {
                final meta = snapshot.data;
                if (meta == null) return const SizedBox.shrink();
                final participant = meta.otherName(userId);
                final participantAvatar =
                    InputSanitizer.safeUrl(meta.otherAvatar(userId));
                final onlineLabel = _otherOnline
                    ? L10n.t(context, 'En ligne', 'En ligne')
                    : L10n.t(context, 'Hors ligne', 'Hors ligne');
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: InputSanitizer.safeUrl(meta.productImage) ==
                                  null
                              ? Container(
                                  width: 56,
                                  height: 56,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: const Icon(Icons.image_outlined),
                                )
                              : CachedNetworkImage(
                                  imageUrl:
                                      InputSanitizer.safeUrl(meta.productImage)!,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  imageRenderMethodForWeb:
                                      ImageRenderMethodForWeb.HtmlImage,
                                  errorWidget: (_, __, ___) =>
                                      const Icon(Icons.image_outlined),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                meta.productTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundImage: participantAvatar != null
                                        ? CachedNetworkImageProvider(
                                            participantAvatar,
                                            imageRenderMethodForWeb:
                                                ImageRenderMethodForWeb.HtmlImage,
                                          )
                                        : null,
                                    child: participantAvatar == null
                                        ? const Icon(Icons.person, size: 12)
                                        : null,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      participant,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.labelMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    onlineLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (meta.price != null)
                          Text(
                            'DA ${meta.price!.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        if (_productId != null)
                          IconButton(
                            tooltip: L10n.t(context, 'Voir l\'annonce', 'Voir l\'annonce'),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ProductDetailPage(productId: _productId!),
                                ),
                              );
                            },
                            icon: const Icon(Icons.open_in_new),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          Expanded(
            child: StreamBuilder<List<Offer>>(
              stream: _productId == null
                  ? const Stream.empty()
                  : _offerService.streamOffersForProduct(_productId!),
              builder: (context, offerSnap) {
                final offers = (offerSnap.data ?? const [])
                    .where((o) {
                      if (_buyerId != null && o.buyerId != _buyerId) return false;
                      if (_sellerId != null && o.sellerId != _sellerId) return false;
                      return true;
                    })
                    .toList();
                final offerMap = <String, Offer>{
                  for (final o in offers) o.id: o,
                };
                return StreamBuilder<List<Message>>(
                  stream: _service.streamMessages(widget.roomId),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          L10n.t(context, 'Erreur de chargement', '??? ?? ???????'),
                        ),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasData) {
                      _service.markRead(widget.roomId);
                    }
                    final messages = snapshot.data ?? const [];
                    if (messages.isEmpty) {
                      return Center(
                        child: Text(
                          L10n.t(context, 'Aucun message', '?? ???? ?????'),
                        ),
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[messages.length - 1 - index];
                        final isMine = message.senderId == userId;
                        return Align(
                          alignment: isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: _MessageBubble(
                            message: message,
                            isMine: isMine,
                            formatter: formatter,
                            offerById: offerMap,
                            isSeller: isSeller,
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
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          if (_typingUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  L10n.t(context, 'En train d\'ecrire...', 'En train d\'ecrire...'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _sending ? null : _pickAndUploadFile,
                        icon: const Icon(Icons.image_outlined),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: 'Message...',
                          ),
                          onChanged: (_) => _setTyping(true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _sending ? null : _sendMessage,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.formatter,
    required this.offerById,
    required this.isSeller,
    required this.onAccept,
    required this.onReject,
    required this.onCounter,
  });

  final Message message;
  final bool isMine;
  final DateFormat formatter;
  final Map<String, Offer> offerById;
  final bool isSeller;
  final Future<void> Function(Offer, double?) onAccept;
  final void Function(Offer) onReject;
  final void Function(Offer, double) onCounter;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: isMine
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildContent(context),
          const SizedBox(height: 4),
          Text(
            formatter.format(message.createdAt ?? DateTime.now()),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    // Image message
    if (message.isImage) {
      final url = message.payload?['url'] as String?;
      final safeUrl = InputSanitizer.safeUrl(url);
      if (safeUrl != null) {
        return GestureDetector(
          onTap: () => _showImagePreview(context, safeUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: safeUrl,
              height: 200,
              width: 260,
              fit: BoxFit.cover,
              imageRenderMethodForWeb: ImageRenderMethodForWeb.HtmlImage,
              errorWidget: (_, __, ___) => const Icon(Icons.image_outlined),
            ),
          ),
        );
      }
    }

    if (message.type == MessageType.label && message.payload != null) {
      final url = (message.payload?['signed_url'] ??
              message.payload?['label_url'] ??
              message.payload?['label'])
          ?.toString();
      final safeUrl = InputSanitizer.safeUrl(url);
      final tracking = message.payload?['tracking_number']?.toString() ?? 'N/A';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Label $tracking',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          if (safeUrl != null)
            InkWell(
              onTap: () => launchUrl(Uri.parse(safeUrl)),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Theme.of(context).colorScheme.surface,
                ),
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.link),
                    SizedBox(width: 8),
                    Text('Open label'),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    final payloadType = message.payload?['type'] as String?;
    if (payloadType == 'offer') {
      final offerId = message.payload?['offer_id']?.toString();
      final offer = offerId != null ? offerById[offerId] : null;
      final amount = offer?.amount ??
          double.tryParse(message.payload?['amount']?.toString() ?? '');
      return _OfferCard(
        offer: offer,
        amountFallback: amount,
        isSeller: isSeller,
        onAccept: onAccept,
        onReject: onReject,
        onCounter: onCounter,
      );
    }
    if (payloadType == 'payment') {
      final status = message.payload?['status'] ?? 'pending';
      return _CardRow(
        icon: Icons.credit_card,
        title: 'Payment update',
        subtitle: 'Status: $status',
      );
    }

    final preview = _extractPreviewImage(message.content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (InputSanitizer.safeUrl(preview) != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () =>
                  _showImagePreview(context, InputSanitizer.safeUrl(preview)!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: InputSanitizer.safeUrl(preview)!,
                  height: 180,
                  width: 260,
                  fit: BoxFit.cover,
                  imageRenderMethodForWeb: ImageRenderMethodForWeb.HtmlImage,
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.image_not_supported),
                ),
              ),
            ),
          ),
        Text(message.content),
      ],
    );
  }

  String? _extractPreviewImage(String content) {
    final uri = Uri.tryParse(content);
    if (uri != null &&
        (uri.path.endsWith('.jpg') ||
            uri.path.endsWith('.png') ||
            uri.path.endsWith('.jpeg'))) {
      return content;
    }
    return null;
  }

  void _showImagePreview(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            imageRenderMethodForWeb: ImageRenderMethodForWeb.HtmlImage,
            errorWidget: (_, __, ___) =>
                const Icon(Icons.image_not_supported),
          ),
        ),
      ),
    );
  }

}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (subtitle != null) Text(subtitle!),
            ],
          ),
        ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.amountFallback,
    required this.isSeller,
    required this.onAccept,
    required this.onReject,
    required this.onCounter,
  });

  final Offer? offer;
  final double? amountFallback;
  final bool isSeller;
  final Future<void> Function(Offer, double?) onAccept;
  final void Function(Offer) onReject;
  final void Function(Offer, double) onCounter;

  @override
  Widget build(BuildContext context) {
    final resolved = offer;
    final amount = resolved?.amount ?? amountFallback ?? 0;
    if (resolved == null) {
      return _CardRow(
        icon: Icons.handshake_outlined,
        title: L10n.t(
          context,
          'Offre: ${amount.toStringAsFixed(0)} DA',
          '???: ${amount.toStringAsFixed(0)} ??',
          key: 'offer.card.amount',
        ),
        subtitle: L10n.t(context, 'En attente', '??? ????????',
            key: 'offers.status_pending'),
      );
    }

    final status = resolved.status;
    final canRespond = isSeller && status == OfferStatus.pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardRow(
          icon: Icons.handshake_outlined,
          title: L10n.t(
            context,
            'Offre: ${amount.toStringAsFixed(0)} DA',
            '???: ${amount.toStringAsFixed(0)} ??',
            key: 'offer.card.amount',
          ),
          subtitle: resolved.statusLabel(context),
        ),
        if (resolved.counterAmount != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              L10n.t(
                context,
                'Contre-offre: DA ${resolved.counterAmount!.toStringAsFixed(0)}',
                '??? ?????: ${resolved.counterAmount!.toStringAsFixed(0)} ??',
                key: 'offer.counter',
              ),
            ),
          ),
        if (resolved.agreedAmount != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              L10n.t(
                context,
                'Prix accepte: DA ${resolved.agreedAmount!.toStringAsFixed(0)}',
                '????? ???????: ${resolved.agreedAmount!.toStringAsFixed(0)} ??',
                key: 'offer.accepted_amount',
              ),
            ),
          ),
        if (canRespond) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton(
                onPressed: () => onAccept(resolved, resolved.amount),
                child: Text(L10n.t(context, 'Accepter', '????', key: 'offer.accept')),
              ),
              TextButton(
                onPressed: () => onReject(resolved),
                child: Text(L10n.t(context, 'Refuser', '???', key: 'offer.reject')),
              ),
              TextButton(
                onPressed: () async {
                  final ctrl = TextEditingController(
                    text: resolved.counterAmount?.toStringAsFixed(0) ??
                        resolved.amount.toStringAsFixed(0),
                  );
                  final val = await showDialog<double>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(L10n.t(
                          context, 'Faire une contre-offre', '????? ??? ?????',
                          key: 'offer.counter_title')),
                      content: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: L10n.t(context, 'Montant (DA)', '?????? (??)',
                              key: 'offer.amount'),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(L10n.t(context, 'Annuler', '?????', key: 'common.cancel')),
                        ),
                        TextButton(
                          onPressed: () {
                            try {
                              final v =
                                  InputSanitizer.parseAmount(ctrl.text, min: 1);
                              Navigator.pop(context, v);
                            } on FormatException catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.message)),
                              );
                            }
                          },
                          child: Text(L10n.t(context, 'Envoyer', '?????', key: 'common.send')),
                        ),
                      ],
                    ),
                  );
                  if (val != null) {
                    onCounter(resolved, val);
                  }
                },
                child: Text(
                  L10n.t(context, 'Contre-offre', '??? ?????', key: 'offer.counter_action'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}



