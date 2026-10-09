import 'package:dzmarket/src/models/product.dart';

/// Invisible discovery ranking: when a signed-in user has one detected
/// interest category (from a recent saved search, or failing that their
/// favorites) and no explicit search/filter/sort is active, listings
/// matching that category are moved ahead of the rest. Every item is kept
/// and the relative order within each group is preserved; user intent
/// (search, filters, explicit sort) always takes priority and disables
/// the reorder entirely.
///
/// Listings the user already favorited are never part of the boost: the
/// user already knows about and saved those, so re-surfacing them at the
/// top adds no discovery value. They stay in the list, just in their
/// original relative position among the non-matching items.
List<Product> applyInterestRanking(
  List<Product> products, {
  required String? interestCategoryId,
  required bool hasActiveUserFilters,
  Set<String> favoriteIds = const {},
}) {
  if (interestCategoryId == null ||
      interestCategoryId.isEmpty ||
      hasActiveUserFilters) {
    return products;
  }
  final matching = <Product>[];
  final rest = <Product>[];
  for (final product in products) {
    if (product.categoryId == interestCategoryId &&
        !favoriteIds.contains(product.id)) {
      matching.add(product);
    } else {
      rest.add(product);
    }
  }
  if (matching.isEmpty) return products;
  return [...matching, ...rest];
}
