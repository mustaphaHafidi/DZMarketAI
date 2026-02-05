import 'package:dzmarket/src/features/listings/product_detail_page.dart';
import 'package:dzmarket/src/models/chat_message.dart';
import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/widgets/refresh_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.conversationId,
    this.productId,
  });

  final String conversationId;
  final String? productId;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _repo = ChatRepository();
  final _controller = TextEditingController();
  bool _sending = false;
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
    _headerFuture = _loadHeader();
  }

  Future<_ProductHeaderData?> _loadHeader() async {
    try {
      var productId = widget.productId;
      if (productId == null || productId.isEmpty) {
        final conv = await supabase
            .from('conversations')
            .select('product_id')
            .eq('id', widget.conversationId)
            .maybeSingle();
        productId = conv?['product_id']?.toString();
      }
      if (productId == null || productId.isEmpty) return null;

      final product = await supabase
          .from('products')
          .select('id,title,image_url,price,status')
          .eq('id', productId)
          .maybeSingle();
      if (product == null) return null;

      return _ProductHeaderData(
        productId: product['id'].toString(),
        title: product['title']?.toString() ?? 'Produit',
        imageUrl: product['image_url']?.toString(),
        price: (product['price'] as num?)?.toDouble(),
        status: product['status']?.toString(),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
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

  Widget _buildSystemMessage(ChatMessage msg) {
    final payload = msg.payload ?? const {};
    final i18nKey = payload['i18n_key']?.toString();
    final status = payload['status']?.toString();
    final tracking = payload['tracking_number']?.toString();
    final labelUrl = payload['label_url']?.toString();
    final statusKey = payload['status_i18n']?.toString() ??
        (status == null ? null : 'order.status.$status');
    final hasLabel = labelUrl != null && labelUrl.isNotEmpty;
    final messageText = i18nKey != null && i18nKey.isNotEmpty
        ? L10n.tr(context, i18nKey, fallback: msg.text)
        : msg.text;
    final statusText = statusKey != null
        ? L10n.tr(context, statusKey, fallback: status ?? '')
        : status;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
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
            if (hasLabel)
              TextButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(labelUrl);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(L10n.tr(context, 'chat.room.label_open')),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(L10n.tr(context, 'chat.room.label_pending')),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat.Hm();
    final currentUser = supabase.auth.currentUser?.id;

      return Scaffold(
        appBar: AppBar(
          title: Text(L10n.tr(context, 'chat.room.title')),
        ),
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
                final status =
                    (data.status ?? 'active').toLowerCase() == 'sold'
                        ? L10n.tr(context, 'chat.room.status_sold')
                        : L10n.tr(context, 'chat.room.status_available');
              final statusColor =
                  (data.status ?? '').toLowerCase() == 'sold'
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withOpacity(0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: data.imageUrl != null
                            ? Image.network(
                                data.imageUrl!,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 56,
                                height: 56,
                                color: Colors.grey.shade300,
                                child: const Icon(Icons.image_not_supported),
                              ),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
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
                                    style:
                                        Theme.of(context).textTheme.labelLarge,
                                  ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.15),
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
            child: StreamBuilder<List<ChatMessage>>(
              stream: _repo.watchMessages(widget.conversationId),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? const [];
                if (snapshot.hasData) {
                  _markRead(messages);
                }
                if (messages.isEmpty) {
                  return Center(
                    child: Text(L10n.tr(context, 'chat.room.empty')),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => _refreshController.run(context, _forceReload),
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      if (msg.isSystem || msg.isLabel) {
                        return _buildSystemMessage(msg);
                      }
                      final isMine = msg.senderId == currentUser;
                      return Align(
                        alignment:
                            isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceVariant,
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
                                  ? formatter.format(msg.createdAt!.toLocal())
                                  : '',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
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
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tr(
                context,
                'common.error_with',
                params: {'error': e.toString()},
              ),
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
  });

  final String productId;
  final String title;
  final double? price;
  final String? imageUrl;
  final String? status;
}
