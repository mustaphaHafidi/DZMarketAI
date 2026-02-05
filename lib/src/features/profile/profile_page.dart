// ignore_for_file: deprecated_member_use
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/orders/shipments_dashboard_page.dart';
import 'package:dzmarket/src/features/orders/seller_orders_page.dart';
import 'package:dzmarket/src/features/profile/courier_settings_page.dart';
import 'package:dzmarket/src/features/profile/my_listings_page.dart';
import 'package:dzmarket/src/features/profile/seller_dashboard_page.dart';
import 'package:dzmarket/src/models/profile.dart';
import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/location_service.dart';
import 'package:dzmarket/src/services/storage_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Unified profile page (buyer/seller) with editable fields and seller tools.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _wilayaCtrl = TextEditingController();
  final _dairaCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _isSeller = false;
  bool _isPublic = true;
  String? _lang = 'fr';
  double? _lat;
  double? _lng;
  Profile? _profile;
  String? _error;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _phoneCtrl.dispose();
    _wilayaCtrl.dispose();
    _dairaCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _error = 'Connectez-vous pour voir votre profil.';
          _loading = false;
        });
        return;
      }
      await AuthService.instance.ensureProfileExists();
      final p = await AuthService.instance.fetchProfile();
      if (!mounted) return;
      if (p == null) {
        setState(() {
          _error = 'Profil introuvable';
          _loading = false;
        });
        return;
      }
      _profile = p;
      _nameCtrl.text = p.fullName ?? '';
      _bioCtrl.text = p.bio ?? '';
      _phoneCtrl.text = p.phone ?? '';
      _wilayaCtrl.text = p.wilaya ?? '';
      _dairaCtrl.text = p.daira ?? '';
      _avatarUrl = p.avatarUrl;
      _isSeller = p.isSeller || p.role == UserRole.seller;
      _isPublic = p.isPublic;
      _lang = p.lang ?? LocaleService.instance.locale.value?.languageCode ?? 'fr';
      _lat = p.locationLat;
      _lng = p.locationLng;
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fullName =
          InputSanitizer.sanitizeOptionalText(_nameCtrl.text, maxLength: 80);
      final avatarUrl = InputSanitizer.safeUrl(_avatarUrl);
      final phone = InputSanitizer.sanitizePhone(_phoneCtrl.text);
      final wilaya =
          InputSanitizer.sanitizeOptionalText(_wilayaCtrl.text, maxLength: 60);
      final daira =
          InputSanitizer.sanitizeOptionalText(_dairaCtrl.text, maxLength: 60);
      final bio = InputSanitizer.sanitizeOptionalText(
        _bioCtrl.text,
        maxLength: 240,
        allowNewlines: true,
      );
      final lang = InputSanitizer.sanitizeOptionalText(_lang, maxLength: 8);
      await AuthService.instance.updateProfile(
        id: user.id,
        fullName: fullName,
        avatarUrl: avatarUrl,
        phone: phone,
        wilaya: wilaya,
        daira: daira,
        locationLat: _lat,
        locationLng: _lng,
        bio: bio,
        isPublic: _isPublic,
        lang: lang,
        isSeller: _isSeller,
        role: _isSeller ? 'seller' : 'buyer',
      );
      await LocaleService.instance.setLocale(_lang);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis ? jour')),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _saving = true);
    final data = await LocationService.instance.fetchLocation();
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (data != null) {
        _lat = data.latitude;
        _lng = data.longitude;
        if (data.wilaya != null) _wilayaCtrl.text = data.wilaya!;
        if (data.daira != null) _dairaCtrl.text = data.daira!;
      }
    });
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.image,
    );
    final file = result?.files.first;
    if (file?.bytes == null) return;
    setState(() => _saving = true);
    try {
      final urls = await StorageService().uploadImages(
        files: [file!.bytes!],
        fileNames: [file.name],
        bucket: 'avatars',
      );
      if (!mounted) return;
      setState(() {
        _avatarUrl = urls.isNotEmpty ? urls.first : null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _removeAvatar() {
    setState(() {
      _avatarUrl = null;
    });
  }

  String _initials() {
    final raw = _nameCtrl.text.trim();
    if (raw.isEmpty) return '?';
    final parts = raw.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final first = parts.first;
      final last = parts.last;
      final a = first.isNotEmpty ? first[0] : '';
      final b = last.isNotEmpty ? last[0] : '';
      final combined = '$a$b'.toUpperCase();
      return combined.isEmpty ? '?' : combined;
    }
    final single = parts.first;
    final letters = single.length >= 2 ? single.substring(0, 2) : single;
    return letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadProfile,
                child: const Text('Recharger'),
              ),
            ],
          ),
        ),
      );
    }

    final safeAvatar = InputSanitizer.safeUrl(_avatarUrl);
    final isSeller = _isSeller;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProfile,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                      backgroundImage: safeAvatar != null
                          ? CachedNetworkImageProvider(
                              safeAvatar,
                              imageRenderMethodForWeb:
                                  ImageRenderMethodForWeb.HtmlImage,
                            )
                          : null,
                      child: safeAvatar == null
                          ? Text(
                              _initials(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _profile?.email ?? '',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isSeller ? 'Mode vendeur' : 'Mode acheteur',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : _useMyLocation,
                      icon: const Icon(Icons.my_location_outlined),
                      tooltip: 'Utiliser ma position',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nom complet',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _saving ? null : _pickAvatar,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Importer une photo'),
                            ),
                            const SizedBox(width: 12),
                            if (safeAvatar != null)
                              TextButton(
                                onPressed: _saving ? null : _removeAvatar,
                                child: const Text('Supprimer'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _bioCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Bio',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'T?l?phone',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _wilayaCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Wilaya',
                                  prefixIcon: Icon(Icons.map_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _dairaCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Da?ra',
                                  prefixIcon: Icon(Icons.place_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _lang,
                          decoration: const InputDecoration(
                            labelText: 'Langue',
                            prefixIcon: Icon(Icons.language_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'fr', child: Text('Fran?ais')),
                            DropdownMenuItem(value: 'ar', child: Text('Arabe (Alg?rie)')),
                          ],
                          onChanged: (v) => setState(() => _lang = v ?? 'fr'),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          value: _isPublic,
                          onChanged: (v) => setState(() => _isPublic = v),
                          title: const Text('Profil public'),
                          subtitle: const Text('Visible par les acheteurs'),
                        ),
                        SwitchListTile(
                          value: _isSeller,
                          onChanged: (v) => setState(() => _isSeller = v),
                          title: const Text('Mode vendeur'),
                          subtitle: const Text('Affiche les outils vendeur'),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  await AuthService.instance.signOut();
                                  if (context.mounted) {
                                    context.go('/sign-in');
                                  }
                                },
                          icon: const Icon(Icons.logout),
                          label: const Text('Déconnexion'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.error,
                            foregroundColor: Theme.of(context).colorScheme.onError,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Voir mon profil public'),
                        subtitle: const Text('Aper?u de ce que voient les autres'),
                        onTap: () {},
                      ),
                      if (isSeller) const Divider(height: 1),
                      if (isSeller)
                        ListTile(
                          leading: const Icon(Icons.sell_outlined),
                          title: const Text('Mes ventes'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SellerOrdersPage()),
                          ),
                        ),
                      if (isSeller) const Divider(height: 1),
                      if (isSeller)
                        ListTile(
                          leading: const Icon(Icons.analytics_outlined),
                          title: const Text('Tableau de bord'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SellerDashboardPage(),
                            ),
                          ),
                        ),
                      if (isSeller) const Divider(height: 1),
                      if (isSeller)
                        ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: const Text('Mes annonces'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const MyListingsPage()),
                          ),
                        ),
                      if (isSeller) const Divider(height: 1),
                      if (isSeller)
                        ListTile(
                          leading: const Icon(Icons.local_shipping_outlined),
                          title: const Text('Tableau de livraisons'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ShipmentsDashboardPage()),
                          ),
                        ),
                      if (isSeller) const Divider(height: 1),
                      if (isSeller)
                        ListTile(
                          leading: const Icon(Icons.settings_applications_outlined),
                          title: const Text('Param?tres transporteurs'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const CourierSettingsPage()),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Geo: ${_lat?.toStringAsFixed(4) ?? "--"}, ${_lng?.toStringAsFixed(4) ?? "--"}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



