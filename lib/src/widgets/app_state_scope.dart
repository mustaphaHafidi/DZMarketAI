import 'package:flutter/material.dart';

import 'package:dzmarket/src/services/session_controller.dart';

class AppStateScope extends InheritedNotifier<SessionController> {
  const AppStateScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  static SessionController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    return scope?.notifier ?? SessionController.instance;
  }
}
