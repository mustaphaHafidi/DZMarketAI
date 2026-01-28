import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/widgets.dart';

class PaymentLabels {
  static String methodLabel(
    BuildContext context,
    String method, {
    bool includeCodSuffix = false,
  }) {
    switch (method) {
      case 'cod':
        return includeCodSuffix
            ? L10n.t(
                context,
                'Paiement a la livraison (COD)',
                'الدفع عند التسليم (COD)',
                key: 'payment.method_cod_full',
              )
            : L10n.t(
                context,
                'Paiement a la livraison',
                'الدفع عند التسليم',
                key: 'payment.method_cod',
              );
      case 'online':
      case 'card':
      case 'stripe':
        return L10n.t(
          context,
          'Paiement en ligne',
          'الدفع عبر الإنترنت',
          key: 'payment.method_online',
        );
      default:
        return method;
    }
  }
}
