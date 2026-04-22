import 'package:dzmarket/src/features/listings/product_detail_page.dart';
import 'package:dzmarket/src/features/profile/edit_product_page.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/product_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Listing management: open, edit, archive own products.
class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage> {
  String _filter = 'active';
  static const int _maxListings = 30;

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    final localeCode = Localizations.localeOf(context).languageCode;
    final currency = NumberFormat.currency(
      locale: localeCode == 'ar' ? 'ar_DZ' : 'fr_DZ',
      symbol: 'DA',
    );
    if (userId == null) {
      return Scaffold(
        body: Center(child: Text(L10n.tr(context, 'profile.login_required'))),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(L10n.tr(context, 'profile.my_listings'))),
      body: StreamBuilder<List<Product>>(
        stream: ProductService().streamProductsForOwner(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snapshot.data ?? const [];
          final filtered = switch (_filter) {
            'archived' => products
                .where((p) => p.isArchived || p.stockQuantity <= 0)
                .toList(),
            'all' => products,
            _ => products
                .where((p) => !p.isArchived && p.stockQuantity > 0)
                .toList(),
          }
            ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                  a.createdAt ?? DateTime(0),
                ));
          final limited = filtered.take(_maxListings).toList();
          final emptyLabel = switch (_filter) {
            'archived' => L10n.tr(context, 'listing.archived_empty'),
            'active' => L10n.tr(context, 'listing.active_empty'),
            _ => L10n.tr(context, 'listing.empty'),
          };
          return ListView.separated(
            itemCount: limited.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(L10n.tr(context, 'listing.filter_active')),
                        selected: _filter == 'active',
                        onSelected: (_) => setState(() => _filter = 'active'),
                      ),
                      ChoiceChip(
                        label: Text(
                          L10n.tr(context, 'listing.filter_archived'),
                        ),
                        selected: _filter == 'archived',
                        onSelected: (_) =>
                            setState(() => _filter = 'archived'),
                      ),
                      ChoiceChip(
                        label: Text(L10n.tr(context, 'listing.filter_all')),
                        selected: _filter == 'all',
                        onSelected: (_) => setState(() => _filter = 'all'),
                      ),
                    ],
                  ),
                );
              }
              if (limited.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text(emptyLabel)),
                );
              }
              final product = limited[index - 1];
              final imageUrls = product
                  .displayableImageUrls()
                  .map(InputSanitizer.safeUrl)
                  .whereType<String>()
                  .toList();
              final stockLabel = L10n.tr(
                context,
                'listing.detail.stock',
                params: {'value': product.stockQuantity.toString()},
              );
              final soldLabel = L10n.tr(
                context,
                'listing.detail.sold',
                params: {'value': product.soldCount.toString()},
              );
              final metaParts = <String>[
                currency.format(product.price),
                stockLabel,
                soldLabel,
              ];
              if (product.stockQuantity <= 0) {
                metaParts.add(L10n.tr(context, 'cta.out_of_stock'));
              }
              if (product.isArchived) {
                metaParts.add(L10n.tr(context, 'listing.status_archived'));
              }
              return ListTile(
                leading: _MyListingAvatarImage(imageUrls: imageUrls),
                title: Text(product.title),
                subtitle: Text(metaParts.join(' • ')),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditProductPage(product: product),
                        ),
                      );
                    } else if (value == 'archive') {
                      await ProductService().updateProduct(
                        id: product.id.toString(),
                        isArchived: true,
                      );
                    } else if (value == 'unarchive') {
                      await ProductService().updateProduct(
                        id: product.id.toString(),
                        isArchived: false,
                      );
                    } else {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductDetailPage(
                            productId: product.id.toString(),
                          ),
                        ),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'open',
                      child: Text(L10n.tr(context, 'common.open')),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(L10n.tr(context, 'common.edit')),
                    ),
                    if (!product.isArchived)
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(L10n.tr(context, 'common.archive')),
                      ),
                    if (product.isArchived)
                      PopupMenuItem(
                        value: 'unarchive',
                        child: Text(L10n.tr(context, 'common.unarchive')),
                      ),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ProductDetailPage(productId: product.id.toString()),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MyListingAvatarImage extends StatefulWidget {
  const _MyListingAvatarImage({required this.imageUrls});

  final List<String> imageUrls;

  @override
  State<_MyListingAvatarImage> createState() => _MyListingAvatarImageState();
}

class _MyListingAvatarImageState extends State<_MyListingAvatarImage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.image));
    }

    final imageUrl = widget.imageUrls[_index];
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ClipOval(
        child: SizedBox.expand(
          child: Image.network(
            imageUrl,
            key: ValueKey(imageUrl),
            fit: BoxFit.cover,
            loadingBuilder: (_, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const SizedBox.shrink();
            },
            errorBuilder: (_, __, ___) {
              if (_index + 1 < widget.imageUrls.length) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _index += 1);
                  }
                });
                return const SizedBox.shrink();
              }
              return const Icon(Icons.image);
            },
          ),
        ),
      ),
    );
  }
}
