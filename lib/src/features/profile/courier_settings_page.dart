// ignore_for_file: deprecated_member_use
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CourierSettingsPage extends StatefulWidget {
  const CourierSettingsPage({super.key});

  @override
  State<CourierSettingsPage> createState() => _CourierSettingsPageState();
}

class _CourierSettingsPageState extends State<CourierSettingsPage> {
  final _apiKeyCtrl = TextEditingController();
  final _apiSecretCtrl = TextEditingController();
  final _senderCtrl = TextEditingController();

  String _selectedCourierName = ShippingService.couriers.first['name']!;
  final Map<String, Map<String, String?>> _localCache = {};
  bool _saving = false;
  bool _validating = false;
  bool _loading = true;
  bool _deleting = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _apiSecretCtrl.dispose();
    _senderCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings({bool keepIfMissing = false}) async {
    setState(() => _loading = true);
    try {
      final row = await ShippingService().loadSellerDeliverySettingsByName(
        _selectedCourierName,
      );
      _error = null;
      if (row != null) {
        _apiKeyCtrl.text = row['api_key']?.toString() ?? '';
        _apiSecretCtrl.text = row['api_secret']?.toString() ?? '';
        _senderCtrl.text = row['sender_id']?.toString() ?? '';
        _localCache[_selectedCourierName] = {
          'api_key': _apiKeyCtrl.text,
          'api_secret': _apiSecretCtrl.text,
          'sender_id': _senderCtrl.text,
        };
      } else {
        final cached = keepIfMissing ? _localCache[_selectedCourierName] : null;
        if (cached != null) {
          _apiKeyCtrl.text = cached['api_key'] ?? '';
          _apiSecretCtrl.text = cached['api_secret'] ?? '';
          _senderCtrl.text = cached['sender_id'] ?? '';
        } else {
          _apiKeyCtrl.clear();
          _apiSecretCtrl.clear();
          _senderCtrl.clear();
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.tr(context, 'courier_settings.login_required')),
        ),
      );
      return;
    }

    String apiKey;
    String apiSecret;
    String? sender;
    try {
      final lower = _selectedCourierName.toLowerCase();
      final isEcotrack = lower.contains('ecotrack');
      final isZrExpress = ShippingService.isZrExpressCourier(
        courierName: _selectedCourierName,
      );
      final isGuepex = ShippingService.isGuepexCourier(
        courierName: _selectedCourierName,
      );
      apiKey = InputSanitizer.sanitizeText(
        _apiKeyCtrl.text,
        maxLength: (isEcotrack || isZrExpress || isGuepex) ? 200 : 120,
      );
      apiSecret = isEcotrack
          ? InputSanitizer.sanitizeOptionalText(
                  _apiSecretCtrl.text,
                  maxLength: 120,
                ) ??
                ''
          : InputSanitizer.sanitizeText(
              _apiSecretCtrl.text,
              maxLength: (isZrExpress || isGuepex) ? 200 : 120,
            );
      sender = InputSanitizer.sanitizeOptionalText(
        _senderCtrl.text,
        maxLength: 80,
      );
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }

    setState(() {
      _validating = true;
      _saving = false;
      _error = null;
      _status = null;
    });
    final validation = await ShippingService().validateCredentialsDetailed(
      courierName: _selectedCourierName,
      apiKey: apiKey,
      apiSecret: apiSecret,
      senderId: sender,
    );
    final valid = validation['ok'] == true;
    if (!valid) {
      final message = validation['message']?.toString();
      if (!mounted) return;
      setState(() {
        _validating = false;
        _saving = false;
        _error = message == null || message.isEmpty
            ? L10n.tr(context, 'courier_settings.error_invalid_token')
            : L10n.tr(
                context,
                'courier_settings.error_invalid_token_detail',
                params: {'error': message},
              );
        _status = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message == null || message.isEmpty
                ? L10n.tr(context, 'courier_settings.snack_invalid_token')
                : L10n.tr(
                    context,
                    'courier_settings.snack_invalid_token_detail',
                    params: {'error': message},
                  ),
          ),
        ),
      );
      return;
    }

    setState(() {
      _validating = false;
      _saving = true;
      if (valid) {
        _status = L10n.tr(context, 'courier_settings.status_valid');
      }
    });
    await ShippingService().saveSellerDeliverySettingsByName(
      courierName: _selectedCourierName,
      apiKey: apiKey,
      apiSecret: apiSecret,
      senderId: sender,
    );
    _localCache[_selectedCourierName] = {
      'api_key': apiKey,
      'api_secret': apiSecret,
      'sender_id': sender,
    };
    if (!mounted) return;
    setState(() => _saving = false);
    await _loadSettings(keepIfMissing: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.tr(context, 'courier_settings.snack_saved'))),
    );
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ShippingService().deleteSellerDeliverySettingsByName(
        _selectedCourierName,
      );
      _apiKeyCtrl.clear();
      _apiSecretCtrl.clear();
      _senderCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.tr(context, 'courier_settings.snack_deleted')),
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lower = _selectedCourierName.toLowerCase();
    final isEcotrack = lower.contains('ecotrack');
    final isZrExpress = ShippingService.isZrExpressCourier(
      courierName: _selectedCourierName,
    );
    final isGuepex = ShippingService.isGuepexCourier(
      courierName: _selectedCourierName,
    );
    return Scaffold(
      appBar: AppBar(title: Text(L10n.tr(context, 'courier_settings.title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedCourierName,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: L10n.tr(
                        context,
                        'courier_settings.courier_label',
                      ),
                      prefixIcon: const Icon(Icons.local_shipping_outlined),
                    ),
                    items: ShippingService.couriers
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['name'],
                            child: Text(
                              c['name'] ?? '',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _selectedCourierName = v);
                      await _loadSettings();
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _apiKeyCtrl,
                    decoration: InputDecoration(
                      labelText: isEcotrack
                          ? L10n.tr(context, 'courier_settings.token_label')
                          : isGuepex
                          ? L10n.tr(context, 'courier_settings.guepex_id_label')
                          : isZrExpress
                          ? L10n.tr(
                              context,
                              'courier_settings.zrexpress_key_label',
                            )
                          : L10n.tr(context, 'courier_settings.api_key_label'),
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                    ),
                  ),
                  if (!isEcotrack) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiSecretCtrl,
                      decoration: InputDecoration(
                        labelText: isGuepex
                            ? L10n.tr(
                                context,
                                'courier_settings.guepex_token_label',
                              )
                            : isZrExpress
                            ? L10n.tr(
                                context,
                                'courier_settings.zrexpress_tenant_label',
                              )
                            : L10n.tr(context, 'courier_settings.secret_label'),
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _senderCtrl,
                    decoration: InputDecoration(
                      labelText: L10n.tr(
                        context,
                        'courier_settings.sender_label',
                      ),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),
                  if (kIsWeb) ...[
                    const SizedBox(height: 8),
                    Text(
                      L10n.tr(context, 'courier_settings.web_notice'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _status!,
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _saving || _validating ? null : _save,
                    icon: _validating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _saving
                          ? L10n.tr(context, 'courier_settings.saving')
                          : _validating
                          ? L10n.tr(context, 'courier_settings.validating')
                          : L10n.tr(context, 'courier_settings.save'),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _deleting || _saving || _validating
                        ? null
                        : _delete,
                    icon: _deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(
                      _deleting
                          ? L10n.tr(context, 'courier_settings.deleting')
                          : L10n.tr(context, 'courier_settings.delete'),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
