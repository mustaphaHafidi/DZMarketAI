import 'package:dzmarket/src/models/product.dart';

/// Invisible discovery ranking: when a signed-in user has one detected
/// interest category (from a recent saved search, or failing that their
/// favorites) and no explicit search/filter/sort is active, listings
/// matching that category are moved ahead of the rest. Every item is kept
/// and the relative order within each group is preserved; user intent
/// (search, filters, explicit sort) always takes priority and disables
/// the reorder entirely.
List<Product> applyInterestRanking(
  List<Product> products, {
  required String? interestCategoryId,
  required bool hasActiveUserFilters,
}) {
  if (interestCategoryId == null ||
      interestCategoryId.isEmpty ||
      hasActiveUserFilters) {
    return products;
  }
  final matching = <Product>[];
  final rest = <Product>[];
  for (final product in products) {
    if (product.categoryId == interestCategoryId) {
      matching.add(product);
    } else {
      rest.add(product);
    }
  }
  if (matching.isEmpty) return products;
  return [...matching, ...rest];
}
