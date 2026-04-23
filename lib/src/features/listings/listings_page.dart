// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/listings/add_listing_page.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/app_error_service.dart';
import 'package:dzmarket/src/services/category_service.dart';
import 'package:dzmarket/src/services/connectivity_service.dart';
import 'package:dzmarket/src/services/favorite_service.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/network_preferences_service.dart';
import 'package:dzmarket/src/services/product_service.dart';
import 'package:dzmarket/src/services/saved_search_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/widgets/refresh_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class ListingsPage extends StatefulWidget {
  const ListingsPage({super.key});

  @override
  State<ListingsPage> createState() => _ListingsPageState();
}

class _ListingsPageState extends State<ListingsPage> {
  static const Duration _initialLoadTimeout = Duration(seconds: 18);
  static const Duration _retryLoadTimeout = Duration(seconds: 22);
  static const int _maxInitialLoadAttempts = 2;
  final _searchController = TextEditingController();
  final _priceMin = TextEditingController();
  final _priceMax = TextEditingController();
  final _brand = TextEditingController();
  final _size = TextEditingController();
  final _color = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;
  String _condition = 'any';
  String _category = 'any';
  String _sort = 'newest';
  bool _showFavoritesOnly = false;
  bool _nearbyOnly = false;
  bool _quickNewOnly = false;
  bool _quickDeliveryOnly = false;
  String? _buyerWilaya;
  List<Product> _products = const [];
  bool _loading = false;
  bool _initialLoad = true;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 30;
  String? _activeQueryKey;
  String? _loadError;
  bool _loadErrorOffline = false;
  String? _lastLoggedLoadError;
  int _savedSearchesRefreshTick = 0;

  List<Map<String, String>> _categories = const [
    {'id': 'any'},
  ];
  final _conditions = ['any', 'new', 'like new', 'good', 'fair'];
  final RefreshController _refreshController = RefreshController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadBuyerWilaya();
    _refresh();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadBuyerWilaya() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final profile = await supabase
          .from('profiles')
          .select('wilaya')
          .eq('id', userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _buyerWilaya = profile?['wilaya']?.toString());
    } catch (_) {}
  }

  Future<void> _loadCategories() async {
    List<Map<String, String>> data = const [];
    try {
      data = await CategoryService().fetchCategories();
    } catch (error, stackTrace) {
      _logLoadError(error, stackTrace, contextTag: 'listings.load_categories');
    }
    if (!mounted) return;
    setState(() {
      _categories = [
        {'id': 'any'},
        ...data,
      ];
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _priceMin.dispose();
    _priceMax.dispose();
    _brand.dispose();
    _size.dispose();
    _color.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;
    final currency = NumberFormat.currency(
      locale: localeCode == 'ar' ? 'ar_DZ' : 'fr_DZ',
      symbol: 'DA',
    );
    final userId = supabase.auth.currentUser?.id;
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = switch (screenWidth) {
      >= 1500 => 5,
      >= 1180 => 4,
      >= 820 => 3,
      _ => 2,
    };
    final gridAspectRatio = switch (crossAxisCount) {
      >= 4 => 0.83,
      3 => 0.79,
      _ => screenWidth >= 600 ? 0.75 : 0.6,
    };

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _SearchBar(
            controller: _searchController,
            onChanged: _onSearchChanged,
          ),
        ),
        actions: [
          if (userId != null)
            _FavoritesBadge(
              countStream: FavoriteService().streamFavorites(userId),
              enabled: _showFavoritesOnly,
              onPressed: () =>
                  setState(() => _showFavoritesOnly = !_showFavoritesOnly),
            ),
        ],
      ),
      body: Column(
        children: [
          if (userId != null)
            _SavedSearchesRow(
              userId: userId,
              clearFilters: _clearFilters,
              openSavedFilters: _openSavedFiltersSheet,
              saveSearch: _saveSearch,
              canSave: _canSaveCurrentSearch(),
              refreshTick: _savedSearchesRefreshTick,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterPill(
                    icon: Icons.tune,
                    label: _allFiltersLabel(context),
                    onPressed: () => _showFilters(context),
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: _category == 'any'
                        ? L10n.tr(context, 'listing.filters.all_categories')
                        : _categoryLabel(
                            context,
                            _categories.firstWhere(
                              (c) => c['id'] == _category,
                              orElse: () => {'id': _category},
                            ),
                          ),
                    onPressed: () => _openCategoryQuick(context),
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: _formatPriceQuickLabel(context),
                    onPressed: () => _openPriceQuick(context),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(L10n.tr(context, 'listing.filters.nearby')),
                    selected: _nearbyOnly,
                    onSelected: (value) {
                      if (_buyerWilaya == null || _buyerWilaya!.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              L10n.tr(
                                context,
                                'listing.filters.nearby_unavailable',
                              ),
                            ),
                          ),
                        );
                        return;
                      }
                      setState(() => _nearbyOnly = value);
                      _refresh();
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    selected: _quickNewOnly,
                    label: Text(
                      L10n.tr(context, 'listing.quick.new', fallback: 'Neuf'),
                    ),
                    onSelected: (value) {
                      setState(() => _quickNewOnly = value);
                      _refresh();
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    selected: _quickDeliveryOnly,
                    label: Text(
                      L10n.tr(
                        context,
                        'listing.quick.delivery',
                        fallback: 'Livraison',
                      ),
                    ),
                    onSelected: (value) {
                      setState(() => _quickDeliveryOnly = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: ConnectivityService.instance.isOnline,
            builder: (context, isOnline, _) {
              if (isOnline && !_loading && _products.isNotEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Row(
                  children: [
                    if (!isOnline)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              L10n.tr(
                                context,
                                'common.offline_chip',
                                fallback: 'Hors ligne',
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    if (!isOnline)
                      TextButton(
                        onPressed: _refresh,
                        child: Text(L10n.tr(context, 'common.retry')),
                      ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<Set<String>>(
              stream: userId != null
                  ? FavoriteService().streamFavorites(userId)
                  : const Stream.empty(),
              builder: (context, favSnapshot) {
                final favorites = favSnapshot.data ?? const <String>{};
                return RefreshIndicator(
                  onRefresh: () => _refreshController.run(context, _refresh),
                  child: _buildProductsGrid(
                    favorites,
                    userId,
                    currency,
                    crossAxisCount,
                    gridAspectRatio,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddListing(context),
        label: Text(L10n.tr(context, 'listing.sell')),
        icon: const Icon(Icons.add),
      ),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  String _safeSearch() =>
      InputSanitizer.sanitizeSearchQuery(_searchController.text);

  String _safeCondition() =>
      InputSanitizer.sanitizeText(_condition, maxLength: 20);

  String _safeCategory() =>
      InputSanitizer.sanitizeText(_category, maxLength: 40);

  String _safeBrand() =>
      InputSanitizer.sanitizeText(_brand.text, maxLength: 40);

  String _safeSize() => InputSanitizer.sanitizeText(_size.text, maxLength: 40);

  String _safeColor() =>
      InputSanitizer.sanitizeText(_color.text, maxLength: 40);

  double? _safeMinPrice() => double.tryParse(
    InputSanitizer.sanitizeText(_priceMin.text, maxLength: 16),
  );

  double? _safeMaxPrice() => double.tryParse(
    InputSanitizer.sanitizeText(_priceMax.text, maxLength: 16),
  );

  String _effectiveCondition() {
    if (_quickNewOnly) return 'new';
    return _safeCondition();
  }

  double? _effectiveMinPrice() => _safeMinPrice();

  double? _effectiveMaxPrice() => _safeMaxPrice();

  String _queryKey() {
    final userId = supabase.auth.currentUser?.id ?? '';
    return [
      _safeSearch().toLowerCase(),
      _effectiveCondition(),
      _safeCategory(),
      _effectiveMinPrice()?.toString() ?? '',
      _effectiveMaxPrice()?.toString() ?? '',
      _safeBrand(),
      _safeSize(),
      _safeColor(),
      _nearbyOnly ? (_buyerWilaya ?? '') : '',
      _sort,
      _quickDeliveryOnly ? 'delivery_only' : '',
      userId,
    ].join('|');
  }

  Future<void> _refresh({int attempt = 1}) async {
    final key = _queryKey();
    _activeQueryKey = key;
    final min = _effectiveMinPrice();
    final max = _effectiveMaxPrice();
    final previousProducts = _products;
    final wasEmpty = previousProducts.isEmpty;
    setState(() {
      _loading = true;
      _initialLoad = wasEmpty;
      _page = 0;
      _hasMore = true;
      _loadError = null;
      _loadErrorOffline = false;
    });

    List<Product> results = const [];
    var failed = false;
    var offline = false;
    var timedOut = false;
    try {
      results = await ProductService()
          .fetchProducts(
            search: _safeSearch(),
            categoryId: _safeCategory(),
            condition: _effectiveCondition(),
            minPrice: min,
            maxPrice: max,
            brand: _safeBrand(),
            size: _safeSize(),
            color: _safeColor(),
            nearbyWilaya: _nearbyOnly ? _buyerWilaya : null,
            sort: _sort,
            limit: _pageSize,
            offset: 0,
            excludeOwner: true,
          )
          .timeout(
            attempt >= _maxInitialLoadAttempts
                ? _retryLoadTimeout
                : _initialLoadTimeout,
          );
    } on TimeoutException {
      failed = true;
      timedOut = true;
      offline = !ConnectivityService.instance.isOnline.value;
    } catch (error, stackTrace) {
      failed = true;
      offline = _looksOfflineError(error);
      _logLoadError(error, stackTrace);
    }

    if (!mounted || _activeQueryKey != key) return;
    if (failed &&
        wasEmpty &&
        !offline &&
        attempt < _maxInitialLoadAttempts) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted || _activeQueryKey != key) return;
      return _refresh(attempt: attempt + 1);
    }
    if (failed) {
      final friendlyMessage = timedOut
          ? L10n.tr(context, 'common.refresh_timeout')
          : L10n.tr(
              context,
              offline ? 'common.offline_action' : 'listing.load_error_friendly',
              fallback: L10n.tr(context, 'common.offline_action'),
            );
      if (!wasEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyMessage)));
      }
      setState(() {
        _products = previousProducts;
        _loading = false;
        _initialLoad = false;
        _hasMore = previousProducts.length == _pageSize;
        _loadError = wasEmpty ? friendlyMessage : null;
        _loadErrorOffline = offline;
      });
      return;
    }

    setState(() {
      _products = results;
      _loading = false;
      _initialLoad = false;
      _hasMore = results.length == _pageSize;
      _page = 1;
      _loadError = null;
      _loadErrorOffline = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final key = _activeQueryKey ?? _queryKey();
    final min = _effectiveMinPrice();
    final max = _effectiveMaxPrice();
    setState(() => _loading = true);

    List<Product> results = const [];
    try {
      results = await ProductService()
          .fetchProducts(
            search: _safeSearch(),
            categoryId: _safeCategory(),
            condition: _effectiveCondition(),
            minPrice: min,
            maxPrice: max,
            brand: _safeBrand(),
            size: _safeSize(),
            color: _safeColor(),
            nearbyWilaya: _nearbyOnly ? _buyerWilaya : null,
            sort: _sort,
            limit: _pageSize,
            offset: _page * _pageSize,
            excludeOwner: true,
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}

    if (!mounted || _activeQueryKey != key) return;
    setState(() {
      _products = [..._products, ...results];
      _loading = false;
      if (results.length < _pageSize) {
        _hasMore = false;
      } else {
        _page += 1;
      }
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _refresh);
  }

  bool _looksOfflineError(Object? error) {
    final msg = error?.toString().toLowerCase() ?? '';
    if (msg.isEmpty) return !ConnectivityService.instance.isOnline.value;
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('dns') ||
        msg.contains('network') ||
        msg.contains('connection closed') ||
        msg.contains('timed out') ||
        msg.contains('clientexception') ||
        msg.contains('no address associated with hostname');
  }

  void _logLoadError(
    Object error,
    StackTrace? stackTrace, {
    String contextTag = 'listings.refresh',
  }) {
    final signature = '$contextTag|${error.toString()}';
    if (_lastLoggedLoadError == signature) return;
    _lastLoggedLoadError = signature;
    unawaited(
      AppErrorService.instance.logError(error, stackTrace, context: contextTag),
    );
  }

  Widget _buildProductsGrid(
    Set<String> favorites,
    String? userId,
    NumberFormat currency,
    int crossAxisCount,
    double childAspectRatio,
  ) {
    final showSkeleton = _initialLoad && _loading;
    final filtered = _applyClientFilters(_products, favorites);
    if (showSkeleton) {
      return const _GridSkeleton();
    }
    if (filtered.isEmpty) {
      if (_loadError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _loadErrorOffline
                      ? Icons.wifi_off_rounded
                      : Icons.error_outline,
                  size: 28,
                ),
                const SizedBox(height: 10),
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _refresh,
                  child: Text(L10n.tr(context, 'common.retry')),
                ),
              ],
            ),
          ),
        );
      }
      return _BrowseEmptyState(onReset: _clearFilters, onRetry: _refresh);
    }
    final showLoader = _loading && _products.isNotEmpty;
    final itemCount = filtered.length + (showLoader ? 1 : 0);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        controller: _scrollController,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= filtered.length) {
            return const _GridLoader();
          }
          final product = filtered[index];
          final isFav = favorites.contains(product.id);
          return _ProductCard(
            product: product,
            currency: currency,
            isFavorite: isFav,
            onFavoriteToggle: userId == null
                ? null
                : (currentIsFavorite) => FavoriteService().toggleFavorite(
                    productId: product.id,
                    isFav: currentIsFavorite,
                  ),
          );
        },
      ),
    );
  }

  List<Product> _applyClientFilters(
    List<Product> products,
    Set<String> favorites,
  ) {
    return products.where((p) {
      if (_showFavoritesOnly && !favorites.contains(p.id)) return false;
      if (_quickDeliveryOnly && !p.deliveryOptions.contains('cod')) {
        return false;
      }
      return true;
    }).toList();
  }

  String _conditionLabel(BuildContext context, String value) {
    switch (value) {
      case 'any':
        return L10n.tr(context, 'condition.any');
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

  String _categoryLabel(BuildContext context, Map<String, String> category) {
    if (category.isEmpty) return '-';
    final slug = category['slug'] ?? '';
    final fr = category['name_fr'] ?? category['name'] ?? '';
    final ar = category['name_ar'] ?? fr;
    final locale = Localizations.localeOf(context).languageCode;
    var fallback = locale == 'ar'
        ? (_hasArabicLetters(ar) ? ar : (fr.isNotEmpty ? fr : ar))
        : (fr.isNotEmpty ? fr : ar);
    if (_looksMojibake(fallback) || fallback.trim().isEmpty) {
      fallback = _humanizeSlug(slug);
    }
    if (slug.isEmpty) return fallback;
    final translated = L10n.tr(context, 'category.$slug', fallback: fallback);
    return _looksMojibake(translated) ? fallback : translated;
  }

  bool _looksKeyLikeToken(String value) {
    final normalized = value
        .replaceAll(
          RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'),
          '',
        )
        .trim()
        .toLowerCase();
    return RegExp(r'^[a-z0-9_-]+(?:\.[a-z0-9_-]+)+$').hasMatch(normalized);
  }

  bool _hasArabicLetters(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }

  bool _looksMojibake(String value) {
    if (value.isEmpty) return false;
    if (_looksKeyLikeToken(value)) return true;
    if (value.contains('\uFFFD') || value.contains('�')) return true;
    if (value.contains('Ã') ||
        value.contains('Â') ||
        value.contains('\u00C3') ||
        value.contains('\u00C2')) {
      return true;
    }
    if (RegExp(r'[A-Za-z]\?[A-Za-z]').hasMatch(value)) return true;
    return false;
  }

  String _humanizeSlug(String slug) {
    final normalized = slug.trim().toLowerCase();
    if (normalized.isEmpty) return '-';
    final words = normalized
        .replaceAll('_', '-')
        .split('-')
        .where((part) => part.isNotEmpty)
        .toList();
    if (words.isEmpty) return '-';
    return words
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.length > 1 ? word.substring(1) : ''}',
        )
        .join(' ');
  }

  void _applySavedSearch(SavedSearch saved) {
    final f = saved.filters;
    setState(() {
      _searchController.text = saved.query ?? f['q']?.toString() ?? '';
      _condition = (f['condition'] as String?) ?? 'any';
      _category = (f['category'] as String?) ?? 'any';
      _priceMin.text = f['priceMin']?.toString() ?? '';
      _priceMax.text = f['priceMax']?.toString() ?? '';
      _brand.text = f['brand']?.toString() ?? '';
      _size.text = f['size']?.toString() ?? '';
      _color.text = f['color']?.toString() ?? '';
      _sort = (f['sort'] as String?) ?? 'newest';
      _showFavoritesOnly = (f['favoritesOnly'] as bool?) ?? false;
      _nearbyOnly = (f['nearbyOnly'] as bool?) ?? false;
      _quickNewOnly = (f['quickNewOnly'] as bool?) ?? false;
      _quickDeliveryOnly = (f['quickDeliveryOnly'] as bool?) ?? false;
    });
    _refresh();
  }

  Map<String, dynamic> _currentFilters() {
    return {
      'q': _safeSearch(),
      'condition': _safeCondition(),
      'category': _safeCategory(),
      'priceMin': _safeMinPrice()?.toString() ?? '',
      'priceMax': _safeMaxPrice()?.toString() ?? '',
      'brand': _safeBrand(),
      'size': _safeSize(),
      'color': _safeColor(),
      'sort': _sort,
      'favoritesOnly': _showFavoritesOnly,
      'nearbyOnly': _nearbyOnly,
      'quickNewOnly': _quickNewOnly,
      'quickDeliveryOnly': _quickDeliveryOnly,
    };
  }

  bool _canSaveCurrentSearch() {
    if (_safeSearch().isNotEmpty) return true;
    return _hasActiveFilters();
  }

  Future<void> _saveSearch() async {
    final nameController = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.tr(context, 'saved_search.title')),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: L10n.tr(context, 'saved_search.name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L10n.tr(context, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text(L10n.tr(context, 'common.save')),
          ),
        ],
      ),
    );
    if (saved == null || saved.isEmpty) return;
    final safeName = InputSanitizer.sanitizeText(saved, maxLength: 60);
    await SavedSearchService().saveSearch(
      name: safeName,
      query: _safeSearch(),
      filters: _currentFilters(),
    );
    if (!mounted) return;
    setState(() => _savedSearchesRefreshTick++);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.tr(context, 'saved_search.saved'))),
    );
  }

  Future<void> _showFilters(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void updateFilters(VoidCallback fn) {
              setState(fn);
              setModalState(fn);
            }

            void resetLocal() {
              updateFilters(() {
                _condition = 'any';
                _category = 'any';
                _priceMin.clear();
                _priceMax.clear();
                _brand.clear();
                _size.clear();
                _color.clear();
                _sort = 'newest';
                _showFavoritesOnly = false;
                _nearbyOnly = false;
                _quickNewOnly = false;
                _quickDeliveryOnly = false;
              });
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  left: 16,
                  right: 16,
                  top: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          L10n.tr(context, 'listing.filters.title'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: resetLocal,
                          child: Text(L10n.tr(context, 'common.reset')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L10n.tr(context, 'listing.add.condition_label'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _conditions
                          .map(
                            (c) => ChoiceChip(
                              label: Text(_conditionLabel(context, c)),
                              selected: _condition == c,
                              onSelected: (_) =>
                                  updateFilters(() => _condition = c),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      L10n.tr(context, 'listing.filters.category_quick'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _categories
                          .map(
                            (c) => ChoiceChip(
                              label: Text(
                                c['id'] == 'any'
                                    ? L10n.tr(
                                        context,
                                        'listing.filters.all_categories',
                                      )
                                    : _categoryLabel(context, c),
                              ),
                              selected: _category == c['id'],
                              onSelected: (_) => updateFilters(
                                () => _category = c['id'] ?? 'any',
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      L10n.tr(context, 'listing.filters.price_quick'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _priceMin,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: L10n.tr(
                                context,
                                'listing.filters.min_price',
                              ),
                            ),
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _priceMax,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: L10n.tr(
                                context,
                                'listing.filters.max_price',
                              ),
                            ),
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _sort,
                      decoration: InputDecoration(
                        labelText: L10n.tr(context, 'listing.filters.sort'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'newest',
                          child: Text(L10n.tr(context, 'listing.sort.newest')),
                        ),
                        DropdownMenuItem(
                          value: 'price_low',
                          child: Text(
                            L10n.tr(context, 'listing.sort.price_low'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'price_high',
                          child: Text(
                            L10n.tr(context, 'listing.sort.price_high'),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        updateFilters(() => _sort = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: _nearbyOnly,
                      onChanged: (value) {
                        if (_buyerWilaya == null || _buyerWilaya!.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                L10n.tr(
                                  context,
                                  'listing.filters.nearby_unavailable',
                                ),
                              ),
                            ),
                          );
                          return;
                        }
                        updateFilters(() => _nearbyOnly = value);
                      },
                      title: Text(L10n.tr(context, 'listing.filters.nearby')),
                      subtitle: Text(
                        L10n.tr(
                          context,
                          'listing.filters.nearby_hint',
                          params: {'wilaya': _buyerWilaya ?? '-'},
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        L10n.tr(context, 'listing.filters.more'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      children: [
                        TextField(
                          controller: _brand,
                          decoration: InputDecoration(
                            labelText: L10n.tr(
                              context,
                              'listing.filters.brand',
                            ),
                          ),
                          onChanged: (_) => setModalState(() {}),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _size,
                          decoration: InputDecoration(
                            labelText: L10n.tr(context, 'listing.filters.size'),
                          ),
                          onChanged: (_) => setModalState(() {}),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _color,
                          decoration: InputDecoration(
                            labelText: L10n.tr(
                              context,
                              'listing.filters.color',
                            ),
                          ),
                          onChanged: (_) => setModalState(() {}),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: resetLocal,
                            child: Text(L10n.tr(context, 'common.reset')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _refresh();
                            },
                            child: Text(
                              L10n.tr(context, 'listing.filters.show_results'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _deleteSavedSearch(SavedSearch saved) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.tr(context, 'saved_search.delete')),
        content: Text(
          L10n.tr(
            context,
            'saved_search.delete_confirm',
            params: {'name': saved.name},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.tr(context, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.tr(context, 'common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await SavedSearchService().deleteSearch(saved.id);
    if (!mounted) return false;
    setState(() => _savedSearchesRefreshTick++);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.tr(context, 'saved_search.deleted'))),
    );
    return true;
  }

  Future<void> _openSavedFiltersSheet() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    var sheetRefreshTick = _savedSearchesRefreshTick;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: FutureBuilder<List<SavedSearch>>(
                key: ValueKey('saved-filters-$sheetRefreshTick'),
                future: SavedSearchService().fetchSavedSearches(userId),
                builder: (context, snapshot) {
                  final saved = snapshot.data ?? const <SavedSearch>[];
                  final loading =
                      snapshot.connectionState == ConnectionState.waiting &&
                      snapshot.data == null;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(
                          children: [
                            Text(
                              L10n.tr(
                                context,
                                'saved_search.my_filters',
                                fallback: 'Mes filtres',
                              ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            if (_canSaveCurrentSearch())
                              TextButton.icon(
                                onPressed: () async {
                                  Navigator.of(sheetContext).pop();
                                  await _saveSearch();
                                },
                                icon: const Icon(Icons.bookmark_add_outlined),
                                label: Text(L10n.tr(context, 'common.save')),
                              ),
                          ],
                        ),
                      ),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 20),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (snapshot.hasError)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          child: TextButton(
                            onPressed: () {
                              setSheetState(() => sheetRefreshTick++);
                            },
                            child: Text(
                              L10n.tr(
                                context,
                                'common.retry',
                                fallback: 'Reessayer',
                              ),
                            ),
                          ),
                        )
                      else if (saved.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          child: Text(
                            L10n.tr(
                              context,
                              'saved_search.empty',
                              fallback: 'Aucun filtre enregistre.',
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: saved.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final s = saved[index];
                              return ListTile(
                                leading: const Icon(Icons.bookmark_outline),
                                title: Text(s.name),
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  _applySavedSearch(s);
                                },
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final deleted = await _deleteSavedSearch(s);
                                    if (deleted) {
                                      setSheetState(() => sheetRefreshTick++);
                                    }
                                  },
                                ),
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
      },
    );
  }

  String _formatPriceQuickLabel(BuildContext context) {
    final min = _safeMinPrice();
    final max = _safeMaxPrice();
    if (min == null && max == null) {
      return L10n.tr(context, 'listing.filters.price_quick');
    }
    if (min != null && max != null) {
      return '${min.toStringAsFixed(0)}–${max.toStringAsFixed(0)} DA';
    }
    if (min != null) {
      return '${L10n.tr(context, 'listing.filters.min_price')}: ${min.toStringAsFixed(0)}';
    }
    return '${L10n.tr(context, 'listing.filters.max_price')}: ${max!.toStringAsFixed(0)}';
  }

  int _activeFilterCount() {
    var count = 0;
    if (_quickNewOnly) {
      count++;
    } else if (_safeCondition() != 'any') {
      count++;
    }
    if (_safeCategory() != 'any') count++;
    if (_safeMinPrice() != null || _safeMaxPrice() != null) count++;
    if (_safeBrand().isNotEmpty) count++;
    if (_safeSize().isNotEmpty) count++;
    if (_safeColor().isNotEmpty) count++;
    if (_sort != 'newest') count++;
    if (_nearbyOnly) count++;
    if (_showFavoritesOnly) count++;
    if (_quickDeliveryOnly) count++;
    return count;
  }

  bool _hasActiveFilters() => _activeFilterCount() > 0;

  String _allFiltersLabel(BuildContext context) {
    final base = L10n.tr(context, 'listing.filters.all_filters');
    final count = _activeFilterCount();
    return count > 0 ? '$base ($count)' : base;
  }

  Future<void> _openCategoryQuick(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                L10n.tr(context, 'listing.filters.category_quick'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories
                    .map(
                      (c) => ChoiceChip(
                        label: Text(
                          c['id'] == 'any'
                              ? L10n.tr(
                                  context,
                                  'listing.filters.all_categories',
                                )
                              : _categoryLabel(context, c),
                        ),
                        selected: _category == c['id'],
                        onSelected: (_) {
                          setState(() => _category = c['id'] ?? 'any');
                          Navigator.pop(context);
                          _refresh();
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPriceQuick(BuildContext context) async {
    final minCtrl = TextEditingController(text: _priceMin.text);
    final maxCtrl = TextEditingController(text: _priceMax.text);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.tr(context, 'listing.filters.price_quick'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: L10n.tr(
                            context,
                            'listing.filters.min_price',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: maxCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: L10n.tr(
                            context,
                            'listing.filters.max_price',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(L10n.tr(context, 'common.cancel')),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(L10n.tr(context, 'common.confirm')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed == true) {
      setState(() {
        _priceMin.text = minCtrl.text;
        _priceMax.text = maxCtrl.text;
      });
      _refresh();
    }
  }

  void _clearFilters() {
    setState(() {
      _condition = 'any';
      _category = 'any';
      _priceMin.clear();
      _priceMax.clear();
      _brand.clear();
      _size.clear();
      _color.clear();
      _sort = 'newest';
      _showFavoritesOnly = false;
      _nearbyOnly = false;
      _quickNewOnly = false;
      _quickDeliveryOnly = false;
    });
    _refresh();
  }

  Future<void> _openAddListing(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AddListingPage()));
  }
}

class _SavedSearchesRow extends StatelessWidget {
  const _SavedSearchesRow({
    required this.userId,
    required this.clearFilters,
    required this.openSavedFilters,
    required this.saveSearch,
    required this.canSave,
    required this.refreshTick,
  });

  final String userId;
  final VoidCallback clearFilters;
  final VoidCallback openSavedFilters;
  final VoidCallback saveSearch;
  final bool canSave;
  final int refreshTick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          TextButton(
            onPressed: clearFilters,
            child: Text(L10n.tr(context, 'common.reset')),
          ),
          const SizedBox(width: 2),
          FutureBuilder<List<SavedSearch>>(
            key: ValueKey('saved-searches-count-$refreshTick'),
            future: SavedSearchService().fetchSavedSearches(userId),
            builder: (context, snapshot) {
              final count = (snapshot.data ?? const <SavedSearch>[]).length;
              final label = count > 0
                  ? '${L10n.tr(context, 'saved_search.my_filters', fallback: 'Mes filtres')} ($count)'
                  : L10n.tr(
                      context,
                      'saved_search.my_filters',
                      fallback: 'Mes filtres',
                    );
              return TextButton.icon(
                onPressed: openSavedFilters,
                icon: const Icon(Icons.bookmark_outline),
                label: Text(label),
              );
            },
          ),
          if (canSave) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: saveSearch,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(L10n.tr(context, 'common.save')),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  const _ProductCard({
    required this.product,
    required this.currency,
    required this.isFavorite,
    required this.onFavoriteToggle,
  });

  final Product product;
  final NumberFormat currency;
  final bool isFavorite;
  final Future<void> Function(bool currentIsFavorite)? onFavoriteToggle;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hovered = false;
  bool? _favoriteOverride;
  bool _favoriteBusy = false;

  @override
  void didUpdateWidget(covariant _ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      _favoriteOverride = null;
      _favoriteBusy = false;
      return;
    }
    if (_favoriteOverride != null && widget.isFavorite == _favoriteOverride) {
      _favoriteOverride = null;
    }
  }

  Future<void> _handleFavoriteToggle() async {
    final callback = widget.onFavoriteToggle;
    if (callback == null || _favoriteBusy) return;
    final currentIsFavorite = _favoriteOverride ?? widget.isFavorite;
    final nextIsFavorite = !currentIsFavorite;
    setState(() {
      _favoriteBusy = true;
      _favoriteOverride = nextIsFavorite;
    });
    try {
      await callback(currentIsFavorite);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _favoriteOverride = currentIsFavorite;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.tr(
              context,
              'common.error',
              fallback: 'Une erreur est survenue.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _favoriteBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const fallbackImage =
        'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=900&q=80';
    final displayableImages = widget.product.displayableImageUrls(
      fallback: fallbackImage,
    );
    final imagePrefs = NetworkPreferencesService.instance;
    final theme = Theme.of(context);
    final metadataStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );
    final isCompactCard = MediaQuery.of(context).size.width < 430;
    final badges = <Widget>[
      if (widget.product.deliveryOptions.contains('cod'))
        _CardMiniBadge(
          icon: Icons.local_shipping_outlined,
          label: L10n.tr(
            context,
            'listing.quick.delivery',
            fallback: 'Livraison',
          ),
        ),
      if (widget.product.deliveryOptions.contains('pickup'))
        _CardMiniBadge(
          icon: Icons.handshake_outlined,
          label: L10n.tr(context, 'listing.detail.delivery_pickup'),
        ),
      if (widget.product.isNegotiable)
        _CardMiniBadge(
          icon: Icons.sell_outlined,
          label: L10n.tr(
            context,
            'listing.negotiable',
            fallback: 'Prix negociable',
          ),
        ),
    ];
    final visibleBadges = badges.take(isCompactCard ? 1 : 2).toList();
    final hiddenBadgesCount = badges.length - visibleBadges.length;
    final isDesktopCard = MediaQuery.of(context).size.width >= 900;
    final displayIsFavorite = _favoriteOverride ?? widget.isFavorite;

    return MouseRegion(
      onEnter: (_) {
        if (kIsWeb) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (kIsWeb) setState(() => _hovered = false);
      },
      child: AnimatedScale(
        scale: _hovered ? 1.012 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _hovered
                  ? theme.colorScheme.primary.withValues(alpha: 0.18)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.11 : 0.06),
                blurRadius: _hovered ? 26 : 16,
                offset: Offset(0, _hovered ? 12 : 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.go('/product/${widget.product.id}'),
              borderRadius: BorderRadius.circular(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: isDesktopCard ? 12 : 11,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(22),
                        topRight: Radius.circular(22),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _ListingCardImage(
                              imageUrls: displayableImages,
                              imagePrefs: imagePrefs,
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(
                                  alpha: 0.94,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                widget.currency.format(widget.product.price),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: widget.onFavoriteToggle == null
                                      ? null
                                      : _handleFavoriteToggle,
                                  icon: Icon(
                                    displayIsFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: displayIsFavorite
                                        ? Colors.white
                                        : theme.colorScheme.onSurface,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: displayIsFavorite
                                        ? Colors.redAccent.withValues(
                                            alpha: 0.96,
                                          )
                                        : theme.colorScheme.surface.withValues(
                                            alpha: 0.94,
                                          ),
                                  ),
                                ),
                                if (widget.product.imageUrls.length > 1) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.52),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${widget.product.imageUrls.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (widget.product.condition != null &&
                              widget.product.condition!.isNotEmpty)
                            Positioned(
                              left: 10,
                              bottom: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.62),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  widget.product.condition!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: isDesktopCard ? 8 : 9,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.product.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                          if (widget.product.brand != null &&
                              widget.product.brand!.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              widget.product.size != null &&
                                      widget.product.size!.trim().isNotEmpty
                                  ? '${widget.product.brand} • ${widget.product.size}'
                                  : widget.product.brand!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: metadataStyle,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 15,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.product.locationWilaya ??
                                      L10n.tr(
                                        context,
                                        'listing.location_unknown',
                                        fallback: 'Localisation inconnue',
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: metadataStyle,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ...visibleBadges,
                              if (hiddenBadgesCount > 0)
                                _CardMiniBadge(
                                  icon: Icons.add_circle_outline,
                                  label: '+$hiddenBadgesCount',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardMiniBadge extends StatelessWidget {
  const _CardMiniBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingCardImage extends StatefulWidget {
  const _ListingCardImage({
    required this.imageUrls,
    required this.imagePrefs,
  });

  final List<String> imageUrls;
  final NetworkPreferencesService imagePrefs;

  @override
  State<_ListingCardImage> createState() => _ListingCardImageState();
}

class _ListingCardImageState extends State<_ListingCardImage> {
  int _imageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = widget.imageUrls.isNotEmpty;
    if (!hasImage) {
      return _ListingImageFallback(theme: theme);
    }

    final currentUrl = widget.imageUrls[_imageIndex];
    return CachedNetworkImage(
      key: ValueKey(currentUrl),
      imageUrl: currentUrl,
      fit: BoxFit.cover,
      memCacheWidth: widget.imagePrefs.listImageMemCacheWidth,
      fadeInDuration: widget.imagePrefs.imageFadeInDuration,
      fadeOutDuration: widget.imagePrefs.imageFadeOutDuration,
      imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
      placeholder: (_, __) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surfaceContainerHighest,
              theme.colorScheme.surfaceContainer,
            ],
          ),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      ),
      errorWidget: (_, __, ___) {
        if (_imageIndex + 1 < widget.imageUrls.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _imageIndex += 1);
            }
          });
          return DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
            ),
          );
        }
        return _ListingImageFallback(theme: theme);
      },
    );
  }
}

class _ListingImageFallback extends StatelessWidget {
  const _ListingImageFallback({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            color: theme.colorScheme.outline,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            L10n.tr(
              context,
              'listing.image_unavailable',
              fallback: 'Photo indisponible',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowseEmptyState extends StatelessWidget {
  const _BrowseEmptyState({required this.onReset, required this.onRetry});

  final VoidCallback onReset;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 34,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 10),
            Text(
              L10n.tr(context, 'listing.empty'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              L10n.tr(
                context,
                'listing.empty_hint',
                fallback: 'Essaie de modifier les filtres ou la recherche.',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.clear_all),
                  label: Text(L10n.tr(context, 'common.reset')),
                ),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(L10n.tr(context, 'common.retry')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, this.onChanged});

  final TextEditingController controller;
  final void Function(String)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: L10n.tr(context, 'listing.search_hint'),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, this.icon, this.onPressed});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: icon == null ? null : Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _FavoritesBadge extends StatelessWidget {
  const _FavoritesBadge({
    required this.countStream,
    required this.enabled,
    required this.onPressed,
  });

  final Stream<Set<String>> countStream;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: countStream,
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              onPressed: onPressed,
              icon: Icon(enabled ? Icons.favorite : Icons.favorite_border),
              tooltip: L10n.tr(context, 'listing.favorites'),
            ),
            if (count > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
          );
        },
      ),
    );
  }
}

class _GridLoader extends StatelessWidget {
  const _GridLoader();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
