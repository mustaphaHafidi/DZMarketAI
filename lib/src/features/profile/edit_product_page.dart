import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/product_service.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/storage_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class EditProductPage extends StatefulWidget {
  const EditProductPage({super.key, required this.product});

  final Product product;

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _wilayaCtrl;
  late final TextEditingController _dairaCtrl;
  late final TextEditingController _declaredValueCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _lengthCtrl;
  String _condition = 'new';
  bool _deliveryCod = true;
  bool _deliveryPickup = false;
  bool _isNegotiable = true;
  bool _freeShipping = false;
  bool _exchangeAfterDelivery = false;
  bool _insuranceActive = false;
  bool _allowStopdesk = true;
  final List<String> _existingImages = [];
  final List<PlatformFile> _newImages = [];
  bool _saving = false;
  static const int _minWeightKg = 1;
  static const int _maxWeightKg = 60;
  static const _conditions = ['new', 'like new', 'good', 'fair'];

  String _conditionLabel(BuildContext context, String value) {
    switch (value) {
      case 'new':
        return L10n.tr(context, 'condition.new');
      case 'like new':
        return L10n.tr(context, 'condition.like_new');
      case 'good':
        return L10n.tr(context, 'condition.good');
      case 'fair':
        return L10n.tr(context, 'condition.fair');
      default:
        return value;
    }
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.product.title);
    _priceCtrl = TextEditingController(
      text: widget.product.price.toStringAsFixed(0),
    );
    _stockCtrl = TextEditingController(
      text: widget.product.stockQuantity.toString(),
    );
    _costCtrl = TextEditingController(
      text: widget.product.costPrice?.toStringAsFixed(0) ?? '',
    );
    _descCtrl = TextEditingController(text: widget.product.description ?? '');
    _categoryCtrl = TextEditingController(text: widget.product.category ?? '');
    _brandCtrl = TextEditingController(text: widget.product.brand ?? '');
    _sizeCtrl = TextEditingController(text: widget.product.size ?? '');
    _wilayaCtrl = TextEditingController(
      text: widget.product.locationWilaya ?? '',
    );
    _dairaCtrl = TextEditingController(
      text: widget.product.locationDaira ?? '',
    );
    _condition = widget.product.condition ?? 'new';
    _deliveryCod = widget.product.deliveryOptions.contains('cod');
    _deliveryPickup = widget.product.deliveryOptions.contains('pickup');
    _isNegotiable = widget.product.isNegotiable;
    _freeShipping = widget.product.shippingFree;
    _exchangeAfterDelivery = widget.product.exchangeAfterDelivery;
    _insuranceActive = widget.product.insuranceActive;
    _allowStopdesk = widget.product.allowStopdesk;
    final declaredValue = widget.product.declaredValue ?? widget.product.price;
    _declaredValueCtrl = TextEditingController(
      text: declaredValue.toStringAsFixed(0),
    );
    _weightCtrl = TextEditingController(
      text: (widget.product.weightKg ?? 1).toString(),
    );
    _heightCtrl = TextEditingController(
      text: (widget.product.heightCm ?? 0).toString(),
    );
    _widthCtrl = TextEditingController(
      text: (widget.product.widthCm ?? 0).toString(),
    );
    _lengthCtrl = TextEditingController(
      text: (widget.product.lengthCm ?? 0).toString(),
    );
    _existingImages.addAll(widget.product.imageUrls);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _costCtrl.dispose();
    _descCtrl.dispose();
    _categoryCtrl.dispose();
    _brandCtrl.dispose();
    _sizeCtrl.dispose();
    _wilayaCtrl.dispose();
    _dairaCtrl.dispose();
    _declaredValueCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _widthCtrl.dispose();
    _lengthCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.image,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _newImages.addAll(result.files));
  }

  void _removeExistingImage(int index) {
    setState(() => _existingImages.removeAt(index));
  }

  void _removeNewImage(int index) {
    setState(() => _newImages.removeAt(index));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final price = InputSanitizer.parseAmount(_priceCtrl.text, min: 0);
      final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;
      if (stock < 0) {
        throw FormatException(
          L10n.tr(context, 'listing.edit.error_invalid_stock'),
        );
      }
      final costPrice = _costCtrl.text.trim().isEmpty
          ? null
          : InputSanitizer.parseAmount(_costCtrl.text, min: 0);
      final title = InputSanitizer.sanitizeText(_titleCtrl.text, maxLength: 80);
      if (title.isEmpty) {
        throw FormatException(
          L10n.tr(context, 'listing.edit.error_title_required'),
        );
      }
      final description = InputSanitizer.sanitizeOptionalText(
        _descCtrl.text,
        maxLength: 1200,
        allowNewlines: true,
      );
      final brand = InputSanitizer.sanitizeOptionalText(
        _brandCtrl.text,
        maxLength: 40,
      );
      final size = InputSanitizer.sanitizeOptionalText(
        _sizeCtrl.text,
        maxLength: 40,
      );
      final wilaya = InputSanitizer.sanitizeOptionalText(
        _wilayaCtrl.text,
        maxLength: 60,
      );
      final daira = InputSanitizer.sanitizeOptionalText(
        _dairaCtrl.text,
        maxLength: 60,
      );
      final categoryName = InputSanitizer.sanitizeOptionalText(
        _categoryCtrl.text,
        maxLength: 80,
      );
      final weight = int.tryParse(_weightCtrl.text.trim()) ?? 0;
      final height = int.tryParse(_heightCtrl.text.trim()) ?? 0;
      final width = int.tryParse(_widthCtrl.text.trim()) ?? 0;
      final length = int.tryParse(_lengthCtrl.text.trim()) ?? 0;
      if (weight < _minWeightKg || weight > _maxWeightKg) {
        throw FormatException(
          L10n.tr(
            context,
            'checkout.error_weight_range',
            params: {
              'min': _minWeightKg.toString(),
              'max': _maxWeightKg.toString(),
            },
          ),
        );
      }
      if (height < 0 || height > 200) {
        throw FormatException(
          L10n.tr(context, 'checkout.error_height_invalid'),
        );
      }
      if (width < 0 || width > 200) {
        throw FormatException(L10n.tr(context, 'checkout.error_width_invalid'));
      }
      if (length < 0 || length > 200) {
        throw FormatException(
          L10n.tr(context, 'checkout.error_length_invalid'),
        );
      }
      final declaredValue = _declaredValueCtrl.text.trim().isEmpty
          ? null
          : InputSanitizer.parseAmount(_declaredValueCtrl.text, min: 0);
      if (_insuranceActive && declaredValue == null) {
        throw FormatException(
          L10n.tr(context, 'checkout.error_price_required'),
        );
      }
      final sellerId = supabase.auth.currentUser?.id;
      if (sellerId != null) {
        final enabledCouriers = await ShippingService()
            .fetchEnabledCouriersForSeller(sellerId);
        final parcelRules = enabledCouriers.isNotEmpty
            ? await ShippingService.aggregateParcelRulesAsync(enabledCouriers)
            : CourierParcelRules.generic;
        if (!mounted) return;
        final validation = ShippingService.validateParcel(
          rules: parcelRules,
          weightKg: weight,
          heightCm: height,
          widthCm: width,
          lengthCm: length,
          declaredValue: declaredValue,
          codAmount: price.toDouble(),
          insuranceActive: _insuranceActive,
        );
        if (validation != null) {
          switch (validation.code) {
            case 'weight_range':
              throw FormatException(
                L10n.tr(
                  context,
                  'checkout.error_weight_range',
                  params: validation.params,
                ),
              );
            case 'height_max':
              throw FormatException(
                L10n.tr(
                  context,
                  'checkout.error_height_max',
                  params: validation.params,
                  fallback: L10n.tr(context, 'checkout.error_height_invalid'),
                ),
              );
            case 'width_max':
              throw FormatException(
                L10n.tr(
                  context,
                  'checkout.error_width_max',
                  params: validation.params,
                  fallback: L10n.tr(context, 'checkout.error_width_invalid'),
                ),
              );
            case 'length_max':
              throw FormatException(
                L10n.tr(
                  context,
                  'checkout.error_length_max',
                  params: validation.params,
                  fallback: L10n.tr(context, 'checkout.error_length_invalid'),
                ),
              );
            case 'volume_max':
              throw FormatException(
                L10n.tr(
                  context,
                  'checkout.error_volume_max',
                  params: validation.params,
                  fallback: L10n.tr(context, 'checkout.error_length_invalid'),
                ),
              );
            case 'cod_amount_max':
              throw FormatException(
                L10n.tr(
                  context,
                  'checkout.error_cod_amount_max',
                  params: {'max': validation.params['max'] ?? '150000'},
                ),
              );
            case 'declared_value_max':
              throw FormatException(
                L10n.tr(
                  context,
                  'checkout.error_declared_value_max',
                  params: {'max': validation.params['max'] ?? ''},
                ),
              );
            default:
              throw FormatException(L10n.tr(context, 'common.error'));
          }
        }
      }
      final deliveryOptions = <String>[
        if (_deliveryCod) 'cod',
        if (_deliveryPickup) 'pickup',
      ];

      final bytes = _newImages
          .map((f) => f.bytes)
          .whereType<Uint8List>()
          .toList();
      final names = _newImages.map((f) => f.name).toList();
      if (bytes.length != _newImages.length) {
        throw StateError(L10n.tr(context, 'listing.edit.error_file_read'));
      }
      final uploaded = bytes.isEmpty
          ? <String>[]
          : await StorageService().uploadImages(files: bytes, fileNames: names);
      if (!mounted) return;
      final allImages = [..._existingImages, ...uploaded];
      final imageUrl = allImages.isNotEmpty ? allImages.first : null;
      await ProductService().updateProduct(
        id: widget.product.id.toString(),
        title: title,
        price: price,
        stockQuantity: stock,
        costPrice: costPrice,
        description: description,
        imageUrl: imageUrl,
        imageUrls: allImages,
        categoryName: categoryName,
        condition: _condition,
        brand: brand,
        size: size,
        locationWilaya: wilaya,
        locationDaira: daira,
        deliveryOptions: deliveryOptions,
        isNegotiable: _isNegotiable,
        shippingFree: _freeShipping,
        exchangeAfterDelivery: _exchangeAfterDelivery,
        insuranceActive: _insuranceActive,
        allowStopdesk: _allowStopdesk,
        declaredValue: declaredValue,
        weightKg: weight,
        heightCm: height,
        widthCm: width,
        lengthCm: length,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.tr(context, 'listing.edit.saved'))),
      );
      Navigator.pop(context);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr(context, 'listing.edit.title')),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(L10n.tr(context, 'common.save')),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < _existingImages.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          _existingImages[i],
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: InkWell(
                          onTap: () => _removeExistingImage(i),
                          child: const CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black54,
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                for (var i = 0; i < _newImages.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _newImages[i].bytes == null
                            ? Container(
                                width: 96,
                                height: 96,
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.image_outlined),
                              )
                            : Image.memory(
                                _newImages[i].bytes!,
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                              ),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: InkWell(
                          onTap: () => _removeNewImage(i),
                          child: const CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black54,
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                InkWell(
                  onTap: _pickImages,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'listing.add.title_label'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'listing.add.price_label'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stockCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'listing.add.stock_label'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _costCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'listing.add.cost_label'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'listing.add.description_label'),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryCtrl,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'listing.add.category_label'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _brandCtrl,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'listing.add.brand_label'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sizeCtrl,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'listing.add.size_label'),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _condition,
              items: _conditions
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(_conditionLabel(context, c)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _condition = value ?? 'new'),
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'listing.add.condition_label'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wilayaCtrl,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'listing.add.wilaya_label'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dairaCtrl,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'listing.add.commune_label'),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _deliveryCod,
              onChanged: (value) => setState(() => _deliveryCod = value),
              title: Text(L10n.tr(context, 'listing.add.delivery_cod')),
            ),
            SwitchListTile(
              value: _deliveryPickup,
              onChanged: (value) => setState(() => _deliveryPickup = value),
              title: Text(L10n.tr(context, 'listing.add.delivery_pickup')),
            ),
            SwitchListTile(
              value: _isNegotiable,
              onChanged: (value) => setState(() => _isNegotiable = value),
              title: Text(
                L10n.tr(
                  context,
                  'listing.add.negotiable_label',
                  fallback: 'Prix négociable',
                ),
              ),
              subtitle: Text(
                L10n.tr(
                  context,
                  'listing.add.negotiable_hint',
                  fallback: 'Autoriser les acheteurs à envoyer des offres.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              L10n.tr(context, 'checkout.package_details'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            CheckboxListTile(
              value: _freeShipping,
              onChanged: (v) => setState(() => _freeShipping = v ?? false),
              title: Text(L10n.tr(context, 'checkout.free_shipping')),
            ),
            CheckboxListTile(
              value: _exchangeAfterDelivery,
              onChanged: (v) =>
                  setState(() => _exchangeAfterDelivery = v ?? false),
              title: Text(L10n.tr(context, 'checkout.exchange_after_delivery')),
            ),
            CheckboxListTile(
              value: _allowStopdesk,
              onChanged: (v) => setState(() => _allowStopdesk = v ?? true),
              title: Text(L10n.tr(context, 'listing.add.allow_stopdesk')),
            ),
            const SizedBox(height: 8),
            Text(
              L10n.tr(context, 'checkout.insurance'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            SwitchListTile(
              value: _insuranceActive,
              onChanged: (v) => setState(() => _insuranceActive = v),
              title: Text(L10n.tr(context, 'checkout.insurance_active')),
            ),
            TextField(
              controller: _declaredValueCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'checkout.declared_value'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              L10n.tr(context, 'checkout.dimensions_weight'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            TextField(
              controller: _weightCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'checkout.weight_kg'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _heightCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'checkout.height_cm'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _widthCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'checkout.width_cm'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _lengthCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'checkout.length_cm'),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(L10n.tr(context, 'common.save')),
            ),
          ],
        ),
      ),
    );
  }
}
