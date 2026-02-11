import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/material.dart';

class LegalPage extends StatelessWidget {
  const LegalPage({
    super.key,
    required this.titleKey,
    required this.bodyKey,
  });

  final String titleKey;
  final String bodyKey;

  @override
  Widget build(BuildContext context) {
    final title = L10n.tr(context, titleKey);
    final body = L10n.tr(context, bodyKey);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
