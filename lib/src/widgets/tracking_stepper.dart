import 'package:dzmarket/src/models/tracking_progress.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/material.dart';

class TrackingStepper extends StatelessWidget {
  const TrackingStepper({
    super.key,
    required this.presentation,
    this.compact = false,
    this.showAlert = true,
  });

  final TrackingPresentation presentation;
  final bool compact;
  final bool showAlert;

  @override
  Widget build(BuildContext context) {
    final currentIndex = presentation.steps.indexWhere(
      (step) => step.state == TrackingStepState.current,
    );
    final size = compact ? 18.0 : 26.0;
    final labelStyle = compact
        ? Theme.of(context).textTheme.labelSmall
        : Theme.of(context).textTheme.labelMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (
                var index = 0;
                index < presentation.steps.length;
                index++
              ) ...[
                _TrackingStepNode(
                  step: presentation.steps[index],
                  size: size,
                  compact: compact,
                  labelStyle: labelStyle,
                ),
                if (index < presentation.steps.length - 1)
                  _TrackingConnector(
                    active: index < currentIndex,
                    compact: compact,
                  ),
              ],
            ],
          ),
        ),
        if (showAlert && presentation.alert != null) ...[
          SizedBox(height: compact ? 8 : 12),
          _TrackingAlertBanner(alert: presentation.alert!),
        ],
      ],
    );
  }
}

class _TrackingStepNode extends StatelessWidget {
  const _TrackingStepNode({
    required this.step,
    required this.size,
    required this.compact,
    required this.labelStyle,
  });

  final TrackingStep step;
  final double size;
  final bool compact;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isComplete = step.state == TrackingStepState.complete;
    final isCurrent = step.state == TrackingStepState.current;
    final fillColor = isComplete
        ? Colors.green
        : isCurrent
        ? colorScheme.primary
        : colorScheme.surface;
    final borderColor = isComplete || isCurrent
        ? fillColor
        : colorScheme.outlineVariant;
    final iconColor = isComplete || isCurrent
        ? Colors.white
        : colorScheme.outline;

    return SizedBox(
      width: compact ? 72 : 92,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: fillColor,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 2),
            ),
            alignment: Alignment.center,
            child: Icon(
              isComplete ? Icons.check : _iconForStep(step.id),
              size: compact ? 11 : 14,
              color: iconColor,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            L10n.tr(context, step.labelKey),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: labelStyle?.copyWith(
              color: isCurrent
                  ? colorScheme.onSurface
                  : Theme.of(context).textTheme.bodySmall?.color,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForStep(TrackingStepId id) {
    switch (id) {
      case TrackingStepId.ordered:
        return Icons.shopping_bag_outlined;
      case TrackingStepId.labelReady:
        return Icons.picture_as_pdf_outlined;
      case TrackingStepId.inTransit:
        return Icons.local_shipping_outlined;
      case TrackingStepId.outForDelivery:
        return Icons.delivery_dining_outlined;
      case TrackingStepId.delivered:
        return Icons.inventory_2_outlined;
    }
  }
}

class _TrackingConnector extends StatelessWidget {
  const _TrackingConnector({required this.active, required this.compact});

  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 24 : 32,
      height: compact ? 18 : 26,
      alignment: Alignment.center,
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          color: active
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _TrackingAlertBanner extends StatelessWidget {
  const _TrackingAlertBanner({required this.alert});

  final TrackingAlert alert;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (alert.severity) {
      TrackingAlertSeverity.info => colorScheme.primary,
      TrackingAlertSeverity.warning => Colors.orange.shade700,
      TrackingAlertSeverity.critical => colorScheme.error,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(_iconForSeverity(alert.severity), size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              L10n.tr(context, alert.messageKey),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForSeverity(TrackingAlertSeverity severity) {
    switch (severity) {
      case TrackingAlertSeverity.info:
        return Icons.info_outline;
      case TrackingAlertSeverity.warning:
        return Icons.warning_amber_rounded;
      case TrackingAlertSeverity.critical:
        return Icons.cancel_outlined;
    }
  }
}
