import 'package:dzmarket/src/features/profile/my_listings_page.dart';
import 'package:dzmarket/src/services/category_service.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/location_data_service.dart';
import 'package:dzmarket/src/services/product_service.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/storage_service.dart';
import 'package:dzmarket/src/services/moderation_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddListingPage extends StatefulWidget {
  const AddListingPage({super.key});

  @override
  State<AddListingPage> createState() => _AddListingPageState();
}

class _AddListingPageState extends State<AddListingPage> {
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
  String? _categorySlug;
  bool _deliveryEnabled = true;
  bool _freeShipping = false;
  bool _exchangeAfterDelivery = false;
  bool _insuranceActive = false;
  bool _allowStopdesk = true;
  bool _sellerHasEnabledCouriers = true;
  CourierCapabilities _courierCaps = CourierCapabilities.all;
  CourierParcelRules _parcelRules = CourierParcelRules.generic;
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
  static const int _maxPhotos = 5;
  static const String _recentCategoriesKey = 'listing.add.recent_categories.v1';
  static const int _maxRecentCategories = 6;
  List<String> _recentCategoryIds = const [];

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
    _loadRecentCategories();
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
        _categoryLoadError = L10n.tr(
          context,
          'listing.add.error_no_categories',
        );
      }
    });
  }

  Future<void> _loadRecentCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList(_recentCategoriesKey) ?? const [];
      if (!mounted) return;
      setState(() {
        _recentCategoryIds = values
            .where((id) => id.trim().isNotEmpty)
            .take(_maxRecentCategories)
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _rememberRecentCategory(String categoryId) async {
    final safeId = categoryId.trim();
    if (safeId.isEmpty) return;
    final next = <String>[
      safeId,
      ..._recentCategoryIds.where((id) => id != safeId),
    ].take(_maxRecentCategories).toList();
    if (!mounted) return;
    setState(() => _recentCategoryIds = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentCategoriesKey, next);
    } catch (_) {}
  }

  Map<String, String>? _findCategoryById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final item in _categories) {
      if (item['id'] == id) return item;
    }
    return null;
  }

  List<Map<String, String>> _rootCategories(BuildContext context) {
    final roots = _categories
        .where((c) => (c['parent_id'] ?? '').trim().isEmpty)
        .toList();
    roots.sort(
      (a, b) => _categoryItemLabel(
        context,
        a,
      ).compareTo(_categoryItemLabel(context, b)),
    );
    return roots;
  }

  List<Map<String, String>> _childrenOfCategory(
    BuildContext context,
    String parentId,
  ) {
    final children = _categories
        .where((c) => (c['parent_id'] ?? '').trim() == parentId)
        .toList();
    children.sort(
      (a, b) => _categoryItemLabel(
        context,
        a,
      ).compareTo(_categoryItemLabel(context, b)),
    );
    return children;
  }

  String _categoryPathLabel(
    BuildContext context,
    Map<String, String> category,
  ) {
    final parentId = category['parent_id'] ?? '';
    if (parentId.isEmpty) return _categoryItemLabel(context, category);
    final parent = _findCategoryById(parentId);
    if (parent == null) return _categoryItemLabel(context, category);
    return '${_categoryItemLabel(context, parent)} > ${_categoryItemLabel(context, category)}';
  }

  Future<Map<String, String>?> _showCategoryPicker(BuildContext context) {
    final searchCtrl = TextEditingController();
    String activeParentId = '';
    final selected = _findCategoryById(_categoryId);
    if (selected != null) {
      final parentId = (selected['parent_id'] ?? '').trim();
      activeParentId = parentId.isNotEmpty ? parentId : (selected['id'] ?? '');
    }
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              final query = searchCtrl.text.trim().toLowerCase();
              final roots = _rootCategories(sheetContext);
              final activeChildren = activeParentId.isEmpty
                  ? const <Map<String, String>>[]
                  : _childrenOfCategory(sheetContext, activeParentId);
              final filtered = query.isEmpty
                  ? <Map<String, String>>[]
                  : _categories.where((item) {
                      final plain = _categoryItemLabel(
                        sheetContext,
                        item,
                      ).toLowerCase();
                      final path = _categoryPathLabel(
                        sheetContext,
                        item,
                      ).toLowerCase();
                      return plain.contains(query) || path.contains(query);
                    }).toList();
              if (query.isNotEmpty) {
                filtered.sort(
                  (a, b) => _categoryPathLabel(
                    sheetContext,
                    a,
                  ).compareTo(_categoryPathLabel(sheetContext, b)),
                );
              }
              final recentItems = _recentCategoryIds
                  .map(_findCategoryById)
                  .whereType<Map<String, String>>()
                  .toList();

              Widget buildCategoryTile(
                Map<String, String> item, {
                required bool showPath,
              }) {
                final hasChildren = _childrenOfCategory(
                  sheetContext,
                  item['id'] ?? '',
                ).isNotEmpty;
                final label = showPath
                    ? _categoryPathLabel(sheetContext, item)
                    : _categoryItemLabel(sheetContext, item);
                return ListTile(
                  title: Text(label),
                  trailing: hasChildren && query.isEmpty
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: () {
                    if (hasChildren && query.isEmpty) {
                      setSheetState(() => activeParentId = item['id'] ?? '');
                      return;
                    }
                    Navigator.of(sheetContext).pop(item);
                  },
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      L10n.tr(
                        sheetContext,
                        'listing.add.category_label',
                        fallback: 'Categorie',
                      ),
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: L10n.tr(
                          sheetContext,
                          'common.search',
                          fallback: 'Rechercher',
                        ),
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                  if (query.isEmpty &&
                      activeParentId.isNotEmpty &&
                      activeChildren.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              setSheetState(() => activeParentId = ''),
                          icon: const Icon(Icons.arrow_back),
                          label: Text(
                            L10n.tr(
                              sheetContext,
                              'listing.add.category_back_to_root',
                              fallback: 'Categories principales',
                            ),
                          ),
                        ),
                      ),
                    ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (query.isEmpty && recentItems.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                            child: Text(
                              L10n.tr(
                                sheetContext,
                                'listing.add.category_recent',
                                fallback: 'Recentes',
                              ),
                              style: Theme.of(
                                sheetContext,
                              ).textTheme.labelLarge,
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: recentItems
                                .map(
                                  (item) => ActionChip(
                                    label: Text(
                                      _categoryItemLabel(sheetContext, item),
                                    ),
                                    onPressed: () =>
                                        Navigator.of(sheetContext).pop(item),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (query.isNotEmpty)
                          ...filtered.map(
                            (item) => buildCategoryTile(item, showPath: true),
                          )
                        else if (activeParentId.isNotEmpty &&
                            activeChildren.isNotEmpty)
                          ...activeChildren.map(
                            (item) => buildCategoryTile(item, showPath: false),
                          )
                        else
                          ...roots.map(
                            (item) => buildCategoryTile(item, showPath: false),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
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
    final rows = await ShippingService().fetchEnabledCouriersForSeller(userId);
    CourierParcelRules parcelRules = CourierParcelRules.generic;
    if (rows.isNotEmpty) {
      try {
        parcelRules = await ShippingService.aggregateParcelRulesAsync(rows);
      } catch (_) {
        parcelRules = ShippingService.aggregateParcelRules(rows);
      }
    }
    if (!mounted) return;
    setState(() {
      _sellerHasEnabledCouriers = rows.isNotEmpty;
      _courierCaps = rows.isEmpty
          ? CourierCapabilities.none
          : ShippingService.aggregateCapabilities(rows);
      _parcelRules = parcelRules;
      _applyCourierCaps();
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
        decoration: InputDecoration(labelText: label, enabled: onTap != null),
        child: Row(
          children: [
            Expanded(child: Text(value)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Widget _buildParcelRulesCard(BuildContext context) {
    final chips = <Widget>[
      _buildRuleChip(
        context,
        L10n.tr(
          context,
          'checkout.parcel_limits_weight',
          params: {
            'min': _parcelRules.minWeightKg.toString(),
            'max': _parcelRules.maxWeightKg.toString(),
          },
        ),
      ),
      _buildRuleChip(
        context,
        L10n.tr(
          context,
          'checkout.parcel_limits_dimensions',
          params: {
            'h': _parcelRules.maxHeightCm.toString(),
            'w': _parcelRules.maxWidthCm.toString(),
            'l': _parcelRules.maxLengthCm.toString(),
          },
        ),
      ),
      _buildRuleChip(
        context,
        L10n.tr(
          context,
          'checkout.parcel_limits_volume',
          params: {'max': _parcelRules.maxVolumeCm3.toString()},
        ),
      ),
      _buildRuleChip(
        context,
        L10n.tr(
          context,
          'checkout.parcel_limits_overweight',
          params: {'kg': _parcelRules.overweightThresholdKg.toString()},
        ),
      ),
    ];
    if (_courierCaps.supportsInsurance) {
      chips.add(
        _buildRuleChip(
          context,
          L10n.tr(
            context,
            'checkout.parcel_limits_declared_value',
            params: {'max': _parcelRules.maxDeclaredValue.toStringAsFixed(0)},
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.tr(context, 'checkout.parcel_limits_title'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }

  Widget _buildRuleChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }

  bool _isSupportedImageFile(PlatformFile file) {
    final ext = (file.extension ?? '').trim().toLowerCase();
    if (ext.isNotEmpty) {
      return ext != 'heic' && ext != 'heif';
    }
    final name = file.name.trim().toLowerCase();
    return !name.endsWith('.heic') && !name.endsWith('.heif');
  }

  Future<void> _pickImages() async {
    final remainingSlots = _maxPhotos - _pickedFiles.length;
    if (remainingSlots <= 0) {
      _setError(
        L10n.tr(
          context,
          'listing.add.error_max_photos',
          params: {'max': _maxPhotos.toString()},
        ),
      );
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.image,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final supported = result.files.where(_isSupportedImageFile).toList();
    final unsupportedCount = result.files.length - supported.length;
    if (supported.isEmpty) {
      _setError(L10n.tr(context, 'listing.add.error_unsupported_image'));
      return;
    }
    final selected = supported.take(remainingSlots).toList();
    setState(() {
      _pickedFiles.addAll(selected);
    });
    if (unsupportedCount > 0) {
      _setError(L10n.tr(context, 'listing.add.error_unsupported_image'));
    } else if (supported.length > remainingSlots) {
      _setError(
        L10n.tr(
          context,
          'listing.add.error_max_photos',
          params: {'max': _maxPhotos.toString()},
        ),
      );
    }
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
        if (_pickedFiles.length > _maxPhotos) {
          _setError(
            L10n.tr(
              context,
              'listing.add.error_max_photos',
              params: {'max': _maxPhotos.toString()},
            ),
          );
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
        return true;
      case 6:
        final weight = _parseDigitsNullable(_weightCtrl.text.trim());
        final height = _parseDigitsNullable(_heightCtrl.text.trim());
        final width = _parseDigitsNullable(_widthCtrl.text.trim());
        final length = _parseDigitsNullable(_lengthCtrl.text.trim());
        double? declaredValue;
        if (_insuranceActive && _declaredValueCtrl.text.trim().isEmpty) {
          _setError(L10n.tr(context, 'checkout.error_price_required'));
          return false;
        }
        if (_declaredValueCtrl.text.trim().isNotEmpty) {
          try {
            declaredValue = InputSanitizer.parseAmount(
              _declaredValueCtrl.text,
              min: 0,
            );
          } on FormatException catch (e) {
            _setError(e.message);
            return false;
          }
        }
        final validation = ShippingService.validateParcel(
          rules: _parcelRules,
          weightKg: weight,
          heightCm: height,
          widthCm: width,
          lengthCm: length,
          declaredValue: declaredValue,
          insuranceActive: _insuranceActive,
        );
        if (validation != null) {
          _setError(_parcelValidationMessage(validation));
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

  String _parcelValidationMessage(CourierParcelValidation validation) {
    switch (validation.code) {
      case 'weight_range':
        return L10n.tr(
          context,
          'checkout.error_weight_range',
          params: validation.params,
        );
      case 'height_max':
        return L10n.tr(
          context,
          'checkout.error_height_max',
          params: validation.params,
          fallback: L10n.tr(context, 'checkout.error_height_invalid'),
        );
      case 'width_max':
        return L10n.tr(
          context,
          'checkout.error_width_max',
          params: validation.params,
          fallback: L10n.tr(context, 'checkout.error_width_invalid'),
        );
      case 'length_max':
        return L10n.tr(
          context,
          'checkout.error_length_max',
          params: validation.params,
          fallback: L10n.tr(context, 'checkout.error_length_invalid'),
        );
      case 'volume_max':
        return L10n.tr(
          context,
          'checkout.error_volume_max',
          params: validation.params,
          fallback: L10n.tr(context, 'checkout.error_length_invalid'),
        );
      case 'declared_value_max':
        return L10n.tr(
          context,
          'checkout.error_declared_value_max',
          params: validation.params,
          fallback: L10n.tr(context, 'checkout.error_price_required'),
        );
      default:
        return L10n.tr(context, 'common.error');
    }
  }

  String _moderationListingMessage(ModerationResult moderation) {
    final labels = (moderation.labels ?? const [])
        .map((e) => e.toLowerCase())
        .toSet();
    final hasIllegal =
        labels.contains('weapon') ||
        labels.contains('drug') ||
        labels.contains('extremism') ||
        labels.contains('content-trade') ||
        labels.contains('money-transaction');
    if (hasIllegal) {
      return L10n.tr(
        context,
        'moderation.blocked_illegal',
        fallback: 'Annonce refusee : contenu illegal detecte.',
      );
    }
    final hasViolent =
        labels.contains('gore') ||
        labels.contains('violence') ||
        labels.contains('self-harm');
    if (hasViolent) {
      return L10n.tr(
        context,
        'moderation.blocked_violent',
        fallback: 'Annonce refusee : contenu violent ou choquant detecte.',
      );
    }
    final hasOffensive =
        labels.contains('offensive') ||
        labels.contains('profanity') ||
        labels.contains('nudity_raw') ||
        labels.contains('nudity_partial');
    if (hasOffensive) {
      return L10n.tr(
        context,
        'moderation.blocked_offensive',
        fallback:
            'Annonce refusee : contenu offensant ou non conforme detecte.',
      );
    }
    if (moderation.action == 'review') {
      return L10n.tr(
        context,
        'moderation.listing_review_required',
        fallback:
            'Annonce en attente de verification manuelle (contenu sensible detecte).',
      );
    }
    return L10n.tr(
      context,
      'moderation.blocked_listing',
      fallback: 'Annonce refusee : contenu non conforme.',
    );
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

  List<int> _buildWeightOptions() {
    final min = _parcelRules.minWeightKg < 1 ? 1 : _parcelRules.minWeightKg;
    final max = _parcelRules.maxWeightKg < min ? min : _parcelRules.maxWeightKg;
    final values = <int>{};
    for (var kg = min; kg <= max; kg++) {
      if (kg <= 10 || kg % 2 == 0 || kg == max) {
        values.add(kg);
      }
    }
    return values.toList()..sort();
  }

  List<int> _buildDimensionOptions(int max) {
    final safeMax = max < 0 ? 0 : max;
    final values = <int>{};
    for (var cm = 0; cm <= safeMax; cm++) {
      if (cm <= 30 || cm % 5 == 0 || cm == safeMax) {
        values.add(cm);
      }
    }
    return values.toList()..sort();
  }

  List<int> _withCurrentValue(List<int> options, int? value) {
    if (value == null || options.contains(value)) return options;
    final merged = <int>{...options, value}.toList()..sort();
    return merged;
  }

  Widget _buildNumericDropdown({
    required String label,
    required String helperText,
    required TextEditingController controller,
    required List<int> options,
  }) {
    final currentValue = _parseDigitsNullable(controller.text.trim());
    final safeOptions = _withCurrentValue(options, currentValue);
    return DropdownButtonFormField<int>(
      initialValue: currentValue,
      decoration: InputDecoration(labelText: label, helperText: helperText),
      items: safeOptions
          .map(
            (value) => DropdownMenuItem<int>(
              value: value,
              child: Text(value.toString()),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => controller.text = value.toString());
      },
    );
  }

  bool _isLargeVolumeListing() {
    final weight = _parseDigitsNullable(_weightCtrl.text.trim()) ?? 0;
    final height = _parseDigitsNullable(_heightCtrl.text.trim()) ?? 0;
    final width = _parseDigitsNullable(_widthCtrl.text.trim()) ?? 0;
    final length = _parseDigitsNullable(_lengthCtrl.text.trim()) ?? 0;
    final volume = height * width * length;
    final text = [
      _titleCtrl.text,
      _descCtrl.text,
      _categoryNameFr,
    ].whereType<String>().join(' ').toLowerCase();
    final keywordMatch = RegExp(
      r'(voiture|moto|camion|meuble|canape|armoire|frigo|refrigerateur|lave[- ]linge|machine[- ]a[- ]laver|climatiseur|lit|table|bureau|vehicle|furniture)',
    ).hasMatch(text);
    return weight > 15 ||
        height > 120 ||
        width > 120 ||
        length > 200 ||
        volume > 900000 ||
        keywordMatch;
  }

  bool _isForcedArrangedDelivery() {
    return _isLargeVolumeListing() || !_sellerHasEnabledCouriers;
  }

  bool _usesCourierDelivery() {
    return _deliveryEnabled && !_isForcedArrangedDelivery();
  }

  List<String> _effectiveDeliveryOptions() {
    if (_isForcedArrangedDelivery()) return const ['pickup'];
    if (!_sellerHasEnabledCouriers) return const ['pickup'];
    // Keep both modes available when at least one courier is configured.
    // The seller toggle only sets preferred default order.
    if (_deliveryEnabled) return const ['cod', 'pickup'];
    return const ['pickup', 'cod'];
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
        throw FormatException(
          L10n.tr(context, 'listing.add.error_invalid_stock'),
        );
      }
      final costPrice = _costCtrl.text.trim().isEmpty
          ? null
          : InputSanitizer.parseAmount(_costCtrl.text, min: 0);
      final brand = InputSanitizer.sanitizeOptionalText(
        _brandCtrl.text,
        maxLength: 40,
      );
      final size = InputSanitizer.sanitizeOptionalText(
        _sizeCtrl.text,
        maxLength: 40,
      );
      final wilaya = InputSanitizer.sanitizeText(
        _wilayaNameOnly(context),
        maxLength: 60,
      );
      final daira = InputSanitizer.sanitizeText(
        _selectedCommuneLabel(context),
        maxLength: 60,
      );
      final categoryId = InputSanitizer.sanitizeText(
        _categoryId ?? '',
        maxLength: 20,
      );
      final categoryName = InputSanitizer.sanitizeOptionalText(
        _categoryNameFr,
        maxLength: 80,
      );
      if (title.isEmpty || categoryId.isEmpty) {
        throw FormatException(
          L10n.tr(context, 'listing.add.error_missing_info'),
        );
      }

      final bytes = _pickedFiles
          .map((f) => f.bytes)
          .whereType<Uint8List>()
          .toList();
      final names = _pickedFiles.map((f) => f.name).toList();
      if (bytes.length != _pickedFiles.length) {
        throw StateError(L10n.tr(context, 'listing.add.error_file_read'));
      }
      if (bytes.length > _maxPhotos) {
        throw FormatException(
          L10n.tr(
            context,
            'listing.add.error_max_photos',
            params: {'max': _maxPhotos.toString()},
          ),
        );
      }
      final uploaded = await StorageService().uploadImages(
        files: bytes,
        fileNames: names,
      );
      final moderation = await ModerationService().moderateListing(
        title: title,
        description: description,
        imageUrls: uploaded,
        categorySlug: _categorySlug,
        policyProfile: 'dz_strict',
      );
      if (!moderation.allowed || moderation.action == 'block') {
        await StorageService().deletePublicUrls(uploaded);
        throw FormatException(_moderationListingMessage(moderation));
      }
      final requiresReview = moderation.action == 'review';
      final deliveryOptions = _effectiveDeliveryOptions();
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
        moderationStatus: requiresReview ? 'masked' : 'approved',
        moderationReason: moderation.reason,
        moderationLabels: moderation.labels,
        moderationScore: moderation.score,
      );
      if (!mounted) return;
      if (requiresReview) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_moderationListingMessage(moderation))),
        );
      }
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
    final options = _effectiveDeliveryOptions();
    return options
        .map(
          (value) => value == 'cod'
              ? L10n.tr(context, 'listing.add.delivery_cod')
              : L10n.tr(context, 'listing.add.delivery_pickup'),
        )
        .toList();
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

  String _wilayaNameOnly(BuildContext context) {
    final code = _selectedWilayaCode;
    if (code == null || code.isEmpty) return '-';
    final match = _wilayas.where((w) => w['code'] == code).toList();
    if (match.isEmpty) return code;
    final fr = match.first['name_fr'] ?? code;
    final ar = match.first['name_ar'] ?? fr;
    return _pickLocalizedName(context, fr, ar);
  }

  String _formatWilayaLabel(String code, String name) {
    final raw = code.trim();
    if (raw.isEmpty) return name;
    final numeric = int.tryParse(raw);
    final normalized = numeric != null ? raw.padLeft(2, '0') : raw;
    return '$normalized - $name';
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
    final name = _pickLocalizedName(context, fr, ar);
    return _formatWilayaLabel(code, name);
  }

  String _wilayaItemLabel(BuildContext context, Map<String, String> item) {
    final fr = item['name_fr'] ?? '';
    final ar = item['name_ar'] ?? fr;
    final name = _pickLocalizedName(context, fr, ar);
    final code = item['code'] ?? '';
    return _formatWilayaLabel(code, name);
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
        return true;
      case 6:
        final weight = _parseDigitsNullable(_weightCtrl.text.trim());
        final height = _parseDigitsNullable(_heightCtrl.text.trim());
        final width = _parseDigitsNullable(_widthCtrl.text.trim());
        final length = _parseDigitsNullable(_lengthCtrl.text.trim());
        double? declaredValue;
        if (_insuranceActive && _declaredValueCtrl.text.trim().isEmpty) {
          return false;
        }
        if (_declaredValueCtrl.text.trim().isNotEmpty) {
          try {
            declaredValue = InputSanitizer.parseAmount(
              _declaredValueCtrl.text,
              min: 0,
            );
          } catch (_) {
            return false;
          }
        }
        final validation = ShippingService.validateParcel(
          rules: _parcelRules,
          weightKg: weight,
          heightCm: height,
          widthCm: width,
          lengthCm: length,
          declaredValue: declaredValue,
          insuranceActive: _insuranceActive,
        );
        if (validation != null) return false;
        return true;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.tr(context, 'listing.add.title'))),
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
                const SizedBox(height: 6),
                Text(
                  L10n.tr(
                    context,
                    'listing.add.photos_count',
                    params: {
                      'count': _pickedFiles.length.toString(),
                      'max': _maxPhotos.toString(),
                    },
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    L10n.tr(
                      context,
                      'listing.add.moderation_hint',
                      fallback:
                          'Controle automatique: les images illegales, violentes ou choquantes sont bloquees. Les contenus sensibles peuvent etre verifies manuellement.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
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
                      onTap: _pickedFiles.length >= _maxPhotos
                          ? null
                          : _pickImages,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Icon(
                          _pickedFiles.length >= _maxPhotos
                              ? Icons.check_circle_outline
                              : Icons.add_photo_alternate_outlined,
                          color: _pickedFiles.length >= _maxPhotos
                              ? Theme.of(context).disabledColor
                              : null,
                        ),
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
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L10n.tr(context, 'listing.add.category_label'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final picked = await _showCategoryPicker(context);
                          if (picked == null) return;
                          final pickedId = picked['id'] ?? '';
                          if (pickedId.isEmpty) return;
                          await _rememberRecentCategory(pickedId);
                          setState(() {
                            _categoryId = pickedId;
                            _categoryNameFr = picked['name_fr'];
                            _categorySlug = picked['slug'];
                          });
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.category_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _categoryLabel(context) == '-'
                                      ? L10n.tr(
                                          context,
                                          'listing.add.choose_category_cta',
                                          fallback: 'Choisir une categorie',
                                        )
                                      : _categoryLabel(context),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                      if (_recentCategoryIds.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          L10n.tr(
                            context,
                            'listing.add.category_recent',
                            fallback: 'Recentes',
                          ),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _recentCategoryIds.map((id) {
                            final item = _findCategoryById(id);
                            if (item == null) {
                              return const SizedBox.shrink();
                            }
                            return ActionChip(
                              onPressed: () {
                                setState(() {
                                  _categoryId = item['id'];
                                  _categoryNameFr = item['name_fr'];
                                  _categorySlug = item['slug'];
                                });
                              },
                              label: Text(_categoryItemLabel(context, item)),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
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
                    labelText: L10n.tr(
                      context,
                      'listing.add.description_label',
                    ),
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
                  onChanged: (value) =>
                      setState(() => _condition = value ?? 'new'),
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
                                      _wilayaItemLabel(context, w),
                                );
                                if (picked != null) {
                                  _onWilayaSelected(picked['code']);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      _buildPickerField(
                        label: L10n.tr(context, 'listing.add.commune_label'),
                        value: _selectedCommuneLabelWithPlaceholder(
                          context,
                          placeholder: L10n.tr(
                            context,
                            'listing.add.select_commune',
                          ),
                        ),
                        onTap:
                            (_selectedWilayaCode == null || _communes.isEmpty)
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
                if (_isLargeVolumeListing())
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      L10n.tr(context, 'listing.add.delivery_pickup_required'),
                    ),
                  ),
                if (!_sellerHasEnabledCouriers)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      L10n.tr(context, 'checkout.no_courier_enabled'),
                    ),
                  ),
                SwitchListTile(
                  value: _usesCourierDelivery(),
                  onChanged: _isForcedArrangedDelivery()
                      ? null
                      : (value) => setState(() => _deliveryEnabled = value),
                  title: Text(L10n.tr(context, 'listing.add.delivery_toggle')),
                  subtitle: Text(
                    L10n.tr(context, 'listing.add.delivery_toggle_hint'),
                  ),
                ),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Text(
                    _usesCourierDelivery()
                        ? L10n.tr(context, 'listing.add.delivery_auto_courier')
                        : L10n.tr(
                            context,
                            'listing.add.delivery_auto_arranged',
                          ),
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
                if (_sellerHasEnabledCouriers) _buildParcelRulesCard(context),
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
                    title: Text(
                      L10n.tr(context, 'checkout.exchange_after_delivery'),
                    ),
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
                    onChanged: (v) => setState(() => _insuranceActive = v),
                    title: Text(L10n.tr(context, 'checkout.insurance_active')),
                  ),
                  TextField(
                    controller: _declaredValueCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: L10n.tr(context, 'checkout.declared_value'),
                      helperText: L10n.tr(
                        context,
                        'checkout.declared_value_hint',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  L10n.tr(context, 'checkout.dimensions_weight'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                _buildNumericDropdown(
                  controller: _weightCtrl,
                  label: L10n.tr(context, 'checkout.weight_kg'),
                  helperText: L10n.tr(
                    context,
                    'checkout.weight_hint',
                    params: {
                      'min': _parcelRules.minWeightKg.toString(),
                      'max': _parcelRules.maxWeightKg.toString(),
                    },
                  ),
                  options: _buildWeightOptions(),
                ),
                const SizedBox(height: 8),
                _buildNumericDropdown(
                  controller: _heightCtrl,
                  label: L10n.tr(context, 'checkout.height_cm'),
                  helperText: L10n.tr(
                    context,
                    'checkout.height_hint',
                    params: {'max': _parcelRules.maxHeightCm.toString()},
                  ),
                  options: _buildDimensionOptions(_parcelRules.maxHeightCm),
                ),
                const SizedBox(height: 8),
                _buildNumericDropdown(
                  controller: _widthCtrl,
                  label: L10n.tr(context, 'checkout.width_cm'),
                  helperText: L10n.tr(
                    context,
                    'checkout.width_hint',
                    params: {'max': _parcelRules.maxWidthCm.toString()},
                  ),
                  options: _buildDimensionOptions(_parcelRules.maxWidthCm),
                ),
                const SizedBox(height: 8),
                _buildNumericDropdown(
                  controller: _lengthCtrl,
                  label: L10n.tr(context, 'checkout.length_cm'),
                  helperText: L10n.tr(
                    context,
                    'checkout.length_hint',
                    params: {'max': _parcelRules.maxLengthCm.toString()},
                  ),
                  options: _buildDimensionOptions(_parcelRules.maxLengthCm),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image_outlined),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            bytes,
                            width: 180,
                            fit: BoxFit.cover,
                          ),
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
                  value: _priceCtrl.text.trim().isEmpty
                      ? '-'
                      : 'DA ${_priceCtrl.text.trim()}',
                ),
                _PreviewRow(
                  label: L10n.tr(context, 'listing.add.preview_stock'),
                  value: _stockCtrl.text.trim().isEmpty
                      ? '-'
                      : _stockCtrl.text.trim(),
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
                    label: L10n.tr(context, 'checkout.exchange_after_delivery'),
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
