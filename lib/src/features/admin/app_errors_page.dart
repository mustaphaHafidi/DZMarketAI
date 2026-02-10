import 'dart:convert';

import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppErrorsPage extends StatefulWidget {
  const AppErrorsPage({super.key});

  @override
  State<AppErrorsPage> createState() => _AppErrorsPageState();
}

class _AppErrorsPageState extends State<AppErrorsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  final _dateFmt = DateFormat('dd/MM HH:mm');

  @override
  void initState() {
    super.initState();
    _future = _loadErrors();
  }

  Future<List<Map<String, dynamic>>> _loadErrors() async {
    final response = await supabase
        .from('app_errors')
        .select('id,user_id,message,stack,context,platform,created_at')
        .order('created_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadErrors();
    });
    await _future;
  }

  Map<String, dynamic> _parseContext(dynamic raw) {
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    return const {};
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }

  void _showDetails(BuildContext context, Map<String, dynamic> row) {
    final ctx = _parseContext(row['context']);
    final stack = row['stack']?.toString();
    final message = row['message']?.toString() ?? '-';
    final platform = row['platform']?.toString() ?? '-';
    final userId = row['user_id']?.toString() ?? '-';
    final createdAt = _parseDate(row['created_at']);
    final prettyContext =
        const JsonEncoder.withIndent('  ').convert(ctx.isEmpty ? {} : ctx);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.tr(sheetContext, 'admin.errors_view_details'),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(message),
                const SizedBox(height: 12),
                Text('${L10n.tr(sheetContext, 'admin.errors_user')}: $userId'),
                Text(
                  '${L10n.tr(sheetContext, 'admin.errors_platform')}: $platform',
                ),
                if (createdAt != null)
                  Text(
                    '${L10n.tr(sheetContext, 'admin.errors_time')}: ${_dateFmt.format(createdAt)}',
                  ),
                const SizedBox(height: 12),
                Text(
                  L10n.tr(sheetContext, 'admin.errors_context'),
                  style: Theme.of(sheetContext).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                SelectableText(prettyContext),
                if (stack != null && stack.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    L10n.tr(sheetContext, 'admin.errors_stack'),
                    style: Theme.of(sheetContext).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(stack),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context, String text) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(child: Text(text)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.tr(context, 'admin.errors_title'))),
        body: Center(child: Text(L10n.tr(context, 'profile.login_required'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr(context, 'admin.errors_title')),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _buildEmpty(
                context,
                L10n.tr(
                  context,
                  'common.error_with',
                  params: {'error': snapshot.error.toString()},
                ),
              );
            }
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) {
              return _buildEmpty(
                context,
                L10n.tr(context, 'admin.errors_empty'),
              );
            }
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = rows[index];
                final ctx = _parseContext(row['context']);
                final isFatal = ctx['fatal'] == true;
                final message = row['message']?.toString() ?? '-';
                final platform = row['platform']?.toString() ?? '-';
                final uid = row['user_id']?.toString() ??
                    L10n.tr(context, 'admin.errors_unknown_user');
                final createdAt = _parseDate(row['created_at']);
                final timeLabel =
                    createdAt == null ? '-' : _dateFmt.format(createdAt);
                return ListTile(
                  leading: Icon(
                    isFatal
                        ? Icons.error_outline
                        : Icons.bug_report_outlined,
                    color: isFatal
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  title: Text(message),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${L10n.tr(context, 'admin.errors_user')}: $uid',
                      ),
                      Text(
                        '${L10n.tr(context, 'admin.errors_platform')}: $platform',
                      ),
                      Text(
                        '${L10n.tr(context, 'admin.errors_time')}: $timeLabel',
                      ),
                      if (isFatal)
                        Text(
                          L10n.tr(context, 'admin.errors_fatal'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDetails(context, row),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
