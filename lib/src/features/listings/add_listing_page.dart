import 'dart:typed_data';

import 'package:dzmarket/src/features/profile/my_listings_page.dart';
import 'package:dzmarket/src/services/category_service.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/location_data_service.dart';
import 'package:dzmarket/src/services/product_service.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/storage_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddListingPage extends StatefulWidget {
  const AddListingPage({super.key});

  @override
  State<AddListingPage> createState() => _AddListingPageState();
}

class _AddListingPageState extends State<AddListingPage> {
  static const int _minWeightKg = 1;
  static const int _maxWeightKg = 60;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _declaredValueCtrl = TextEditingController();
  final _weightCtrl = TextEditingController(text: '1');
  final _heightCtrl = TextEditingController(text: '0');
  final _widthCtrl = TextEditingController(text: '0');
  final _lengthCtrl = TextEditingController(text: '0');
  String? _selectedWilayaCode;
  String? _selectedCommune;
  String _condition = 'new';
  String? _categoryId;
  String? _categoryNameFr;
  bool _deliveryCod = true;
  bool _deliveryPickup = false;
  bool _freeShipping = false;
  bool _exchangeAfterDelivery = false;
  bool _insuranceActive = false;
  bool _allowStopdesk = true;
  bool _loadingCouriers = false;
  CourierCapabilities _courierCaps = CourierCapabilities.all;
  List<Map<String, dynamic>> _enabledCouriers = const [];
  int _step = 0;
  bool _saving = false;
  String? _error;
  bool _loadingCategories = false;
  bool _loadingLocations = false;
  String? _categoryLoadError;
  String? _locationLoadError;
  List<Map<String, String>> _categories = const [];
  List<Map<String, String>> _wilayas = const [];
  List<Map<String, String>> _communes = const [];
  final List<PlatformFile> _pickedFiles = [];

  final _conditions = const ['new', 'like new', 'good', 'fair'];

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
    _loadCategories();
    _loadLocations();
    _loadEnabledCouriers();
    _titleCtrl.addListener(_onFieldChanged);
    _descCtrl.addListener(_onFieldChanged);
    _priceCtrl.addListener(_onFieldChanged);
    _stockCtrl.addListener(_onFieldChanged);
    _costCtrl.addListener(_onFieldChanged);
    _priceCtrl.addListener(() {
      if (_declaredValueCtrl.text.trim().isEmpty) {
        _declaredValueCtrl.text = _priceCtrl.text.trim();
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onFieldChanged);
    _descCtrl.removeListener(_onFieldChanged);
    _priceCtrl.removeListener(_onFieldChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _costCtrl.dispose();
    _brandCtrl.dispose();
    _sizeCtrl.dispose();
    _declaredValueCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _widthCtrl.dispose();
    _lengthCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoryLoadError = null;
    });
    final items = await CategoryService().fetchCategories();
    if (!mounted) return;
    setState(() {
      _categories = items;
      _loadingCategories = false;
      if (items.isEmpty) {
        _categoryLoadError = L10n.tr(context, 'listing.add.error_no_categories');
      }
    });
  }

  Future<void> _loadLocations() async {
    setState(() {
      _loadingLocations = true;
      _locationLoadError = null;
    });
    final items = await LocationDataService.instance.fetchWilayas();
    if (!mounted) return;
    setState(() {
      _wilayas = items;
      _loadingLocations = false;
      if (items.isEmpty) {
        _locationLoadError = L10n.tr(context, 'listing.add.error_no_wilayas');
      }
    });
  }

  void _applyCourierCaps() {
    if (!_courierCaps.supportsStopdesk) {
      _allowStopdesk = false;
      _deliveryPickup = false;
    }
    if (!_courierCaps.supportsExchange) {
      _exchangeAfterDelivery = false;
    }
    if (!_courierCaps.supportsInsurance) {
      _insuranceActive = false;
      if (_declaredValueCtrl.text.trim().isNotEmpty) {
        _declaredValueCtrl.text = '';
      }
    }
  }

  Future<void> _loadEnabledCouriers() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() {
      _loadingCouriers = true;
    });
    final rows = await ShippingService().fetchEnabledCouriersForSeller(userId);
    if (!mounted) return;
    setState(() {
      _enabledCouriers = rows;
      _courierCaps = ShippingService.aggregateCapabilities(rows);
      _applyCourierCaps();
      _loadingCouriers = false;
    });
  }

  void _onWilayaSelected(String? code) {
    setState(() {
      _selectedWilayaCode = code;
      _selectedCommune = null;
      _communes = const [];
    });
    if (code == null || code.isEmpty) return;
    _loadCommunes(code);
  }

  Future<void> _loadCommunes(String code) async {
    setState(() {
      _loadingLocations = true;
      _locationLoadError = null;
    });
    final items = await LocationDataService.instance.fetchCommunes(code);
    if (!mounted) return;
    setState(() {
      _communes = items;
      _loadingLocations = false;
      if (items.isEmpty) {
        _locationLoadError = L10n.tr(context, 'listing.add.error_no_communes');
      }
    });
  }

  Future<Map<String, String>?> _showLocationPicker({
    required BuildContext context,
    required String title,
    required List<Map<String, String>> items,
    required String Function(Map<String, String>) itemLabel,
  }) {
    final searchCtrl = TextEditingController();
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (sheetContext, setState) {
              final query = searchCtrl.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? items
                  : items.where((item) {
                      final label = itemLabel(item).toLowerCase();
                      final code = (item['code'] ?? '').toLowerCase();
                      return label.contains(query) || code.contains(query);
                    }).toList();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      title,
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: L10n.tr(sheetContext, 'common.search'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        return ListTile(
                          title: Text(itemLabel(item)),
                          onTap: () => Navigator.of(sheetContext).pop(item),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPickerField({
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: onTap != null,
        ),
        child: Row(
          children: [
            Expanded(child: Text(value)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.image,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _pickedFiles.addAll(result.files);
    });
  }

  void _removeImage(int index) {
    setState(() {
      _pickedFiles.removeAt(index);
    });
  }

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        if (_pickedFiles.isEmpty) {
          _setError(L10n.tr(context, 'listing.add.error_min_photo'));
          return false;
        }
        return true;
      case 1:
        if ((_categoryId ?? '').isEmpty) {
          _setError(L10n.tr(context, 'listing.add.error_choose_category'));
          return false;
        }
        return true;
      case 2:
        if (_titleCtrl.text.trim().isEmpty) {
          _setError(L10n.tr(context, 'listing.add.error_add_title'));
          return false;
        }
        if (_descCtrl.text.trim().isEmpty) {
          _setError(L10n.tr(context, 'listing.add.error_add_description'));
          return false;
        }
        return true;
      case 3:
        try {
          InputSanitizer.parseAmount(_priceCtrl.text, min: 1);
          final stock = _parseDigits(_stockCtrl.text.trim());
          if (stock <= 0) {
            _setError(L10n.tr(context, 'listing.add.error_invalid_stock'));
            return false;
          }
          if (_costCtrl.text.trim().isNotEmpty) {
            InputSanitizer.parseAmount(_costCtrl.text, min: 0);
          }
        } on FormatException catch (e) {
          _setError(e.message);
          return false;
        }
        return true;
      case 4:
        if (_selectedWilayaCode == null || _selectedCommune == null) {
          _setError(L10n.tr(context, 'listing.add.error_invalid_location'));
          return false;
        }
        return true;
      case 5:
        if (!_deliveryCod && !_deliveryPickup) {
          _setError(L10n.tr(context, 'listing.add.error_choose_delivery'));
          return false;
        }
        return true;
      case 6:
        final weight = _parseDigitsNullable(_weightCtrl.text.trim());
        final height = _parseDigitsNullable(_heightCtrl.text.trim());
        final width = _parseDigitsNullable(_widthCtrl.text.trim());
        final length = _parseDigitsNullable(_lengthCtrl.text.trim());
        if (weight == null ||
            weight < _minWeightKg ||
            weight > _maxWeightKg) {
          _setError(
            L10n.tr(
              context,
              'checkout.error_weight_range',
              params: {
                'min': _minWeightKg.toString(),
                'max': _maxWeightKg.toString(),
              },
            ),
          );
          return false;
        }
        if (height == null || height < 0 || height > 200) {
          _setError(L10n.tr(context, 'checkout.error_height_invalid'));
          return false;
        }
        if (width == null || width < 0 || width > 200) {
          _setError(L10n.tr(context, 'checkout.error_width_invalid'));
          return false;
        }
        if (length == null || length < 0 || length > 200) {
          _setError(L10n.tr(context, 'checkout.error_length_invalid'));
          return false;
        }
        if (_insuranceActive &&
            _declaredValueCtrl.text.trim().isEmpty) {
          _setError(L10n.tr(context, 'checkout.error_price_required'));
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _setError(String message) {
    setState(() => _error = message);
  }

  void _clearError() {
    if (_error != null) {
      setState(() => _error = null);
    }
  }

  void _onFieldChanged() {
    if (!mounted) return;
    setState(() {});
  }

  int _parseDigits(String value, {int fallback = 0}) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? fallback;
  }

  int? _parseDigitsNullable(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  void _next() {
    _clearError();
    if (!_validateStep(_step)) return;
    setState(() {
      _step = (_step + 1).clamp(0, 7);
    });
  }

  void _back() {
    if (_step == 0) return;
    setState(() {
      _step = (_step - 1).clamp(0, 6);
    });
  }

  Future<void> _publish() async {
    _clearError();
    if (!_validateStep(6)) return;
    setState(() => _saving = true);
    try {
      final title = InputSanitizer.sanitizeText(_titleCtrl.text, maxLength: 80);
      final description = InputSanitizer.sanitizeOptionalText(
        _descCtrl.text,
        maxLength: 1200,
        allowNewlines: true,
      );
      final price = InputSanitizer.parseAmount(_priceCtrl.text, min: 1);
      final stock = _parseDigits(_stockCtrl.text.trim());
      if (stock <= 0) {
        throw FormatException(L10n.tr(context, 'listing.add.error_invalid_stock'));
      }
      final costPrice = _costCtrl.text.trim().isEmpty
          ? null
          : InputSanitizer.parseAmount(_costCtrl.text, min: 0);
      final brand = InputSanitizer.sanitizeOptionalText(_brandCtrl.text, maxLength: 40);
      final size = InputSanitizer.sanitizeOptionalText(_sizeCtrl.text, maxLength: 40);
      final wilaya = InputSanitizer.sanitizeText(
        _wilayaLabel(context),
        maxLength: 60,
      );
      final daira =
          InputSanitizer.sanitizeText(
            _selectedCommuneLabel(context),
            maxLength: 60,
          );
      final categoryId =
          InputSanitizer.sanitizeText(_categoryId ?? '', maxLength: 20);
      final categoryName = InputSanitizer.sanitizeOptionalText(
        _categoryNameFr,
        maxLength: 80,
      );
      if (title.isEmpty || categoryId.isEmpty) {
        throw FormatException(L10n.tr(context, 'listing.add.error_missing_info'));
      }

      final bytes = _pickedFiles.map((f) => f.bytes).whereType<Uint8List>().toList();
      final names = _pickedFiles.map((f) => f.name).toList();
      if (bytes.length != _pickedFiles.length) {
        throw StateError(L10n.tr(context, 'listing.add.error_file_read'));
      }
      final uploaded = await StorageService().uploadImages(
        files: bytes,
        fileNames: names,
      );
      final deliveryOptions = <String>[
        if (_deliveryCod) 'cod',
        if (_deliveryPickup) 'pickup',
      ];
      final weight = _parseDigits(_weightCtrl.text.trim(), fallback: 1);
      final height = _parseDigits(_heightCtrl.text.trim());
      final width = _parseDigits(_widthCtrl.text.trim());
      final length = _parseDigits(_lengthCtrl.text.trim());
      final declaredValue = _declaredValueCtrl.text.trim().isEmpty
          ? null
          : InputSanitizer.parseAmount(_declaredValueCtrl.text, min: 0);

      await ProductService().createProduct(
        title: title,
        price: price,
        description: description,
        imageUrl: uploaded.isNotEmpty ? uploaded.first : null,
        imageUrls: uploaded,
        categoryId: categoryId,
        categoryName: categoryName,
        condition: _condition,
        brand: brand,
        size: size,
        locationWilaya: wilaya,
        locationDaira: daira,
        deliveryOptions: deliveryOptions,
        stockQuantity: stock,
        costPrice: costPrice,
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MyListingsPage()),
      );
    } on FormatException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _deliveryOptionsPreview(BuildContext context) {
    final options = <String>[];
    if (_deliveryCod) {
      options.add(L10n.tr(context, 'listing.add.delivery_cod'));
    }
    if (_deliveryPickup) {
      options.add(L10n.tr(context, 'listing.add.delivery_pickup'));
    }
    return options;
  }

  bool _hasArabicLetters(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }

  bool _looksMojibake(String value) {
    return value.contains('Ã') || value.contains('Â') || value.contains('�');
  }

  String _pickLocalizedName(BuildContext context, String fr, String ar) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    if (!isAr) return fr.isNotEmpty ? fr : ar;
    if (_hasArabicLetters(ar)) return ar;
    return fr.isNotEmpty ? fr : ar;
  }

  String _categoryLabel(BuildContext context) {
    final id = _categoryId ?? '';
    if (id.isEmpty) return '-';
    final match = _categories.where((c) => c['id'] == id).toList();
    if (match.isEmpty) return id;
    return _categoryItemLabel(context, match.first);
  }

  String _categoryItemLabel(BuildContext context, Map<String, String> item) {
    if (item.isEmpty) return '-';
    final slug = item['slug'] ?? '';
    final fr = item['name_fr'] ?? '';
    final ar = item['name_ar'] ?? fr;
    final fallback = _pickLocalizedName(context, fr, ar);
    if (slug.isEmpty) return fallback;
    final translated = L10n.tr(context, 'category.$slug', fallback: fallback);
    return _looksMojibake(translated) ? fallback : translated;
  }

  String _wilayaLabel(BuildContext context) {
    return _wilayaLabelWithPlaceholder(context, placeholder: '-');
  }

  String _wilayaLabelWithPlaceholder(
    BuildContext context, {
    required String placeholder,
  }) {
    final code = _selectedWilayaCode;
    if (code == null || code.isEmpty) return placeholder;
    final match = _wilayas.where((w) => w['code'] == code).toList();
    if (match.isEmpty) return code;
    final fr = match.first['name_fr'] ?? code;
    final ar = match.first['name_ar'] ?? fr;
    return _pickLocalizedName(context, fr, ar);
  }

  String _wilayaItemLabel(BuildContext context, Map<String, String> item) {
    final fr = item['name_fr'] ?? '';
    final ar = item['name_ar'] ?? fr;
    return _pickLocalizedName(context, fr, ar);
  }

  String _selectedCommuneLabel(BuildContext context) {
    return _selectedCommuneLabelWithPlaceholder(context, placeholder: '-');
  }

  String _selectedCommuneLabelWithPlaceholder(
    BuildContext context, {
    required String placeholder,
  }) {
    final id = _selectedCommune;
    if (id == null || id.isEmpty) return placeholder;
    final match = _communes.where((c) => c['id'] == id).toList();
    if (match.isEmpty) return id;
    final fr = match.first['name_fr'] ?? id;
    final ar = match.first['name_ar'] ?? fr;
    return _pickLocalizedName(context, fr, ar);
  }

  String _communeItemLabel(BuildContext context, Map<String, String> item) {
    final fr = item['name_fr'] ?? '';
    final ar = item['name_ar'] ?? fr;
    return _pickLocalizedName(context, fr, ar);
  }

  bool _canContinue() {
    switch (_step) {
      case 0:
        return _pickedFiles.isNotEmpty;
      case 1:
        return (_categoryId ?? '').isNotEmpty;
      case 2:
        return _titleCtrl.text.trim().isNotEmpty &&
            _descCtrl.text.trim().isNotEmpty;
      case 3:
        try {
          InputSanitizer.parseAmount(_priceCtrl.text, min: 1);
          final stock = _parseDigits(_stockCtrl.text.trim());
          if (stock <= 0) return false;
          if (_costCtrl.text.trim().isNotEmpty) {
            InputSanitizer.parseAmount(_costCtrl.text, min: 0);
          }
          return true;
        } catch (_) {
          return false;
        }
      case 4:
        return _selectedWilayaCode != null && _selectedCommune != null;
      case 5:
        return _deliveryCod || _deliveryPickup;
      case 6:
        final weight = _parseDigits(_weightCtrl.text.trim());
        final height = _parseDigits(_heightCtrl.text.trim(), fallback: -1);
        final width = _parseDigits(_widthCtrl.text.trim(), fallback: -1);
        final length = _parseDigits(_lengthCtrl.text.trim(), fallback: -1);
        if (weight < _minWeightKg || weight > _maxWeightKg) return false;
        if (height < 0 || height > 200) return false;
        if (width < 0 || width > 200) return false;
        if (length < 0 || length > 200) return false;
        if (_insuranceActive && _declaredValueCtrl.text.trim().isEmpty) {
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr(context, 'listing.add.title')),
      ),
      body: Stepper(
        currentStep: _step,
        onStepContinue: _step == 6 ? null : (_canContinue() ? _next : null),
        onStepCancel: _back,
        onStepTapped: (index) {
          if (index <= _step) {
            setState(() => _step = index);
          }
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                if (_step > 0)
                  TextButton(
                    onPressed: _back,
                    child: Text(L10n.tr(context, 'listing.add.back')),
                  ),
                const Spacer(),
                if (_step < 7)
                  FilledButton(
                    onPressed: _canContinue() ? _next : null,
                    child: Text(L10n.tr(context, 'listing.add.continue')),
                  )
                else
                  FilledButton(
                    onPressed: _saving ? null : _publish,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(L10n.tr(context, 'listing.add.publish')),
                  ),
              ],
            ),
          );
        },
        steps: [
          Step(
            title: Text(L10n.tr(context, 'listing.add.step_photos')),
            isActive: _step >= 0,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.tr(context, 'listing.add.photos_hint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < _pickedFiles.length; i++)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _pickedFiles[i].bytes == null
                                ? Container(
                                    width: 96,
                                    height: 96,
                                    color:
                                        Theme.of(context).colorScheme.surfaceContainerHighest,
                                    child: const Icon(Icons.image_outlined),
                                  )
                                : Image.memory(
                                    _pickedFiles[i].bytes!,
                                    width: 96,
                                    height: 96,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          Positioned(
                            right: 2,
                            top: 2,
                            child: InkWell(
                              onTap: () => _removeImage(i),
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
              ],
            ),
          ),
          Step(
            title: Text(L10n.tr(context, 'listing.add.step_category')),
            isActive: _step >= 1,
            content: _loadingCategories
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _categoryLoadError != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _categoryLoadError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _loadCategories,
                            child: Text(L10n.tr(context, 'common.retry')),
                          ),
                        ],
                      )
                    : DropdownButtonFormField<String>(
                        initialValue: _categoryId,
                        decoration: InputDecoration(
                          labelText: L10n.tr(context, 'listing.add.category_label'),
                        ),
                        items: _categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c['id'],
                                child: Text(_categoryItemLabel(context, c)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          final found = _categories
                              .where((c) => c['id'] == value)
                              .toList();
                          setState(() {
                            _categoryId = value;
                            _categoryNameFr =
                                found.isNotEmpty ? found.first['name_fr'] : null;
                          });
                        },
                      ),
          ),
          Step(
            title: Text(L10n.tr(context, 'listing.add.step_details')),
            isActive: _step >= 2,
            content: Column(
              children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'listing.add.title_label'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'listing.add.description_label'),
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
              ],
            ),
          ),
          Step(
            title: Text(L10n.tr(context, 'listing.add.step_price')),
            isActive: _step >= 3,
            content: Column(
              children: [
                TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'listing.add.price_label'),
                    prefixText: 'DA ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _stockCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                    prefixText: 'DA ',
                  ),
                ),
              ],
            ),
          ),
          Step(
            title: Text(L10n.tr(context, 'listing.add.step_location')),
            isActive: _step >= 4,
            content: _loadingLocations
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _locationLoadError != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _locationLoadError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _loadLocations,
                            child: Text(L10n.tr(context, 'common.retry')),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildPickerField(
                            label: L10n.tr(context, 'listing.add.wilaya_label'),
                            value: _wilayaLabelWithPlaceholder(
                              context,
                              placeholder: L10n.tr(
                                context,
                                'listing.add.select_wilaya',
                              ),
                            ),
                            onTap: _wilayas.isEmpty
                                ? null
                                : () async {
                                    final picked = await _showLocationPicker(
                                      context: context,
                                      title: L10n.tr(
                                        context,
                                        'listing.add.wilaya_label',
                                      ),
                                      items: _wilayas,
                                      itemLabel: (w) =>
                                          '${w['code']} - ${_wilayaItemLabel(context, w)}',
                                    );
                                    if (picked != null) {
                                      _onWilayaSelected(picked['code']);
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          _buildPickerField(
                            label:
                                L10n.tr(context, 'listing.add.commune_label'),
                            value: _selectedCommuneLabelWithPlaceholder(
                              context,
                              placeholder: L10n.tr(
                                context,
                                'listing.add.select_commune',
                              ),
                            ),
                            onTap: (_selectedWilayaCode == null ||
                                    _communes.isEmpty)
                                ? null
                                : () async {
                                    final picked = await _showLocationPicker(
                                      context: context,
                                      title: L10n.tr(
                                        context,
                                        'listing.add.commune_label',
                                      ),
                                      items: _communes,
                                      itemLabel: (c) =>
                                          _communeItemLabel(context, c),
                                    );
                                    if (picked != null) {
                                      setState(
                                        () => _selectedCommune = picked['id'],
                                      );
                                    }
                                  },
                          ),
                        ],
                      ),
          ),
          Step(
            title: Text(L10n.tr(context, 'listing.add.step_delivery')),
            isActive: _step >= 5,
            content: Column(
              children: [
                  SwitchListTile(
                    value: _deliveryCod,
                    onChanged: (value) => setState(() => _deliveryCod = value),
                    title: Text(L10n.tr(context, 'listing.add.delivery_cod')),
                    subtitle:
                        Text(L10n.tr(context, 'listing.add.delivery_cod_hint')),
                  ),
                  if (_courierCaps.supportsStopdesk)
                    SwitchListTile(
                      value: _deliveryPickup,
                      onChanged: (value) =>
                          setState(() => _deliveryPickup = value),
                      title: Text(L10n.tr(context, 'listing.add.delivery_pickup')),
                      subtitle: Text(
                        L10n.tr(context, 'listing.add.delivery_pickup_hint'),
                      ),
                    ),
                ],
              ),
            ),
            Step(
              title: Text(L10n.tr(context, 'listing.add.step_shipping')),
              isActive: _step >= 6,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    value: _freeShipping,
                    onChanged: (v) => setState(() => _freeShipping = v ?? false),
                    title: Text(L10n.tr(context, 'checkout.free_shipping')),
                  ),
                  if (_courierCaps.supportsExchange)
                    CheckboxListTile(
                      value: _exchangeAfterDelivery,
                      onChanged: (v) =>
                          setState(() => _exchangeAfterDelivery = v ?? false),
                      title:
                          Text(L10n.tr(context, 'checkout.exchange_after_delivery')),
                    ),
                  if (_courierCaps.supportsStopdesk)
                    CheckboxListTile(
                      value: _allowStopdesk,
                      onChanged: (v) =>
                          setState(() => _allowStopdesk = v ?? true),
                      title: Text(L10n.tr(context, 'listing.add.allow_stopdesk')),
                    ),
                  if (_courierCaps.supportsInsurance) ...[
                    const SizedBox(height: 8),
                    Text(
                      L10n.tr(context, 'checkout.insurance'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SwitchListTile(
                      value: _insuranceActive,
                      onChanged: (v) =>
                          setState(() => _insuranceActive = v ?? false),
                      title: Text(L10n.tr(context, 'checkout.insurance_active')),
                    ),
                    TextField(
                      controller: _declaredValueCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: L10n.tr(context, 'checkout.declared_value'),
                      ),
                    ),
                  ],
                const SizedBox(height: 12),
                Text(
                  L10n.tr(context, 'checkout.dimensions_weight'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                TextField(
                  controller: _weightCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.weight_kg'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _heightCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.height_cm'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _widthCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.width_cm'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _lengthCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: L10n.tr(context, 'checkout.length_cm'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.tr(
                    context,
                    'checkout.overweight_label',
                    params: {
                      'value': (_parseDigits(_weightCtrl.text.trim()) > 5)
                          ? L10n.tr(context, 'common.yes')
                          : L10n.tr(context, 'common.no'),
                    },
                  ),
                ),
              ],
            ),
          ),
          Step(
            title: Text(L10n.tr(context, 'listing.add.step_preview')),
            isActive: _step >= 7,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titleCtrl.text.trim().isEmpty
                      ? L10n.tr(context, 'listing.add.preview_no_title')
                      : _titleCtrl.text.trim(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (_pickedFiles.isNotEmpty)
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pickedFiles.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final bytes = _pickedFiles[index].bytes;
                        if (bytes == null) {
                          return Container(
                            width: 180,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image_outlined),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(bytes, width: 180, fit: BoxFit.cover),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                _PreviewRow(
                  label: L10n.tr(context, 'listing.add.preview_category'),
                  value: _categoryLabel(context),
                ),
                _PreviewRow(
                  label: L10n.tr(context, 'listing.add.preview_condition'),
                  value: _conditionLabel(context, _condition),
                ),
                _PreviewRow(
                  label: L10n.tr(context, 'listing.add.preview_price'),
                  value: _priceCtrl.text.trim().isEmpty ? '-' : 'DA ${_priceCtrl.text.trim()}',
                ),
                _PreviewRow(
                  label: L10n.tr(context, 'listing.add.preview_stock'),
                  value: _stockCtrl.text.trim().isEmpty ? '-' : _stockCtrl.text.trim(),
                ),
                if (_costCtrl.text.trim().isNotEmpty)
                  _PreviewRow(
                    label: L10n.tr(context, 'listing.add.preview_cost'),
                    value: 'DA ${_costCtrl.text.trim()}',
                  ),
                _PreviewRow(
                  label: L10n.tr(context, 'listing.add.preview_location'),
                  value:
                      '${_wilayaLabel(context)} - ${_selectedCommuneLabel(context)}'
                          .trim(),
                ),
                _PreviewRow(
                  label: L10n.tr(context, 'listing.add.preview_delivery'),
                  value: _deliveryOptionsPreview(context).join(', '),
                ),
                  _PreviewRow(
                    label: L10n.tr(context, 'checkout.free_shipping'),
                    value: _freeShipping
                        ? L10n.tr(context, 'common.yes')
                        : L10n.tr(context, 'common.no'),
                  ),
                  if (_courierCaps.supportsExchange)
                    _PreviewRow(
                      label:
                          L10n.tr(context, 'checkout.exchange_after_delivery'),
                      value: _exchangeAfterDelivery
                          ? L10n.tr(context, 'common.yes')
                          : L10n.tr(context, 'common.no'),
                    ),
                  if (_courierCaps.supportsStopdesk)
                    _PreviewRow(
                      label: L10n.tr(context, 'listing.add.allow_stopdesk'),
                      value: _allowStopdesk
                          ? L10n.tr(context, 'common.yes')
                          : L10n.tr(context, 'common.no'),
                    ),
                  if (_courierCaps.supportsInsurance) ...[
                    _PreviewRow(
                      label: L10n.tr(context, 'checkout.insurance_active'),
                      value: _insuranceActive
                          ? L10n.tr(context, 'common.yes')
                          : L10n.tr(context, 'common.no'),
                    ),
                    _PreviewRow(
                      label: L10n.tr(context, 'checkout.declared_value'),
                      value: _declaredValueCtrl.text.trim().isEmpty
                          ? '-'
                          : _declaredValueCtrl.text.trim(),
                    ),
                  ],
                _PreviewRow(
                  label: L10n.tr(context, 'checkout.weight_kg'),
                  value: _weightCtrl.text.trim().isEmpty
                      ? '-'
                      : _weightCtrl.text.trim(),
                ),
                _PreviewRow(
                  label: L10n.tr(context, 'checkout.height_cm'),
                  value: _heightCtrl.text.trim().isEmpty
                      ? '-'
                      : _heightCtrl.text.trim(),
                ),
                _PreviewRow(
                  label: L10n.tr(context, 'checkout.width_cm'),
                  value: _widthCtrl.text.trim().isEmpty
                      ? '-'
                      : _widthCtrl.text.trim(),
                ),
                _PreviewRow(
                  label: L10n.tr(context, 'checkout.length_cm'),
                  value: _lengthCtrl.text.trim().isEmpty
                      ? '-'
                      : _lengthCtrl.text.trim(),
                ),
                const SizedBox(height: 12),
                if (_descCtrl.text.trim().isNotEmpty)
                  Text(
                    _descCtrl.text.trim(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _error == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
