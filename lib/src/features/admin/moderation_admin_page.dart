import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ModerationAdminPage extends StatefulWidget {
  const ModerationAdminPage({super.key});

  @override
  State<ModerationAdminPage> createState() => _ModerationAdminPageState();
}

class _ModerationAdminPageState extends State<ModerationAdminPage>
    with SingleTickerProviderStateMixin {
  static const _reportsThreshold = 10;
  static const _reportsWindowDays = 7;

  late final TabController _tabs;
  final _dateFmt = DateFormat('dd/MM HH:mm');
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _listings = const [];
  List<_ReportQueueItem> _reportQueue = const [];
  List<_DeletionRequestItem> _deletionRequests = const [];

  String _search = '';
  String _userStatusFilter = 'all';
  String _listingStatusFilter = 'all';
  bool _reportsPriorityOnly = true;
  String _deletionStatusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _searchCtrl.addListener(() {
      setState(() {
        _search = _searchCtrl.text.trim().toLowerCase();
      });
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reportsSince = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: _reportsWindowDays))
          .toIso8601String();

      final usersFuture = supabase
          .from('profiles')
          .select('id,email,full_name,role,status,created_at')
          .order('created_at', ascending: false)
          .limit(400);

      final listingsFuture = supabase
          .from('products')
          .select(
            'id,title,owner_id,moderation_status,moderation_reason,moderation_updated_at,created_at',
          )
          .order('moderation_updated_at', ascending: false)
          .limit(600);

      final reportsFuture = supabase
          .from('reports')
          .select(
            'product_id,reporter_id,reason,created_at,product:products(id,title,owner_id,moderation_status,moderation_reason)',
          )
          .gte('created_at', reportsSince)
          .order('created_at', ascending: false)
          .limit(3000);

      final deletionRequestsFuture = _invokeAdminModeration(
        action: 'list_account_deletion_requests',
        payload: const {},
      );

      final responses = await Future.wait<dynamic>([
        usersFuture,
        listingsFuture,
        reportsFuture,
        deletionRequestsFuture,
      ]);

      if (!mounted) return;
      final deletionPayload = responses[3] as Map<String, dynamic>;
      final deletionRows = (deletionPayload['requests'] as List? ?? const [])
          .cast<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList();
      setState(() {
        _users = (responses[0] as List).cast<Map<String, dynamic>>();
        _listings = (responses[1] as List).cast<Map<String, dynamic>>();
        _reportQueue = _buildReportQueue(
          (responses[2] as List).cast<Map<String, dynamic>>(),
        );
        _deletionRequests = deletionRows
            .map(_DeletionRequestItem.fromJson)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_ReportQueueItem> _buildReportQueue(List<Map<String, dynamic>> rows) {
    final map = <int, _ReportAccumulator>{};
    for (final row in rows) {
      final product = row['product'];
      if (product is! Map) continue;
      final productMap = product.cast<String, dynamic>();
      final productId = (productMap['id'] as num?)?.toInt();
      if (productId == null) continue;

      final acc = map.putIfAbsent(productId, () {
        return _ReportAccumulator(
          productId: productId,
          title: productMap['title']?.toString() ?? '-',
          ownerId: productMap['owner_id']?.toString() ?? '',
          moderationStatus:
              productMap['moderation_status']?.toString() ?? 'approved',
          moderationReason: productMap['moderation_reason']?.toString(),
        );
      });

      final reporterId = row['reporter_id']?.toString();
      if (reporterId != null && reporterId.isNotEmpty) {
        acc.reporters.add(reporterId);
      }
      acc.totalReports += 1;

      final reason = row['reason']?.toString();
      if ((acc.sampleReason == null || acc.sampleReason!.isEmpty) &&
          reason != null &&
          reason.trim().isNotEmpty) {
        acc.sampleReason = reason.trim();
      }

      final date = _parseDate(row['created_at']);
      if (date != null &&
          (acc.lastReportedAt == null || date.isAfter(acc.lastReportedAt!))) {
        acc.lastReportedAt = date;
      }
    }

    final items = map.values.map((acc) => acc.toItem()).toList();
    items.sort((a, b) {
      final cmpReporter = b.uniqueReporters.compareTo(a.uniqueReporters);
      if (cmpReporter != 0) return cmpReporter;
      final cmpTotal = b.totalReports.compareTo(a.totalReports);
      if (cmpTotal != 0) return cmpTotal;
      final aTime = a.lastReportedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.lastReportedAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });
    return items;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  bool _matchesSearch(String value) {
    if (_search.isEmpty) return true;
    return value.toLowerCase().contains(_search);
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((u) {
      final status = (u['status']?.toString() ?? 'active').toLowerCase();
      if (_userStatusFilter != 'all' && status != _userStatusFilter) {
        return false;
      }
      final email = u['email']?.toString() ?? '';
      final fullName = u['full_name']?.toString() ?? '';
      final id = u['id']?.toString() ?? '';
      return _matchesSearch('$email $fullName $id');
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredListings {
    return _listings.where((p) {
      final status = (p['moderation_status']?.toString() ?? 'approved')
          .toLowerCase();
      if (_listingStatusFilter != 'all' && status != _listingStatusFilter) {
        return false;
      }
      final title = p['title']?.toString() ?? '';
      final id = p['id']?.toString() ?? '';
      final owner = p['owner_id']?.toString() ?? '';
      return _matchesSearch('$title $id $owner');
    }).toList();
  }

  List<_ReportQueueItem> get _filteredReports {
    return _reportQueue.where((item) {
      if (_reportsPriorityOnly && item.uniqueReporters < _reportsThreshold) {
        return false;
      }
      return _matchesSearch(
        '${item.title} ${item.productId} ${item.ownerId} ${item.sampleReason ?? ''}',
      );
    }).toList();
  }

  List<_DeletionRequestItem> get _filteredDeletionRequests {
    return _deletionRequests.where((item) {
      if (_deletionStatusFilter != 'all' &&
          item.status != _deletionStatusFilter) {
        return false;
      }
      return _matchesSearch(
        '${item.email} ${item.userFullName ?? ''} ${item.userEmail ?? ''} ${item.reason ?? ''} ${item.adminNote ?? ''}',
      );
    }).toList();
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successKey,
  }) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.tr(context, successKey))));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _setUserStatus(String userId, String status) async {
    await _runAction(() async {
      await _invokeAdminModeration(
        action: 'set_user_status',
        payload: {
          'user_id': userId,
          'status': status,
          'reason': 'manual_superadmin',
        },
      );
    }, successKey: 'admin.moderation.action_done');
  }

  Future<void> _setListingStatus(int productId, String status) async {
    await _runAction(() async {
      await _invokeAdminModeration(
        action: 'set_product_moderation',
        payload: {
          'product_id': productId,
          'status': status,
          'reason': 'manual_superadmin',
        },
      );
    }, successKey: 'admin.moderation.action_done');
  }

  Future<void> _promptDeletionRequestAction(
    _DeletionRequestItem item, {
    required String nextStatus,
    required String userAction,
    required String title,
  }) async {
    final noteCtrl = TextEditingController(text: item.adminNote ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.email),
            if ((item.reason ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.reason!.trim()),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: L10n.tr(
                  dialogContext,
                  'admin.moderation.deletion_note',
                  fallback: 'Note admin (optionnel)',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L10n.tr(dialogContext, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(L10n.tr(dialogContext, 'common.save')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      noteCtrl.dispose();
      return;
    }
    await _runAction(() async {
      await _invokeAdminModeration(
        action: 'set_account_deletion_request_status',
        payload: {
          'request_id': item.id,
          'status': nextStatus,
          'user_action': userAction,
          'admin_note': noteCtrl.text.trim(),
        },
      );
    }, successKey: 'admin.moderation.action_done');
    noteCtrl.dispose();
  }

  Future<Map<String, dynamic>> _invokeAdminModeration({
    required String action,
    Map<String, dynamic> payload = const {},
  }) async {
    final response = await supabase.functions.invoke(
      'admin-moderation',
      body: {'action': action, ...payload},
    );
    final data = response.data;
    final status = response.status;
    if (status < 200 || status >= 300) {
      final message = data is Map ? data['message']?.toString() : null;
      throw StateError(message ?? 'admin moderation failed ($status)');
    }
    if (data is Map && data['ok'] == false) {
      throw StateError(
        data['message']?.toString() ?? 'admin moderation failed',
      );
    }
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    return const {'ok': true};
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildStatusFilter({
    required String selected,
    required void Function(String) onSelected,
    required List<String> values,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((value) {
        final label = value == 'all'
            ? L10n.tr(context, 'admin.moderation.filter_all')
            : _statusLabel(value);
        return ChoiceChip(
          label: Text(label),
          selected: selected == value,
          onSelected: (_) => onSelected(value),
        );
      }).toList(),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return L10n.tr(context, 'admin.moderation.status_active');
      case 'suspended':
        return L10n.tr(context, 'admin.moderation.status_suspended');
      case 'banned':
        return L10n.tr(context, 'admin.moderation.status_banned');
      case 'approved':
        return L10n.tr(context, 'admin.moderation.listing_approved');
      case 'masked':
        return L10n.tr(context, 'admin.moderation.listing_masked');
      case 'blocked':
        return L10n.tr(context, 'admin.moderation.listing_blocked');
      case 'pending':
        return L10n.tr(
          context,
          'admin.moderation.deletion_pending',
          fallback: 'En attente',
        );
      case 'processing':
        return L10n.tr(
          context,
          'admin.moderation.deletion_processing',
          fallback: 'En traitement',
        );
      case 'completed':
        return L10n.tr(
          context,
          'admin.moderation.deletion_completed',
          fallback: 'Clôturée',
        );
      case 'rejected':
        return L10n.tr(
          context,
          'admin.moderation.deletion_rejected',
          fallback: 'Rejetée',
        );
      case 'cancelled':
        return L10n.tr(
          context,
          'admin.moderation.deletion_cancelled',
          fallback: 'Annulée',
        );
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
      case 'approved':
        return Colors.green;
      case 'suspended':
      case 'masked':
        return Colors.orange;
      case 'banned':
      case 'blocked':
        return Colors.red;
      case 'pending':
        return Colors.blueGrey;
      case 'processing':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.blueGrey;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildSearchBox() {
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: L10n.tr(context, 'admin.moderation.search_hint'),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _searchCtrl.clear(),
              ),
      ),
    );
  }

  Widget _buildUsersTab() {
    final users = _filteredUsers;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatusFilter(
          selected: _userStatusFilter,
          onSelected: (value) => setState(() => _userStatusFilter = value),
          values: const ['all', 'active', 'suspended', 'banned'],
        ),
        const SizedBox(height: 12),
        if (users.isEmpty)
          Text(L10n.tr(context, 'admin.moderation.empty_users'))
        else
          ...users.map((u) {
            final id = u['id']?.toString() ?? '';
            final status = (u['status']?.toString() ?? 'active').toLowerCase();
            final email = u['email']?.toString() ?? '-';
            final role = u['role']?.toString() ?? 'buyer';
            final fullName = u['full_name']?.toString();
            final createdAt = _parseDate(u['created_at']);
            return Card(
              child: ListTile(
                title: Text(email),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (fullName != null && fullName.trim().isNotEmpty)
                      Text(fullName),
                    Text('$role - ${_statusLabel(status)}'),
                    if (createdAt != null)
                      Text(
                        L10n.tr(
                          context,
                          'admin.moderation.created_at',
                          params: {'date': _dateFmt.format(createdAt)},
                        ),
                      ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: L10n.tr(context, 'admin.moderation.action_user'),
                  onSelected: (value) => _setUserStatus(id, value),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'active',
                      child: Text(
                        L10n.tr(context, 'admin.moderation.status_active'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'suspended',
                      child: Text(
                        L10n.tr(context, 'admin.moderation.status_suspended'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'banned',
                      child: Text(
                        L10n.tr(context, 'admin.moderation.status_banned'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildListingsTab() {
    final listings = _filteredListings;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatusFilter(
          selected: _listingStatusFilter,
          onSelected: (value) => setState(() => _listingStatusFilter = value),
          values: const ['all', 'approved', 'masked', 'blocked'],
        ),
        const SizedBox(height: 12),
        if (listings.isEmpty)
          Text(L10n.tr(context, 'admin.moderation.empty_listings'))
        else
          ...listings.map((p) {
            final id = (p['id'] as num?)?.toInt();
            final title = p['title']?.toString() ?? '-';
            final status = (p['moderation_status']?.toString() ?? 'approved')
                .toLowerCase();
            final reason = p['moderation_reason']?.toString();
            final ownerId = p['owner_id']?.toString() ?? '';
            final updatedAt = _parseDate(p['moderation_updated_at']);
            return Card(
              child: ListTile(
                title: Text('#${id ?? '-'} - $title'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.tr(
                        context,
                        'admin.moderation.owner',
                        params: {'id': ownerId},
                      ),
                    ),
                    if (reason != null && reason.trim().isNotEmpty)
                      Text(
                        L10n.tr(
                          context,
                          'admin.moderation.reason',
                          params: {'reason': reason},
                        ),
                      ),
                    if (updatedAt != null)
                      Text(
                        L10n.tr(
                          context,
                          'admin.moderation.updated_at',
                          params: {'date': _dateFmt.format(updatedAt)},
                        ),
                      ),
                  ],
                ),
                trailing: id == null
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: L10n.tr(
                          context,
                          'admin.moderation.action_listing',
                        ),
                        onSelected: (value) => _setListingStatus(id, value),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'approved',
                            child: Text(
                              L10n.tr(
                                context,
                                'admin.moderation.listing_approved',
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'masked',
                            child: Text(
                              L10n.tr(
                                context,
                                'admin.moderation.listing_masked',
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'blocked',
                            child: Text(
                              L10n.tr(
                                context,
                                'admin.moderation.listing_blocked',
                              ),
                            ),
                          ),
                        ],
                        child: _buildStatusChip(
                          _statusLabel(status),
                          _statusColor(status),
                        ),
                      ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildReportsTab() {
    final reports = _filteredReports;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                L10n.tr(
                  context,
                  'admin.moderation.queue_hint',
                  params: {
                    'count': _reportsThreshold.toString(),
                    'days': _reportsWindowDays.toString(),
                  },
                ),
              ),
            ),
            Switch(
              value: _reportsPriorityOnly,
              onChanged: (value) =>
                  setState(() => _reportsPriorityOnly = value),
            ),
          ],
        ),
        Text(
          _reportsPriorityOnly
              ? L10n.tr(context, 'admin.moderation.filter_priority')
              : L10n.tr(context, 'admin.moderation.filter_all'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (reports.isEmpty)
          Text(L10n.tr(context, 'admin.moderation.empty_reports'))
        else
          ...reports.map((item) {
            final status = item.moderationStatus.toLowerCase();
            final isPriority = item.uniqueReporters >= _reportsThreshold;
            return Card(
              child: ListTile(
                title: Text('#${item.productId} - ${item.title}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.tr(
                        context,
                        'admin.moderation.owner',
                        params: {'id': item.ownerId},
                      ),
                    ),
                    Text(
                      L10n.tr(
                        context,
                        'admin.moderation.reports_count',
                        params: {'count': item.totalReports.toString()},
                      ),
                    ),
                    Text(
                      L10n.tr(
                        context,
                        'admin.moderation.unique_reporters',
                        params: {'count': item.uniqueReporters.toString()},
                      ),
                    ),
                    if (item.lastReportedAt != null)
                      Text(
                        L10n.tr(
                          context,
                          'admin.moderation.last_report',
                          params: {
                            'date': _dateFmt.format(item.lastReportedAt!),
                          },
                        ),
                      ),
                    if (item.sampleReason != null &&
                        item.sampleReason!.trim().isNotEmpty)
                      Text(
                        L10n.tr(
                          context,
                          'admin.moderation.reason',
                          params: {'reason': item.sampleReason!},
                        ),
                      ),
                  ],
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    if (isPriority)
                      Icon(
                        Icons.priority_high,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    if (item.ownerId.isNotEmpty)
                      PopupMenuButton<String>(
                        tooltip: L10n.tr(
                          context,
                          'admin.moderation.action_user',
                        ),
                        onSelected: (value) =>
                            _setUserStatus(item.ownerId, value),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'active',
                            child: Text(
                              L10n.tr(
                                context,
                                'admin.moderation.status_active',
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'suspended',
                            child: Text(
                              L10n.tr(
                                context,
                                'admin.moderation.status_suspended',
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'banned',
                            child: Text(
                              L10n.tr(
                                context,
                                'admin.moderation.status_banned',
                              ),
                            ),
                          ),
                        ],
                      ),
                    PopupMenuButton<String>(
                      tooltip: L10n.tr(
                        context,
                        'admin.moderation.action_listing',
                      ),
                      onSelected: (value) =>
                          _setListingStatus(item.productId, value),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'approved',
                          child: Text(
                            L10n.tr(
                              context,
                              'admin.moderation.listing_approved',
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'masked',
                          child: Text(
                            L10n.tr(context, 'admin.moderation.listing_masked'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'blocked',
                          child: Text(
                            L10n.tr(
                              context,
                              'admin.moderation.listing_blocked',
                            ),
                          ),
                        ),
                      ],
                      child: _buildStatusChip(
                        _statusLabel(status),
                        _statusColor(status),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildDeletionRequestsTab() {
    final requests = _filteredDeletionRequests;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatusFilter(
          selected: _deletionStatusFilter,
          onSelected: (value) => setState(() => _deletionStatusFilter = value),
          values: const [
            'all',
            'pending',
            'processing',
            'completed',
            'rejected',
            'cancelled',
          ],
        ),
        const SizedBox(height: 12),
        if (requests.isEmpty)
          Text(
            L10n.tr(
              context,
              'admin.moderation.empty_deletion_requests',
              fallback: 'Aucune demande de suppression.',
            ),
          )
        else
          ...requests.map((item) {
            return Card(
              child: ListTile(
                title: Text(item.email),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((item.userFullName ?? '').trim().isNotEmpty)
                      Text(item.userFullName!.trim()),
                    Text(
                      L10n.tr(
                        context,
                        'admin.moderation.created_at',
                        params: {'date': _dateFmt.format(item.requestedAt)},
                      ),
                    ),
                    Text(
                      L10n.tr(
                        context,
                        'admin.moderation.current_account_status',
                        fallback: 'Compte: {status}',
                        params: {'status': _statusLabel(item.userStatus)},
                      ),
                    ),
                    if ((item.reason ?? '').trim().isNotEmpty)
                      Text(
                        L10n.tr(
                          context,
                          'admin.moderation.reason',
                          params: {'reason': item.reason!.trim()},
                        ),
                      ),
                    if ((item.adminNote ?? '').trim().isNotEmpty)
                      Text(
                        L10n.tr(
                          context,
                          'admin.moderation.deletion_note_value',
                          fallback: 'Note admin: {note}',
                          params: {'note': item.adminNote!.trim()},
                        ),
                      ),
                    if (item.processedAt != null)
                      Text(
                        L10n.tr(
                          context,
                          'admin.moderation.updated_at',
                          params: {'date': _dateFmt.format(item.processedAt!)},
                        ),
                      ),
                  ],
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    _buildStatusChip(
                      _statusLabel(item.status),
                      _statusColor(item.status),
                    ),
                    PopupMenuButton<String>(
                      tooltip: L10n.tr(context, 'admin.moderation.action_user'),
                      onSelected: (value) async {
                        switch (value) {
                          case 'processing':
                            await _promptDeletionRequestAction(
                              item,
                              nextStatus: 'processing',
                              userAction: 'none',
                              title: L10n.tr(
                                context,
                                'admin.moderation.deletion_mark_processing',
                                fallback: 'Passer en traitement',
                              ),
                            );
                            break;
                          case 'suspend':
                            await _promptDeletionRequestAction(
                              item,
                              nextStatus: 'processing',
                              userAction: 'suspend',
                              title: L10n.tr(
                                context,
                                'admin.moderation.deletion_suspend_account',
                                fallback:
                                    'Restreindre temporairement le compte',
                              ),
                            );
                            break;
                          case 'activate':
                            await _promptDeletionRequestAction(
                              item,
                              nextStatus: item.status,
                              userAction: 'activate',
                              title: L10n.tr(
                                context,
                                'admin.moderation.deletion_restore_account',
                                fallback: 'Réactiver le compte',
                              ),
                            );
                            break;
                          case 'rejected':
                            await _promptDeletionRequestAction(
                              item,
                              nextStatus: 'rejected',
                              userAction: 'none',
                              title: L10n.tr(
                                context,
                                'admin.moderation.deletion_reject',
                                fallback: 'Rejeter la demande',
                              ),
                            );
                            break;
                          case 'completed':
                            await _promptDeletionRequestAction(
                              item,
                              nextStatus: 'completed',
                              userAction: 'none',
                              title: L10n.tr(
                                context,
                                'admin.moderation.deletion_complete',
                                fallback: 'Clôturer la demande',
                              ),
                            );
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'processing',
                          child: Text(
                            L10n.tr(
                              context,
                              'admin.moderation.deletion_mark_processing',
                              fallback: 'Passer en traitement',
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'suspend',
                          child: Text(
                            L10n.tr(
                              context,
                              'admin.moderation.deletion_suspend_account',
                              fallback: 'Restreindre temporairement le compte',
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'activate',
                          child: Text(
                            L10n.tr(
                              context,
                              'admin.moderation.deletion_restore_account',
                              fallback: 'Réactiver le compte',
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'rejected',
                          child: Text(
                            L10n.tr(
                              context,
                              'admin.moderation.deletion_reject',
                              fallback: 'Rejeter la demande',
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'completed',
                          child: Text(
                            L10n.tr(
                              context,
                              'admin.moderation.deletion_complete',
                              fallback: 'Clôturer la demande',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildSearchBox(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildUsersTab(),
                _buildListingsTab(),
                _buildReportsTab(),
                _buildDeletionRequestsTab(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final usersCount = _filteredUsers.length;
    final listingsCount = _filteredListings.length;
    final reportsCount = _filteredReports.length;
    final deletionCount = _filteredDeletionRequests.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr(context, 'admin.moderation.title')),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(
              text:
                  '${L10n.tr(context, 'admin.moderation.users')} ($usersCount)',
            ),
            Tab(
              text:
                  '${L10n.tr(context, 'admin.moderation.listings')} ($listingsCount)',
            ),
            Tab(
              text:
                  '${L10n.tr(context, 'admin.moderation.reports')} ($reportsCount)',
            ),
            Tab(
              text:
                  '${L10n.tr(context, 'admin.moderation.deletion_requests', fallback: 'Demandes suppression')} ($deletionCount)',
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }
}

class _ReportAccumulator {
  _ReportAccumulator({
    required this.productId,
    required this.title,
    required this.ownerId,
    required this.moderationStatus,
    required this.moderationReason,
  });

  final int productId;
  final String title;
  final String ownerId;
  final String moderationStatus;
  final String? moderationReason;
  final Set<String> reporters = <String>{};
  int totalReports = 0;
  DateTime? lastReportedAt;
  String? sampleReason;

  _ReportQueueItem toItem() {
    return _ReportQueueItem(
      productId: productId,
      title: title,
      ownerId: ownerId,
      moderationStatus: moderationStatus,
      moderationReason: moderationReason,
      uniqueReporters: reporters.length,
      totalReports: totalReports,
      lastReportedAt: lastReportedAt,
      sampleReason: sampleReason,
    );
  }
}

class _ReportQueueItem {
  const _ReportQueueItem({
    required this.productId,
    required this.title,
    required this.ownerId,
    required this.moderationStatus,
    required this.moderationReason,
    required this.uniqueReporters,
    required this.totalReports,
    required this.lastReportedAt,
    required this.sampleReason,
  });

  final int productId;
  final String title;
  final String ownerId;
  final String moderationStatus;
  final String? moderationReason;
  final int uniqueReporters;
  final int totalReports;
  final DateTime? lastReportedAt;
  final String? sampleReason;
}

class _DeletionRequestItem {
  const _DeletionRequestItem({
    required this.id,
    required this.userId,
    required this.email,
    required this.status,
    required this.requestedAt,
    required this.userStatus,
    this.reason,
    this.processedAt,
    this.adminNote,
    this.userEmail,
    this.userFullName,
  });

  final int id;
  final String userId;
  final String email;
  final String status;
  final DateTime requestedAt;
  final DateTime? processedAt;
  final String userStatus;
  final String? reason;
  final String? adminNote;
  final String? userEmail;
  final String? userFullName;

  factory _DeletionRequestItem.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?)?.cast<String, dynamic>();
    final requestedAt =
        DateTime.tryParse(json['requested_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now();
    return _DeletionRequestItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: json['user_id']?.toString() ?? '',
      email:
          json['email']?.toString() ??
          user?['email']?.toString() ??
          json['user_id']?.toString() ??
          '-',
      status: (json['status']?.toString() ?? 'pending').toLowerCase(),
      requestedAt: requestedAt,
      processedAt: DateTime.tryParse(
        json['processed_at']?.toString() ?? '',
      )?.toLocal(),
      userStatus: (user?['status']?.toString() ?? 'active').toLowerCase(),
      reason: json['reason']?.toString(),
      adminNote: json['admin_note']?.toString(),
      userEmail: user?['email']?.toString(),
      userFullName: user?['full_name']?.toString(),
    );
  }
}
