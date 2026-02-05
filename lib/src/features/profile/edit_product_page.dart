import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/product_service.dart';
import 'package:dzmarket/src/services/storage_service.dart';

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
  String _condition = 'new';
  bool _deliveryCod = true;
  bool _deliveryPickup = false;
  final List<String> _existingImages = [];
  final List<PlatformFile> _newImages = [];
  bool _saving = false;
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
    _priceCtrl = TextEditingController(text: widget.product.price.toStringAsFixed(0));
    _stockCtrl =
        TextEditingController(text: widget.product.stockQuantity.toString());
    _costCtrl = TextEditingController(
      text: widget.product.costPrice?.toStringAsFixed(0) ?? '',
    );
    _descCtrl = TextEditingController(text: widget.product.description ?? '');
    _categoryCtrl = TextEditingController(text: widget.product.category ?? '');
    _brandCtrl = TextEditingController(text: widget.product.brand ?? '');
    _sizeCtrl = TextEditingController(text: widget.product.size ?? '');
    _wilayaCtrl = TextEditingController(text: widget.product.locationWilaya ?? '');
    _dairaCtrl = TextEditingController(text: widget.product.locationDaira ?? '');
    _condition = widget.product.condition ?? 'new';
    _deliveryCod = widget.product.deliveryOptions.contains('cod');
    _deliveryPickup = widget.product.deliveryOptions.contains('pickup');
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
        throw FormatException(L10n.tr(context, 'listing.edit.error_invalid_stock'));
      }
      final costPrice = _costCtrl.text.trim().isEmpty
          ? null
          : InputSanitizer.parseAmount(_costCtrl.text, min: 0);
      final title = InputSanitizer.sanitizeText(_titleCtrl.text, maxLength: 80);
      if (title.isEmpty) {
        throw FormatException(L10n.tr(context, 'listing.edit.error_title_required'));
      }
      final description = InputSanitizer.sanitizeOptionalText(
        _descCtrl.text,
        maxLength: 1200,
        allowNewlines: true,
      );
      final brand = InputSanitizer.sanitizeOptionalText(_brandCtrl.text, maxLength: 40);
      final size = InputSanitizer.sanitizeOptionalText(_sizeCtrl.text, maxLength: 40);
      final wilaya =
          InputSanitizer.sanitizeOptionalText(_wilayaCtrl.text, maxLength: 60);
      final daira =
          InputSanitizer.sanitizeOptionalText(_dairaCtrl.text, maxLength: 60);
      final categoryName =
          InputSanitizer.sanitizeOptionalText(_categoryCtrl.text, maxLength: 80);
      final deliveryOptions = <String>[
        if (_deliveryCod) 'cod',
        if (_deliveryPickup) 'pickup',
      ];

      final bytes = _newImages.map((f) => f.bytes).whereType<Uint8List>().toList();
      final names = _newImages.map((f) => f.name).toList();
      if (bytes.length != _newImages.length) {
        throw StateError(L10n.tr(context, 'listing.edit.error_file_read'));
      }
      final uploaded = bytes.isEmpty
          ? <String>[]
          : await StorageService().uploadImages(files: bytes, fileNames: names);
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
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.tr(context, 'listing.edit.saved'))),
      );
      Navigator.pop(context);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
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
                            child: Icon(Icons.close, size: 14, color: Colors.white),
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
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
                            child: Icon(Icons.close, size: 14, color: Colors.white),
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
              decoration: InputDecoration(labelText: L10n.tr(context, 'listing.add.title_label')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: L10n.tr(context, 'listing.add.price_label')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stockCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: L10n.tr(context, 'listing.add.stock_label')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _costCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: L10n.tr(context, 'listing.add.cost_label')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(labelText: L10n.tr(context, 'listing.add.description_label')),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryCtrl,
              decoration: InputDecoration(labelText: L10n.tr(context, 'listing.add.category_label')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _brandCtrl,
              decoration: InputDecoration(labelText: L10n.tr(context, 'listing.add.brand_label')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sizeCtrl,
              decoration: InputDecoration(labelText: L10n.tr(context, 'listing.add.size_label')),
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
              decoration: InputDecoration(labelText: L10n.tr(context, 'listing.add.wilaya_label')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dairaCtrl,
              decoration: InputDecoration(labelText: L10n.tr(context, 'listing.add.commune_label')),
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





