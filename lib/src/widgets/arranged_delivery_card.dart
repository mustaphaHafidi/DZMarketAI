import 'package:flutter/material.dart';

class ArrangedDeliveryCard extends StatelessWidget {
  const ArrangedDeliveryCard({
    super.key,
    required this.title,
    required this.description,
    this.statusLabel,
    this.compact = false,
  });

  final String title;
  final String description;
  final String? statusLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = compact ? 8.0 : 12.0;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.handshake_outlined,
                size: compact ? 18 : 20,
                color: colorScheme.primary,
              ),
              SizedBox(width: spacing),
              Expanded(
                child: Text(
                  title,
                  style: (compact
                          ? Theme.of(context).textTheme.titleSmall
                          : Theme.of(context).textTheme.titleMedium)
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (statusLabel != null && statusLabel!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Chip(
                    label: Text(statusLabel!),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            description,
            style: compact
                ? Theme.of(context).textTheme.bodySmall
                : Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
