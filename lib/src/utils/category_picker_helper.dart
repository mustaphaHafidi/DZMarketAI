import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/material.dart';

/// Shared category-tree lookup, label rendering, and picker bottom sheet,
/// used by both the listing creation form and the listing edit form so the
/// two screens stay in sync and never drift on how a category is selected
/// or displayed.
class CategoryPickerHelper {
  const CategoryPickerHelper._();

  static bool hasArabicLetters(String value) {
    return RegExp(r'[؀-ۿ]').hasMatch(value);
  }

  static final RegExp _bidiControlChars = RegExp(
    '[\\u200B-\\u200F\\u202A-\\u202E\\u2066-\\u2069\\uFEFF]',
  );

  static bool looksKeyLikeToken(String value) {
    final normalized = value
        .replaceAll(_bidiControlChars, '')
        .trim()
        .toLowerCase();
    return RegExp(r'^[a-z0-9_-]+(?:\.[a-z0-9_-]+)+$').hasMatch(normalized);
  }

  static bool looksMojibake(String value) {
    if (value.isEmpty) return false;
    if (looksKeyLikeToken(value)) return true;
    if (value.contains('�') || value.contains('�')) return true;
    // Common UTF-8/Latin-1 corruption markers.
    if (value.contains('Ã') ||
        value.contains('Â') ||
        value.contains('Ã') ||
        value.contains('Â')) {
      return true;
    }
    if (RegExp(r'[A-Za-z]\?[A-Za-z]').hasMatch(value)) return true;
    return false;
  }

  static String humanizeSlug(String slug) {
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

  static String pickLocalizedName(BuildContext context, String fr, String ar) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    if (!isAr) return fr.isNotEmpty ? fr : ar;
    if (hasArabicLetters(ar)) return ar;
    return fr.isNotEmpty ? fr : ar;
  }

  static String itemLabel(BuildContext context, Map<String, String> item) {
    if (item.isEmpty) return '-';
    final slug = item['slug'] ?? '';
    final fr = item['name_fr'] ?? '';
    final ar = item['name_ar'] ?? fr;
    var fallback = pickLocalizedName(context, fr, ar);
    if (looksMojibake(fallback) || fallback.trim().isEmpty) {
      fallback = humanizeSlug(slug);
    }
    if (slug.isEmpty) return fallback;
    return L10n.tr(context, 'category.$slug', fallback: fallback);
  }

  static Map<String, String>? findById(
    List<Map<String, String>> categories,
    String? id,
  ) {
    if (id == null || id.isEmpty) return null;
    for (final item in categories) {
      if (item['id'] == id) return item;
    }
    return null;
  }

  static List<Map<String, String>> rootCategories(
    BuildContext context,
    List<Map<String, String>> categories,
  ) {
    final roots = categories
        .where((c) => (c['parent_id'] ?? '').trim().isEmpty)
        .toList();
    roots.sort(
      (a, b) => itemLabel(context, a).compareTo(itemLabel(context, b)),
    );
    return roots;
  }

  static List<Map<String, String>> childrenOf(
    BuildContext context,
    List<Map<String, String>> categories,
    String parentId,
  ) {
    final children = categories
        .where((c) => (c['parent_id'] ?? '').trim() == parentId)
        .toList();
    children.sort(
      (a, b) => itemLabel(context, a).compareTo(itemLabel(context, b)),
    );
    return children;
  }

  static String pathLabel(
    BuildContext context,
    List<Map<String, String>> categories,
    Map<String, String> category,
  ) {
    final parentId = category['parent_id'] ?? '';
    if (parentId.isEmpty) return itemLabel(context, category);
    final parent = findById(categories, parentId);
    if (parent == null) return itemLabel(context, category);
    return '${itemLabel(context, parent)} > ${itemLabel(context, category)}';
  }

  static String labelForId(
    BuildContext context,
    List<Map<String, String>> categories,
    String? id,
  ) {
    if (id == null || id.isEmpty) return '-';
    final match = findById(categories, id);
    if (match == null) return id;
    return itemLabel(context, match);
  }

  /// Opens the shared category picker bottom sheet (search + root/children
  /// navigation) and resolves with the picked `{id, slug, name_fr, name_ar,
  /// parent_id}` map, or null if dismissed without a pick.
  static Future<Map<String, String>?> show({
    required BuildContext context,
    required List<Map<String, String>> categories,
    String? currentCategoryId,
  }) {
    final searchCtrl = TextEditingController();
    String activeParentId = '';
    final selected = findById(categories, currentCategoryId);
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
              final roots = rootCategories(sheetContext, categories);
              final activeChildren = activeParentId.isEmpty
                  ? const <Map<String, String>>[]
                  : childrenOf(sheetContext, categories, activeParentId);
              final filtered = query.isEmpty
                  ? <Map<String, String>>[]
                  : categories.where((item) {
                      final plain = itemLabel(
                        sheetContext,
                        item,
                      ).toLowerCase();
                      final path = pathLabel(
                        sheetContext,
                        categories,
                        item,
                      ).toLowerCase();
                      return plain.contains(query) || path.contains(query);
                    }).toList();
              if (query.isNotEmpty) {
                filtered.sort(
                  (a, b) => pathLabel(
                    sheetContext,
                    categories,
                    a,
                  ).compareTo(pathLabel(sheetContext, categories, b)),
                );
              }
              Widget buildCategoryTile(
                Map<String, String> item, {
                required bool showPath,
              }) {
                final hasChildren = childrenOf(
                  sheetContext,
                  categories,
                  item['id'] ?? '',
                ).isNotEmpty;
                final label = showPath
                    ? pathLabel(sheetContext, categories, item)
                    : itemLabel(sheetContext, item);
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
}
