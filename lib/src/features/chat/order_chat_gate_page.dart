import 'package:dzmarket/src/features/chat/chat_room_page.dart';
import 'package:dzmarket/src/services/app_error_service.dart';
import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:dzmarket/src/services/connectivity_service.dart';
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
  String? _lastLoggedError;

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
          _logError(snapshot.error, snapshot.stackTrace);
          final offline =
              !ConnectivityService.instance.isOnline.value ||
              _looksOffline(snapshot.error);
          return Scaffold(
            appBar: AppBar(title: Text(L10n.tr(context, 'chat.room.title'))),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      offline ? Icons.wifi_off_rounded : Icons.error_outline,
                      size: 28,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      L10n.tr(
                        context,
                        offline
                            ? 'chat.offline_reconnecting'
                            : 'common.load_error',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _future = _loadConversation();
                      }),
                      child: Text(L10n.tr(context, 'common.retry')),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return Scaffold(
            body: Center(child: Text(L10n.tr(context, 'chat.room.not_found'))),
          );
        }
        return ChatRoomPage(
          conversationId: data.conversationId,
          productId: data.productId,
          orderId: widget.orderId,
        );
      },
    );
  }

  void _logError(Object? error, StackTrace? stack) {
    if (error == null) return;
    final text = error.toString();
    if (_lastLoggedError == text) return;
    _lastLoggedError = text;
    AppErrorService.instance.logError(
      error,
      stack,
      context: 'order_chat_gate.ensure_order_conversation',
    );
  }

  bool _looksOffline(Object? error) {
    final e = error?.toString().toLowerCase() ?? '';
    return e.contains('socketexception') ||
        e.contains('failed host lookup') ||
        e.contains('no address associated with hostname') ||
        e.contains('network is unreachable') ||
        e.contains('websocketchannelexception');
  }
}

class _OrderConversationData {
  const _OrderConversationData({required this.conversationId, this.productId});

  final String conversationId;
  final String? productId;
}
