import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Seller dashboard for shipments with quick status change and label access.
class ShipmentsDashboardPage extends StatelessWidget {
  const ShipmentsDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Non connecté')));
    }
    final service = ShippingService();
    final dateFmt = DateFormat('dd/MM HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Livraisons')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: service.streamSellerShipments(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('Aucune livraison'));
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = rows[i];
              final status = (r['status'] as String?) ?? 'pending';
              final carrier = r['carrier'] as String? ?? '-';
              final tracking = r['tracking_number'] as String? ?? '-';
              final cost = r['shipping_cost'] != null
                  ? (r['shipping_cost'] as num).toStringAsFixed(0)
                  : null;
              final labelUrl = r['label_url'] as String?;
              final createdAt = r['created_at'] != null
                  ? DateTime.tryParse(r['created_at'] as String)
                  : null;
              final orderId = r['order_id']?.toString() ?? '?';
              return ListTile(
                title: Text('Commande #$orderId · $carrier'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Statut: $status'),
                    Text('Tracking: $tracking'),
                    if (cost != null) Text('Frais: $cost DA'),
                    if (createdAt != null) Text('Créé: ${dateFmt.format(createdAt)}'),
                    if (labelUrl != null)
                      Text(
                        'Label prêt',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => _showStatusSheet(context, orderId, status),
                          icon: const Icon(Icons.sync_outlined, size: 18),
                          label: const Text('Changer statut'),
                        ),
                        if (labelUrl != null)
                          TextButton.icon(
                            onPressed: () => _openLabel(labelUrl),
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            label: const Text('Ouvrir label'),
                          ),
                      ],
                    ),
                  ],
                ),
                trailing: labelUrl != null
                    ? IconButton(
                        icon: const Icon(Icons.link),
                        onPressed: () => _openLabel(labelUrl),
                      )
                    : null,
                onTap: () => _showStatusSheet(context, orderId, status),
              );
            },
          );
        },
      ),
    );
  }

  void _showStatusSheet(BuildContext context, String orderId, String current) {
    final service = ShippingService();
    final statuses = ['pending', 'paid', 'shipped', 'delivered'];
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: statuses
                .map(
                  (s) => ListTile(
                    title: Text(s),
                    trailing: s == current ? const Icon(Icons.check) : null,
                    onTap: () async {
                      await service.updateShipmentStatus(orderId: orderId, status: s);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Future<void> _openLabel(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
