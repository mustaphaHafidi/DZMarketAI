// ignore_for_file: deprecated_member_use
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/models/order.dart';
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
  String? _selectedCourierId;
  String? _selectedCourierName;
  String? _deliveryMode = 'home';
  String? _option = ShippingService.options.first;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCouriers();
  }

  Future<void> _loadCouriers() async {
    final list = await _shipping.fetchCouriers();
    setState(() {
      _couriers = list;
      if (list.isNotEmpty) {
        _selectedCourierId = list.first['id'].toString();
        _selectedCourierName = list.first['name']?.toString();
      }
    });
  }

  Future<void> _fulfill() async {
    if (_selectedCourierId == null || _selectedCourierName == null) {
      setState(() => _error = 'Sélectionnez un transporteur');
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
          const SnackBar(
            content: Text('Expédition déclenchée avec bordereau.'),
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
        const Text(
          'Choisir un transporteur',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedCourierId,
          items: _couriers
              .map(
                (c) => DropdownMenuItem(
                  value: c['id'].toString(),
                  child: Text(c['name']?.toString() ?? 'Transporteur'),
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
        const Text(
          'Mode de livraison',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Column(
          children: [
            RadioListTile<String>(
              value: 'home',
              groupValue: _deliveryMode,
              onChanged: (v) => setState(() => _deliveryMode = v),
              title: const Text('Domicile'),
            ),
            RadioListTile<String>(
              value: 'pickup_postal',
              groupValue: _deliveryMode,
              onChanged: (v) => setState(() => _deliveryMode = v),
              title: const Text('Point relais / bureau poste'),
            ),
            RadioListTile<String>(
              value: 'local_driver',
              groupValue: _deliveryMode,
              onChanged: (v) => setState(() => _deliveryMode = v),
              title: const Text('Coursier local'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Option client',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        DropdownButtonFormField<String>(
          value: _option,
          items: ShippingService.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) => setState(() => _option = v),
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
                : const Text('Générer bordereau + expédier'),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text('Expédition #${widget.orderId}')),
      body: _couriers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(child: body),
            ),
    );
  }
}
