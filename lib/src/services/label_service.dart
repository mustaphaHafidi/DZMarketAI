import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/message.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/message_service.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class LabelService {
  Future<Map<String, dynamic>?> generateLabel(
    String orderId, {
    Map<String, dynamic>? request,
    bool sendMessage = false,
  }) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final body = <String, dynamic>{'order_id': safeOrderId};
    if (request != null && request.isNotEmpty) {
      body.addAll(request);
    }
    final response = await RateLimiter.instance.run(
      'labels.invoke',
      () => supabase.functions.invoke(
        SupabaseOptions.createShipmentFunction,
        body: body,
      ),
    );

    final data = (response.data as Map?)?.cast<String, dynamic>();
    if (sendMessage && data != null) {
      await MessageService().sendMessage(
        roomId: 'order:$safeOrderId',
        content: 'Bordereau disponible',
        type: MessageType.label,
        payload: data,
      );
    }
    return data;
  }
}
