import 'package:dzmarket/src/features/chat/chat_room_page.dart';
import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/material.dart';

class OrderChatGatePage extends StatefulWidget {
  const OrderChatGatePage({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderChatGatePage> createState() => _OrderChatGatePageState();
}

class _OrderChatGatePageState extends State<OrderChatGatePage> {
  final ChatRepository _repo = ChatRepository();
  late Future<_OrderConversationData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadConversation();
  }

  Future<_OrderConversationData> _loadConversation() async {
    final conv = await _repo.ensureOrderConversation(widget.orderId);
    return _OrderConversationData(
      conversationId: conv.id,
      productId: conv.productId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OrderConversationData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(L10n.tr(context, 'chat.room.title'))),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  L10n.tr(
                    context,
                    'common.error_with',
                    params: {'error': snapshot.error.toString()},
                  ),
                ),
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return Scaffold(
            body: Center(
              child: Text(L10n.tr(context, 'chat.room.not_found')),
            ),
          );
        }
        return ChatRoomPage(
          conversationId: data.conversationId,
          productId: data.productId,
        );
      },
    );
  }
}

class _OrderConversationData {
  const _OrderConversationData({
    required this.conversationId,
    this.productId,
  });

  final String conversationId;
  final String? productId;
}
