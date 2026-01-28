import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/profile/edit_product_page.dart';
import 'package:dzmarket/src/features/listings/product_detail_page.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
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
    final currency = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA');
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Connectez-vous')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mes annonces')),
      body: StreamBuilder<List<Product>>(
        stream: ProductService().streamProductsForOwner(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snapshot.data ?? const [];
          if (products.isEmpty) {
            return const Center(child: Text('Aucune annonce'));
          }
          return ListView.separated(
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = products[index];
              final raw = p.imageUrls.isNotEmpty ? p.imageUrls.first : p.imageUrl;
              final img = InputSanitizer.safeUrl(raw);
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
                  '${currency.format(p.price)}  •  Stock: ${p.stockQuantity}  •  Vendu: ${p.soldCount}',
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
                            const SnackBar(content: Text('Annonce supprimée')),
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
                    const PopupMenuItem(value: 'open', child: Text('Ouvrir')),
                    const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                    if (!p.isArchived)
                      const PopupMenuItem(value: 'archive', child: Text('Archiver')),
                    if (p.isArchived)
                      const PopupMenuItem(
                        value: 'unarchive',
                        child: Text('Rendre active'),
                      ),
                    const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
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
            title: const Text('Supprimer'),
            content: Text('Supprimer "$title" ?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
            ],
          ),
        ) ??
        false;
  }
}
