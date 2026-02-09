import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/chat_repository.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
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
      final locale = LocaleService.instance.locale.value?.languageCode ?? 'fr';
      const i18nKey = 'order.system.shipped';
      final payload = <String, dynamic>{
        'i18n_key': i18nKey,
        'status': 'shipped',
        'status_i18n': 'order.status.shipped',
        if (data['tracking_number'] != null)
          'tracking_number': data['tracking_number'],
        if (data['label_url'] != null) 'label_url': data['label_url'],
        if (data['courier_name'] != null) 'courier_name': data['courier_name'],
      };
      await ChatRepository().postOrderSystemMessage(
        orderId: safeOrderId,
        text: L10n.trLocale(locale, i18nKey),
        payload: payload,
        dedupeKey: 'order:$safeOrderId:shipped',
      );
    }
    return data;
  }
}
