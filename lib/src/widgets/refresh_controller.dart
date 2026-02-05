import 'dart:async';

import 'package:flutter/material.dart';

/// Lightweight refresh controller to guard pull-to-refresh across screens.
/// Prevents concurrent refresh, enforces timeout, and always clears loading flag.
class RefreshController {
  RefreshController({this.timeout = const Duration(seconds: 8)});

  final Duration timeout;
  bool _refreshing = false;
  bool get refreshing => _refreshing;

  Future<void> run(BuildContext context, Future<void> Function() action) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await action().timeout(timeout);
    } on TimeoutException catch (_) {
      if (!context.mounted) return;
      _showSnack(context, 'Temps dépassé, vérifie la connexion.');
    } catch (e) {
      if (!context.mounted) return;
      _showSnack(context, e.toString());
    } finally {
      _refreshing = false;
    }
  }

  void _showSnack(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}

