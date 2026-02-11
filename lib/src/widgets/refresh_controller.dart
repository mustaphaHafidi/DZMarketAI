import 'dart:async';

import 'package:dzmarket/src/services/connectivity_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/material.dart';

/// Lightweight refresh controller to guard pull-to-refresh across screens.
/// Prevents concurrent refresh, enforces timeout, and always clears loading flag.
class RefreshController {
  RefreshController({
    this.timeout = const Duration(seconds: 10),
    this.retries = 1,
  });

  final Duration timeout;
  final int retries;
  bool _refreshing = false;
  bool get refreshing => _refreshing;

  Future<void> run(BuildContext context, Future<void> Function() action) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      if (!ConnectivityService.instance.isOnline.value) {
        _showSnack(context, L10n.tr(context, 'common.offline_action'));
        return;
      }
      await _runWithRetry(action);
    } on TimeoutException {
      if (!context.mounted) return;
      _showSnack(context, L10n.tr(context, 'common.refresh_timeout'));
    } catch (e) {
      if (!context.mounted) return;
      _showSnack(
        context,
        L10n.tr(
          context,
          'common.error_with',
          params: {'error': e.toString()},
        ),
      );
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _runWithRetry(Future<void> Function() action) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        await action().timeout(timeout);
        return;
      } on TimeoutException {
        if (attempt > retries) rethrow;
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  void _showSnack(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}
