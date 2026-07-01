// ignore_for_file: deprecated_member_use
import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/order.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/utils/delivery_mode_utils.dart';
import 'package:dzmarket/src/utils/shipment_error_mapper.dart';
import 'package:flutter/material.dart';

class FulfillmentPage extends StatefulWidget {
  const FulfillmentPage({super.key, required this.orderId});
  final String orderId;

  @override
  State<FulfillmentPage> createState() => _FulfillmentPageState();
}

class _FulfillmentPageState extends State<FulfillmentPage> {
  final _shipping = ShippingService();
  final _orderService = OrderService();
  List<Map<String, dynamic>> _couriers = const [];
  List<String> _optionChoices = ShippingService.options;
  String? _selectedCourierId;
  String? _selectedCourierName;
  String? _deliveryMode = 'home';
  String? _option = ShippingService.options.first;
  bool _saving = false;
  String? _error;
  bool _courierLocked = false;
  bool _deliveryLocked = false;
  bool _optionLocked = false;
  bool _orderCancelled = false;
  bool _arrangedDelivery = false;
  bool _loading = true;

  bool get _hasLockedClientSelection =>
      _courierLocked || _deliveryLocked || _optionLocked;

  String _deliveryModeLabel(BuildContext context, String? mode) {
    switch (mode) {
      case 'pickup_postal':
      case 'stopdesk':
        return L10n.tr(context, 'fulfillment.delivery_pickup');
      case 'local_driver':
        return L10n.tr(context, 'fulfillment.delivery_local');
      case 'home':
      default:
        return L10n.tr(context, 'fulfillment.delivery_home');
    }
  }

  String _clientOptionLabel(BuildContext context, String? option) {
    final value = option?.trim();
    if (value == null || value.isEmpty) {
      return L10n.tr(context, 'fulfillment.not_specified');
    }
    final normalized = value.toLowerCase();
    final courierId = _selectedCourierId?.toLowerCase();
    final courierName = _selectedCourierName?.toLowerCase();
    if (normalized == courierId || normalized == courierName) {
      return _deliveryModeLabel(context, _deliveryMode);
    }
    return ShippingService.optionLabel(context, value);
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadOrderDefaults();
    await _loadCouriers();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadOrderDefaults() async {
    final orderRow = await supabase
        .from(SupabaseTables.orders)
        .select(
          'courier_id,courier_name,delivery_method,shipping_option,status',
        )
        .eq('id', widget.orderId)
        .maybeSingle();
    if (orderRow is Map<String, dynamic>) {
      final courierId = orderRow['courier_id']?.toString();
      final courierName = orderRow['courier_name']?.toString();
      final deliveryMode = orderRow['delivery_method']?.toString();
      final option = orderRow['shipping_option']?.toString();
      final status = orderRow['status']?.toString().toLowerCase();
      _orderCancelled = status == 'cancelled';
      _arrangedDelivery = isArrangedDelivery(
        deliveryMethod: deliveryMode,
        shippingOption: option,
      );
      if (courierId != null && courierId.isNotEmpty) {
        _selectedCourierId = courierId;
        _selectedCourierName = courierName;
        _courierLocked = true;
      }
      if (deliveryMode != null && deliveryMode.isNotEmpty) {
        _deliveryMode = deliveryMode;
        _deliveryLocked = true;
      }
      if (option != null && option.isNotEmpty) {
        _option = option;
        _optionLocked = true;
        if (!_optionChoices.contains(option)) {
          _optionChoices = [option, ..._optionChoices];
        }
      }
    }
  }

  Future<void> _loadCouriers() async {
    final placeholder = L10n.tr(context, 'fulfillment.courier_placeholder');
    final list = await _shipping.fetchCouriers();
    final updated = List<Map<String, dynamic>>.from(list);
    if (_selectedCourierId != null &&
        updated.every((c) => c['id']?.toString() != _selectedCourierId)) {
      updated.insert(0, {
        'id': _selectedCourierId,
        'name': _selectedCourierName ?? placeholder,
      });
    }
    if (_selectedCourierId == null && updated.isNotEmpty) {
      _selectedCourierId = updated.first['id'].toString();
      _selectedCourierName = updated.first['name']?.toString();
    }
    if (mounted) {
      setState(() {
        _couriers = updated;
      });
    }
  }

  Future<void> _fulfill() async {
    if (_arrangedDelivery) {
      setState(
        () => _error = L10n.tr(context, 'fulfillment.arranged_no_label'),
      );
      return;
    }
    if (_orderCancelled) {
      setState(
        () => _error = L10n.tr(context, 'fulfillment.order_cancelled_blocked'),
      );
      return;
    }
    if (_selectedCourierId == null || _selectedCourierName == null) {
      setState(
        () => _error = L10n.tr(context, 'fulfillment.error_select_courier'),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final selection = await _shipping.buildSelectionFromOrder(widget.orderId);
      await _shipping.createLabelForOrder(
        orderId: widget.orderId,
        courierId: _selectedCourierId!,
        courierName: _selectedCourierName!,
        option: _option,
        deliveryMode: _deliveryMode,
        selection: selection,
      );
      await _orderService.updateStatus(
        orderId: widget.orderId,
        status: OrderStatus.shipped,
        courierId: _selectedCourierId,
        courierName: _selectedCourierName,
        deliveryMethod: _deliveryMode,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tr(context, 'fulfillment.success_label')),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _formatFulfillmentError(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatFulfillmentError(Object error) {
    final raw = switch (error) {
      StateError _ => error.message.toString().trim(),
      _ => error.toString().trim(),
    };
    final cleaned = raw
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
    final lower = cleaned.toLowerCase();
    final parsedPayload = parseShipmentErrorPayload(cleaned);
    if (parsedPayload != null) {
      return mapCreateShipmentError(
        locale: Localizations.localeOf(context).languageCode,
        data: parsedPayload,
        courierName: _selectedCourierName ?? 'transporteur',
      );
    }
    final amountMatch = RegExp(r'(\d{3,})').allMatches(cleaned).lastOrNull;
    final amountMax = amountMatch?.group(1) ?? '150000';
    if (lower == 'parcel_cod_amount_out_of_range' ||
        lower.contains('parcel_cod_amount_out_of_range') ||
        lower.contains('cod_amount_out_of_range') ||
        lower.contains('amount must be less') ||
        lower.contains('montant ne peut') ||
        lower.contains('supérieure à 150000')) {
      return L10n.tr(
        context,
        'checkout.error_cod_amount_max',
        params: {'max': amountMax},
      );
    }
    if (lower == 'courier_credentials_invalid' ||
        lower.contains('invalid api key')) {
      return L10n.tr(
        context,
        'fulfillment.error_courier_credentials_invalid',
        params: {'courier': _selectedCourierName ?? 'transporteur'},
      );
    }
    if (lower == 'missing_courier_settings') {
      return L10n.tr(
        context,
        'fulfillment.error_missing_courier_settings',
        params: {'courier': _selectedCourierName ?? 'transporteur'},
      );
    }
    if (lower == 'courier_rate_limited') {
      return L10n.tr(context, 'fulfillment.error_courier_rate_limited');
    }
    if (cleaned.isEmpty || cleaned.startsWith('FunctionException(')) {
      return L10n.tr(context, 'common.error');
    }
    return cleaned;
  }

  @override
  Widget build(BuildContext context) {
    final courierDisplay =
        _selectedCourierName ??
        _couriers
            .firstWhere(
              (c) => c['id']?.toString() == _selectedCourierId,
              orElse: () => const <String, dynamic>{},
            )['name']
            ?.toString() ??
        L10n.tr(context, 'fulfillment.not_specified');

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_orderCancelled) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              L10n.tr(context, 'fulfillment.order_cancelled_blocked'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        if (_arrangedDelivery) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              L10n.tr(context, 'fulfillment.arranged_no_label'),
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
        if (_hasLockedClientSelection) ...[
          Text(
            L10n.tr(context, 'fulfillment.customer_choice'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.tr(context, 'fulfillment.customer_choice_locked'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                _summaryRow(
                  context,
                  L10n.tr(context, 'fulfillment.choose_courier'),
                  courierDisplay,
                ),
                _summaryRow(
                  context,
                  L10n.tr(context, 'fulfillment.delivery_mode'),
                  _deliveryModeLabel(context, _deliveryMode),
                ),
                _summaryRow(
                  context,
                  L10n.tr(context, 'fulfillment.option_client'),
                  _clientOptionLabel(context, _option),
                ),
              ],
            ),
          ),
        ] else ...[
          Text(
            L10n.tr(context, 'fulfillment.choose_courier'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedCourierId,
            items: _couriers
                .map(
                  (c) => DropdownMenuItem(
                    value: c['id'].toString(),
                    child: Text(
                      c['name']?.toString() ??
                          L10n.tr(context, 'fulfillment.courier_placeholder'),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              final courier = _couriers.firstWhere(
                (c) => c['id'].toString() == v,
                orElse: () => {},
              );
              setState(() {
                _selectedCourierId = v;
                _selectedCourierName = courier['name']?.toString();
              });
            },
          ),
          const SizedBox(height: 16),
          Text(
            L10n.tr(context, 'fulfillment.delivery_mode'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Column(
            children: [
              RadioListTile<String>(
                value: 'home',
                groupValue: _deliveryMode,
                onChanged: (v) => setState(() => _deliveryMode = v),
                title: Text(L10n.tr(context, 'fulfillment.delivery_home')),
              ),
              RadioListTile<String>(
                value: 'pickup_postal',
                groupValue: _deliveryMode,
                onChanged: (v) => setState(() => _deliveryMode = v),
                title: Text(L10n.tr(context, 'fulfillment.delivery_pickup')),
              ),
              RadioListTile<String>(
                value: 'local_driver',
                groupValue: _deliveryMode,
                onChanged: (v) => setState(() => _deliveryMode = v),
                title: Text(L10n.tr(context, 'fulfillment.delivery_local')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            L10n.tr(context, 'fulfillment.option_client'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          DropdownButtonFormField<String>(
            value: _option,
            items: _optionChoices
                .map(
                  (o) => DropdownMenuItem(
                    value: o,
                    child: Text(ShippingService.optionLabel(context, o)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _option = v),
          ),
        ],
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (_saving || _orderCancelled || _arrangedDelivery)
                ? null
                : _fulfill,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(L10n.tr(context, 'fulfillment.generate_label')),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          L10n.tr(context, 'fulfillment.title', params: {'id': widget.orderId}),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(child: body),
            ),
    );
  }
}
