// ignore_for_file: deprecated_member_use
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
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

  Future<void> _loadSettings() async {
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
      } else {
        _apiKeyCtrl.clear();
        _apiSecretCtrl.clear();
        _senderCtrl.clear();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connectez-vous pour enregistrer vos transporteurs.'),
        ),
      );
      return;
    }

    String apiKey;
    String apiSecret;
    String? sender;
    try {
      final isEcotrack = _selectedCourierName.toLowerCase().contains('ecotrack');
      apiKey = InputSanitizer.sanitizeText(
        _apiKeyCtrl.text,
        maxLength: isEcotrack ? 200 : 120,
      );
      apiSecret = isEcotrack
          ? InputSanitizer.sanitizeOptionalText(_apiSecretCtrl.text, maxLength: 120) ?? ''
          : InputSanitizer.sanitizeText(_apiSecretCtrl.text, maxLength: 120);
      sender = InputSanitizer.sanitizeOptionalText(_senderCtrl.text, maxLength: 80);
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
        _error = message == null || message.isEmpty
            ? 'Token invalide'
            : 'Token invalide: $message';
        _status = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message == null || message.isEmpty
                ? 'Token invalide. Verifiez et reessayez.'
                : 'Token invalide ou non autorise: $message',
          ),
        ),
      );
      return;
    }

    setState(() {
      _validating = false;
      _saving = true;
      _status = 'Token valide';
    });
    await ShippingService().saveSellerDeliverySettingsByName(
      courierName: _selectedCourierName,
      apiKey: apiKey,
      apiSecret: apiSecret,
      senderId: sender,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Compte transporteur enregistré.')),
    );
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ShippingService().deleteSellerDeliverySettingsByName(_selectedCourierName);
      _apiKeyCtrl.clear();
      _apiSecretCtrl.clear();
      _senderCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte transporteur supprimé.')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEcotrack = _selectedCourierName.toLowerCase().contains('ecotrack');
    return Scaffold(
      appBar: AppBar(title: const Text('Comptes transporteurs')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedCourierName,
                    decoration: const InputDecoration(
                      labelText: 'Transporteur',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                    items: ShippingService.couriers
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['name'],
                            child: Text(c['name'] ?? ''),
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
                      labelText: isEcotrack ? 'Token Ecotrack' : 'API key / ID',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                    ),
                  ),
                  if (!isEcotrack) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiSecretCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Token / secret',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _senderCtrl,
                    decoration: const InputDecoration(
                      labelText: "Nom expéditeur",
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  if (kIsWeb) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Validation API cote serveur.',
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
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                          ? 'Enregistrement...'
                          : _validating
                              ? 'Validation...'
                              : 'Enregistrer',
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
                    onPressed: _deleting || _saving || _validating ? null : _delete,
                    icon: _deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(_deleting ? 'Suppression...' : 'Supprimer ce transporteur'),
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






