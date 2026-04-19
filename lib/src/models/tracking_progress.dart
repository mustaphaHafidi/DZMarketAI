import 'package:dzmarket/src/models/shipment.dart';

enum TrackingStepId {
  ordered,
  labelReady,
  inTransit,
  outForDelivery,
  delivered,
}

enum TrackingStepState { complete, current, pending }

enum TrackingAlertSeverity { info, warning, critical }

class TrackingStep {
  const TrackingStep({
    required this.id,
    required this.labelKey,
    required this.state,
  });

  final TrackingStepId id;
  final String labelKey;
  final TrackingStepState state;
}

class TrackingAlert {
  const TrackingAlert({required this.messageKey, required this.severity});

  final String messageKey;
  final TrackingAlertSeverity severity;
}

class TrackingPresentation {
  const TrackingPresentation({
    required this.currentStep,
    required this.displayStatusKey,
    required this.displayStatusFallback,
    required this.steps,
    this.alert,
  });

  factory TrackingPresentation.fromShipment(
    Shipment? shipment, {
    DateTime? createdAt,
  }) {
    if (shipment == null) {
      return TrackingPresentation.fromData(createdAt: createdAt);
    }
    return TrackingPresentation.fromData(
      status: shipment.status,
      trackingNumber: shipment.trackingNumber,
      labelUrl: shipment.labelUrl,
      createdAt: createdAt ?? shipment.createdAt,
      events: shipment.events,
    );
  }

  factory TrackingPresentation.fromData({
    String? status,
    String? trackingNumber,
    String? labelUrl,
    DateTime? createdAt,
    List<ShipmentEvent> events = const <ShipmentEvent>[],
    String? systemEventKey,
  }) {
    final normalizedStatus = _normalizeStatus(status);
    final hasLabel = _hasValue(labelUrl);
    final hasTracking = _hasValue(trackingNumber);
    final hasCarrierProgress = _hasCarrierProgress(events);
    final isOutForDelivery =
        normalizedStatus == 'out_for_delivery' ||
        _hasOutForDeliveryEvent(events);
    final currentStep = _resolveCurrentStep(
      normalizedStatus: normalizedStatus,
      hasLabel: hasLabel,
      hasTracking: hasTracking,
      hasCarrierProgress: hasCarrierProgress,
      isOutForDelivery: isOutForDelivery,
    );
    final alert = _resolveAlert(
      normalizedStatus: normalizedStatus,
      hasLabel: hasLabel,
      hasTracking: hasTracking,
      hasCarrierProgress: hasCarrierProgress,
      createdAt: createdAt,
      systemEventKey: systemEventKey,
    );

    return TrackingPresentation(
      currentStep: currentStep,
      displayStatusKey: _displayStatusKey(
        normalizedStatus: normalizedStatus,
        currentStep: currentStep,
      ),
      displayStatusFallback: normalizedStatus.isEmpty
          ? 'pending'
          : normalizedStatus,
      steps: _buildSteps(currentStep),
      alert: alert,
    );
  }

  final TrackingStepId currentStep;
  final String displayStatusKey;
  final String displayStatusFallback;
  final List<TrackingStep> steps;
  final TrackingAlert? alert;

  static List<TrackingStep> _buildSteps(TrackingStepId currentStep) {
    const order = <TrackingStepId>[
      TrackingStepId.ordered,
      TrackingStepId.labelReady,
      TrackingStepId.inTransit,
      TrackingStepId.outForDelivery,
      TrackingStepId.delivered,
    ];
    final currentIndex = order.indexOf(currentStep);
    return order
        .asMap()
        .entries
        .map((entry) {
          final step = entry.value;
          final index = entry.key;
          final state = index < currentIndex
              ? TrackingStepState.complete
              : index == currentIndex
              ? TrackingStepState.current
              : TrackingStepState.pending;
          return TrackingStep(
            id: step,
            labelKey: _stepLabelKey(step),
            state: state,
          );
        })
        .toList(growable: false);
  }

  static TrackingStepId _resolveCurrentStep({
    required String normalizedStatus,
    required bool hasLabel,
    required bool hasTracking,
    required bool hasCarrierProgress,
    required bool isOutForDelivery,
  }) {
    if (normalizedStatus == 'delivered') {
      return TrackingStepId.delivered;
    }
    if (isOutForDelivery) {
      return TrackingStepId.outForDelivery;
    }
    if (hasCarrierProgress) {
      return TrackingStepId.inTransit;
    }
    if (normalizedStatus == 'validated' ||
        normalizedStatus == 'shipped' ||
        hasLabel ||
        hasTracking) {
      return TrackingStepId.labelReady;
    }
    return TrackingStepId.ordered;
  }

  static TrackingAlert? _resolveAlert({
    required String normalizedStatus,
    required bool hasLabel,
    required bool hasTracking,
    required bool hasCarrierProgress,
    required DateTime? createdAt,
    required String? systemEventKey,
  }) {
    switch (systemEventKey) {
      case 'order.system.label_reminder':
        return const TrackingAlert(
          messageKey: 'tracking.alert.label_reminder',
          severity: TrackingAlertSeverity.warning,
        );
      case 'order.system.carrier_scan_reminder':
        return const TrackingAlert(
          messageKey: 'tracking.alert.dropoff_overdue',
          severity: TrackingAlertSeverity.warning,
        );
    }

    switch (normalizedStatus) {
      case 'cancelled':
        return const TrackingAlert(
          messageKey: 'tracking.alert.cancelled',
          severity: TrackingAlertSeverity.critical,
        );
      case 'returned_to_sender':
        return const TrackingAlert(
          messageKey: 'tracking.alert.returned_to_sender',
          severity: TrackingAlertSeverity.info,
        );
      case 'not_claimed':
        return const TrackingAlert(
          messageKey: 'tracking.alert.not_claimed',
          severity: TrackingAlertSeverity.info,
        );
      case 'refused':
        return const TrackingAlert(
          messageKey: 'tracking.alert.refused',
          severity: TrackingAlertSeverity.info,
        );
    }

    if (createdAt == null) return null;
    final age = DateTime.now().difference(createdAt.toLocal());
    final hasLabelOrTracking = hasLabel || hasTracking;
    if (!hasLabelOrTracking) {
      if (age.inHours >= 72) {
        return const TrackingAlert(
          messageKey: 'tracking.alert.auto_cancel_soon',
          severity: TrackingAlertSeverity.critical,
        );
      }
      if (age.inHours >= 48) {
        return const TrackingAlert(
          messageKey: 'tracking.alert.label_reminder',
          severity: TrackingAlertSeverity.warning,
        );
      }
      return null;
    }
    if (!hasCarrierProgress && age.inHours >= 96) {
      return const TrackingAlert(
        messageKey: 'tracking.alert.dropoff_overdue',
        severity: TrackingAlertSeverity.warning,
      );
    }
    return null;
  }

  static bool _hasCarrierProgress(List<ShipmentEvent> events) {
    for (final event in events) {
      final status = _normalizeStatus(event.status);
      if (status == 'shipped' ||
          status == 'out_for_delivery' ||
          status == 'delivered' ||
          status == 'returned_to_sender' ||
          status == 'not_claimed' ||
          status == 'refused') {
        return true;
      }
      if (_containsOutForDeliveryToken(event.title) ||
          _containsOutForDeliveryToken(event.description) ||
          _containsTransitToken(event.title) ||
          _containsTransitToken(event.description)) {
        return true;
      }
    }
    return false;
  }

  static bool _hasOutForDeliveryEvent(List<ShipmentEvent> events) {
    for (final event in events) {
      final status = _normalizeStatus(event.status);
      if (status == 'out_for_delivery') return true;
      if (_containsOutForDeliveryToken(event.title) ||
          _containsOutForDeliveryToken(event.description)) {
        return true;
      }
    }
    return false;
  }

  static String _displayStatusKey({
    required String normalizedStatus,
    required TrackingStepId currentStep,
  }) {
    switch (normalizedStatus) {
      case 'cancelled':
        return 'order.status.cancelled';
      case 'returned_to_sender':
        return 'order.status.returned_to_sender';
      case 'not_claimed':
        return 'order.status.not_claimed';
      case 'refused':
        return 'order.status.refused';
      case 'delivered':
        return 'order.status.delivered';
      case 'out_for_delivery':
        return 'order.status.out_for_delivery';
      case 'paid':
        return 'orders.status_paid';
    }
    switch (currentStep) {
      case TrackingStepId.ordered:
        return normalizedStatus == 'paid'
            ? 'orders.status_paid'
            : 'order.status.pending';
      case TrackingStepId.labelReady:
        return 'tracking.status.label_ready';
      case TrackingStepId.inTransit:
        return 'tracking.status.in_transit';
      case TrackingStepId.outForDelivery:
        return 'order.status.out_for_delivery';
      case TrackingStepId.delivered:
        return 'order.status.delivered';
    }
  }

  static String _stepLabelKey(TrackingStepId step) {
    switch (step) {
      case TrackingStepId.ordered:
        return 'tracking.step.ordered';
      case TrackingStepId.labelReady:
        return 'tracking.step.label_ready';
      case TrackingStepId.inTransit:
        return 'tracking.step.in_transit';
      case TrackingStepId.outForDelivery:
        return 'tracking.step.out_for_delivery';
      case TrackingStepId.delivered:
        return 'tracking.step.delivered';
    }
  }

  static String _normalizeStatus(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return '';
    if (normalized == 'paid') return 'paid';
    if (normalized == 'validated') return 'validated';
    if (normalized == 'shipped') return 'shipped';
    if (normalized == 'out_for_delivery') return 'out_for_delivery';
    if (normalized == 'delivered') return 'delivered';
    if (normalized == 'cancelled') return 'cancelled';
    if (normalized == 'returned_to_sender') return 'returned_to_sender';
    if (normalized == 'not_claimed') return 'not_claimed';
    if (normalized == 'refused') return 'refused';
    return normalized;
  }

  static bool _containsTransitToken(String? value) {
    final text = _normalizeFreeText(value);
    if (text.isEmpty) return false;
    return text.contains('transit') ||
        text.contains('exped') ||
        text.contains('picked') ||
        text.contains('acceptedbycarrier') ||
        text.contains('dispatch');
  }

  static bool _containsOutForDeliveryToken(String? value) {
    final text = _normalizeFreeText(value);
    if (text.isEmpty) return false;
    return text.contains('outfordelivery') ||
        text.contains('encoursdelivraison') ||
        text.contains('enlivraison') ||
        text.contains('distribution') ||
        text.contains('attemptdelivery');
  }

  static bool _hasValue(String? value) => (value ?? '').trim().isNotEmpty;

  static String _normalizeFreeText(String? value) {
    return (value ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}
