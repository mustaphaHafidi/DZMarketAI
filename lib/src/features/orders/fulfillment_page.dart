// ignore_for_file: deprecated_member_use
import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/order.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
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
  bool _loading = true;

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
        .select('courier_id,courier_name,delivery_method,shipping_option')
        .eq('id', widget.orderId)
        .maybeSingle();
    if (orderRow is Map<String, dynamic>) {
      final courierId = orderRow['courier_id']?.toString();
      final courierName = orderRow['courier_name']?.toString();
      final deliveryMode = orderRow['delivery_method']?.toString();
      final option = orderRow['shipping_option']?.toString();
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
    final list = await _shipping.fetchCouriers();
    final updated = List<Map<String, dynamic>>.from(list);
    if (_selectedCourierId != null &&
        updated.every((c) => c['id']?.toString() != _selectedCourierId)) {
      updated.insert(
        0,
        {
          'id': _selectedCourierId,
          'name': _selectedCourierName ?? L10n.tr(context, 'fulfillment.courier_placeholder'),
        },
      );
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
    if (_selectedCourierId == null || _selectedCourierName == null) {
      setState(() => _error = L10n.tr(context, 'fulfillment.error_select_courier'));
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
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.tr(context, 'fulfillment.choose_courier'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_courierLocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              L10n.tr(context, 'fulfillment.courier_locked'),
              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
            ),
          ),
        DropdownButtonFormField<String>(
          value: _selectedCourierId,
          items: _couriers
              .map(
                (c) => DropdownMenuItem(
                  value: c['id'].toString(),
                  child: Text(c['name']?.toString() ?? L10n.tr(context, 'fulfillment.courier_placeholder')),
                ),
              )
              .toList(),
          onChanged: _courierLocked
              ? null
              : (v) {
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
              onChanged:
                  _deliveryLocked ? null : (v) => setState(() => _deliveryMode = v),
              title: Text(L10n.tr(context, 'fulfillment.delivery_home')),
            ),
            RadioListTile<String>(
              value: 'pickup_postal',
              groupValue: _deliveryMode,
              onChanged:
                  _deliveryLocked ? null : (v) => setState(() => _deliveryMode = v),
              title: Text(L10n.tr(context, 'fulfillment.delivery_pickup')),
            ),
            RadioListTile<String>(
              value: 'local_driver',
              groupValue: _deliveryMode,
              onChanged:
                  _deliveryLocked ? null : (v) => setState(() => _deliveryMode = v),
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
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: _optionLocked ? null : (v) => setState(() => _option = v),
        ),
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
            onPressed: _saving ? null : _fulfill,
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
          L10n.tr(
            context,
            'fulfillment.title',
            params: {'id': widget.orderId},
          ),
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
