// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/listings/add_listing_page.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/category_service.dart';
import 'package:dzmarket/src/services/favorite_service.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/product_service.dart';
import 'package:dzmarket/src/services/saved_search_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/widgets/refresh_controller.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class ListingsPage extends StatefulWidget {
  const ListingsPage({super.key});

  @override
  State<ListingsPage> createState() => _ListingsPageState();
}

class _ListingsPageState extends State<ListingsPage> {
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
  List<Product> _products = const [];
  bool _loading = false;
  bool _initialLoad = true;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 30;
  String? _activeQueryKey;

  List<Map<String, String>> _categories = const [
    {'id': 'any', 'name_fr': 'Toutes categories', 'name_ar': 'كل الفئات'},
  ];
  final _conditions = ['any', 'new', 'like new', 'good', 'fair'];
  final RefreshController _refreshController = RefreshController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _refresh();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadCategories() async {
    final data = await CategoryService().fetchCategories();
    if (!mounted) return;
    setState(() {
      _categories = [
        {'id': 'any', 'name_fr': 'Toutes categories', 'name_ar': 'كل الفئات'},
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
    final currency = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA');
    final userId = supabase.auth.currentUser?.id;
    final isWide = MediaQuery.of(context).size.width > 900;
    final crossAxisCount = isWide ? 3 : 2;

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
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => _showFilters(context),
            tooltip: L10n.t(context, 'Filtres', 'مرشحات'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (userId != null)
            _SavedSearchesRow(
              userId: userId,
              apply: _applySavedSearch,
              clearFilters: _clearFilters,
              saveSearch: _saveSearch,
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
                  ),
                );

              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddListing(context),
        label: Text(L10n.t(context, 'Vendre', 'بيع')),
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

  double? _safeMinPrice() =>
      double.tryParse(InputSanitizer.sanitizeText(_priceMin.text, maxLength: 16));

  double? _safeMaxPrice() =>
      double.tryParse(InputSanitizer.sanitizeText(_priceMax.text, maxLength: 16));

  String _queryKey() {
    final userId = supabase.auth.currentUser?.id ?? '';
    return [
      _safeSearch().toLowerCase(),
      _safeCondition(),
      _safeCategory(),
      _safeMinPrice()?.toString() ?? '',
      _safeMaxPrice()?.toString() ?? '',
      _safeBrand(),
      _safeSize(),
      _safeColor(),
      _sort,
      userId,
    ].join('|');
  }

  Future<void> _refresh() async {
    final key = _queryKey();
    _activeQueryKey = key;
    final min = _safeMinPrice();
    final max = _safeMaxPrice();
    setState(() {
      _loading = true;
      _initialLoad = _products.isEmpty;
      _page = 0;
      _hasMore = true;
      _products = const [];
    });

    List<Product> results = const [];
    try {
      results = await ProductService()
          .fetchProducts(
            search: _safeSearch(),
            categoryId: _safeCategory(),
            condition: _safeCondition(),
            minPrice: min,
            maxPrice: max,
            brand: _safeBrand(),
            size: _safeSize(),
            color: _safeColor(),
            sort: _sort,
            limit: _pageSize,
            offset: 0,
            excludeOwner: true,
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rafraîchissement trop long.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }

    if (!mounted || _activeQueryKey != key) return;
    setState(() {
      _products = results;
      _loading = false;
      _initialLoad = false;
      _hasMore = results.length == _pageSize;
      _page = 1;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final key = _activeQueryKey ?? _queryKey();
    final min = _safeMinPrice();
    final max = _safeMaxPrice();
    setState(() => _loading = true);

    List<Product> results = const [];
    try {
      results = await ProductService()
          .fetchProducts(
            search: _safeSearch(),
            categoryId: _safeCategory(),
            condition: _safeCondition(),
            minPrice: min,
            maxPrice: max,
            brand: _safeBrand(),
            size: _safeSize(),
            color: _safeColor(),
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

  Widget _buildProductsGrid(
    Set<String> favorites,
    String? userId,
    NumberFormat currency,
    int crossAxisCount,
  ) {
    final showSkeleton = _initialLoad && _loading;
    final filtered = _applyClientFilters(_products, favorites);
    if (showSkeleton) {
      return const _GridSkeleton();
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          L10n.t(
            context,
            'Aucune annonce ne correspond.',
            'لا يوجد تطابق.',
          ),
        ),
      );
    }
    final showLoader = _loading && _products.isNotEmpty;
    final itemCount = filtered.length + (showLoader ? 1 : 0);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        controller: _scrollController,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.72,
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
                : () => FavoriteService().toggleFavorite(
                      productId: product.id,
                      isFav: isFav,
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
    if (!_showFavoritesOnly) return products;
    return products.where((p) => favorites.contains(p.id)).toList();
  }

  String _conditionLabel(BuildContext context, String value) {
    switch (value) {
      case 'any':
        return L10n.t(context, 'Toutes conditions', 'كل الحالات');
      case 'new':
        return L10n.t(context, 'Neuf', 'جديد', key: 'condition.new');
      case 'like new':
        return L10n.t(context, 'Comme neuf', 'كالجديد', key: 'condition.like_new');
      case 'good':
        return L10n.t(context, 'Bon', 'جيد', key: 'condition.good');
      case 'fair':
        return L10n.t(context, 'Correct', 'مقبول', key: 'condition.fair');
      default:
        return value;
    }
  }

  String _categoryLabel(BuildContext context, Map<String, String> category) {
    final fr = category['name_fr'] ?? category['name'] ?? '';
    final ar = category['name_ar'] ?? fr;
    return L10n.t(context, fr, ar);
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
    };
  }

  Future<void> _saveSearch() async {
    final nameController = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.t(context, 'Enregistrer cette recherche', 'حفظ هذا البحث')),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: L10n.t(context, 'Nom', 'الاسم', key: 'saved_search.name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L10n.t(context, 'Annuler', 'إلغاء')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text(L10n.t(context, 'Enregistrer', 'حفظ')),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.t(context, 'Recherche enregistrée', 'تم حفظ البحث'))),
    );
  }

  Future<void> _showFilters(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      L10n.t(context, 'Filtres', 'مرشحات'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _clearFilters,
                      child: Text(L10n.t(context, 'Réinitialiser', 'إعادة تعيين')),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _conditions
                      .map(
                        (c) => ChoiceChip(
                          label: Text(_conditionLabel(context, c)),
                          selected: _condition == c,
                          onSelected: (_) => setState(() => _condition = c),
                        ),
                      )
                      .toList(),
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
                                ? L10n.t(
                                    context,
                                    'Toutes catégories',
                                    'كل الفئات',
                                  )
                                : _categoryLabel(context, c),
                          ),
                          selected: _category == c['id'],
                          onSelected: (_) =>
                              setState(() => _category = c['id'] ?? 'any'),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _priceMin,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: L10n.t(context, 'Min DA', 'الحد الأدنى دج'),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _priceMax,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: L10n.t(context, 'Max DA', 'الحد الأقصى دج'),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _brand,
                  decoration: InputDecoration(
                    labelText: L10n.t(context, 'Marque', 'العلامة'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _size,
                  decoration: InputDecoration(
                    labelText: L10n.t(context, 'Taille', 'المقاس'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _color,
                  decoration: InputDecoration(
                    labelText: L10n.t(context, 'Couleur', 'اللون'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _sort,
                  decoration: InputDecoration(
                    labelText: L10n.t(context, 'Tri', 'الترتيب'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text(
                        L10n.t(context, 'Plus récentes', 'الأحدث'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'price_low',
                      child: Text(
                        L10n.t(context, 'Prix croissant', 'السعر تصاعدي'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'price_high',
                      child: Text(
                        L10n.t(context, 'Prix décroissant', 'السعر تنازلي'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _sort = value);
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _refresh();
                    },
                    child: Text(
                      L10n.t(
                        context,
                        'Afficher les résultats',
                        'عرض النتائج',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    });
    _refresh();
  }

  Future<void> _openAddListing(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddListingPage()),
    );
  }
}

class _SavedSearchesRow extends StatelessWidget {
  const _SavedSearchesRow({
    required this.userId,
    required this.apply,
    required this.clearFilters,
    required this.saveSearch,
  });

  final String userId;
  final void Function(SavedSearch) apply;
  final VoidCallback clearFilters;
  final VoidCallback saveSearch;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          TextButton.icon(
            onPressed: clearFilters,
            icon: const Icon(Icons.clear_all),
            label: Text(L10n.t(context, 'Réinitialiser', 'إعادة تعيين')),
          ),
          TextButton.icon(
            onPressed: saveSearch,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(L10n.t(context, 'Enregistrer', 'حفظ')),
          ),
          Expanded(
            child: StreamBuilder<List<SavedSearch>>(
              stream: SavedSearchService().streamSavedSearches(userId),
              builder: (context, snapshot) {
                final saved = snapshot.data ?? const [];
                if (saved.isEmpty) return const SizedBox.shrink();
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemBuilder: (context, index) {
                    final s = saved[index];
                    return InputChip(
                      label: Text(s.name),
                      onPressed: () => apply(s),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemCount: saved.length,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.currency,
    required this.isFavorite,
    required this.onFavoriteToggle,
  });

  final Product product;
  final NumberFormat currency;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  @override
  Widget build(BuildContext context) {
    const fallbackImage =
        'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=900&q=80';
    final firstImage = product.imageUrls.isNotEmpty
        ? product.imageUrls.first
        : (product.imageUrl ?? fallbackImage);
    return InkWell(
      onTap: () => context.push('/product/${product.id}'),
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                        child: CachedNetworkImage(
                          imageUrl: firstImage,
                          fit: BoxFit.cover,
                          imageRenderMethodForWeb:
                              ImageRenderMethodForWeb.HtmlImage,
                          errorWidget: (_, __, ___) => Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.image_not_supported),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          currency.format(product.price),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton(
                        onPressed: onFavoriteToggle,
                        icon: Icon(
                          isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: isFavorite
                              ? Colors.redAccent
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.surface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  if (product.brand != null && product.brand!.isNotEmpty)
                    Text(
                      '${product.brand}${product.size != null ? ' - ${product.size}' : ''}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (product.condition != null &&
                      product.condition!.isNotEmpty)
                    Chip(
                      label: Text(product.condition!),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
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
                hintText: L10n.t(
                  context,
                  'Rechercher des articles...',
                  'ابحث عن منتجات...',
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
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
              icon: Icon(
                enabled ? Icons.favorite : Icons.favorite_border,
              ),
              tooltip: L10n.t(context, 'Favoris', 'المفضلة'),
            ),
            if (count > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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


