import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/profile/edit_product_page.dart';
import 'package:dzmarket/src/features/listings/product_detail_page.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/product_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Listing management: open, edit, delete own products.
class MyListingsPage extends StatelessWidget {
  const MyListingsPage({super.key});

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
          if (products.isEmpty) {
            return Center(child: Text(L10n.tr(context, 'listing.empty')));
          }
          return ListView.separated(
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = products[index];
              final raw = p.imageUrls.isNotEmpty ? p.imageUrls.first : p.imageUrl;
              final img = InputSanitizer.safeUrl(raw);
              final stockLabel = L10n.tr(
                context,
                'listing.detail.stock',
                params: {'value': p.stockQuantity.toString()},
              );
              final soldLabel = L10n.tr(
                context,
                'listing.detail.sold',
                params: {'value': p.soldCount.toString()},
              );
              return ListTile(
                leading: img != null
                    ? CircleAvatar(
                        backgroundImage: CachedNetworkImageProvider(
                          img,
                          imageRenderMethodForWeb:
                              ImageRenderMethodForWeb.HtmlImage,
                        ),
                      )
                    : const CircleAvatar(child: Icon(Icons.image)),
                title: Text(p.title),
                subtitle: Text(
                  '${currency.format(p.price)} • $stockLabel • $soldLabel',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => EditProductPage(product: p)),
                      );
                    } else if (value == 'delete') {
                      final confirmed = await _confirmDelete(context, p.title);
                      if (confirmed) {
                        await ProductService().deleteProduct(p.id.toString());
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                L10n.tr(context, 'listing.delete_success'),
                              ),
                            ),
                          );
                        }
                      }
                    } else if (value == 'archive') {
                      await ProductService()
                          .updateProduct(id: p.id.toString(), isArchived: true);
                    } else if (value == 'unarchive') {
                      await ProductService()
                          .updateProduct(id: p.id.toString(), isArchived: false);
                    } else {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductDetailPage(productId: p.id.toString()),
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
                    if (!p.isArchived)
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(L10n.tr(context, 'common.archive')),
                      ),
                    if (p.isArchived)
                      PopupMenuItem(
                        value: 'unarchive',
                        child: Text(L10n.tr(context, 'common.unarchive')),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(L10n.tr(context, 'common.delete')),
                    ),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProductDetailPage(productId: p.id.toString()),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String title) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(L10n.tr(context, 'listing.delete_title')),
            content: Text(
              L10n.tr(
                context,
                'listing.delete_confirm',
                params: {'title': title},
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
        ) ??
        false;
  }
}

