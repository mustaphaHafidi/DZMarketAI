// ignore_for_file: deprecated_member_use
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/admin/app_errors_page.dart';
import 'package:dzmarket/src/features/admin/moderation_admin_page.dart';
import 'package:dzmarket/src/features/orders/shipments_dashboard_page.dart';
import 'package:dzmarket/src/features/orders/seller_orders_page.dart';
import 'package:dzmarket/src/features/profile/courier_settings_page.dart';
import 'package:dzmarket/src/features/profile/my_listings_page.dart';
import 'package:dzmarket/src/features/profile/seller_dashboard_page.dart';
import 'package:dzmarket/src/models/profile.dart';
import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/location_data_service.dart';
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
  bool _loadingLocations = false;
  String? _locationLoadError;
  List<Map<String, String>> _wilayas = const [];
  List<Map<String, String>> _communes = const [];
  String? _selectedWilayaCode;
  String? _selectedCommuneId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadLocations();
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
      final localeCode =
          LocaleService.instance.locale.value?.languageCode ?? 'fr';
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _error = L10n.trLocale(localeCode, 'profile.login_required');
          _loading = false;
        });
        return;
      }
      await AuthService.instance.ensureProfileExists();
      final p = await AuthService.instance.fetchProfile();
      if (!mounted) return;
      if (p == null) {
        setState(() {
          _error = L10n.trLocale(localeCode, 'profile.not_found');
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
      _lang =
          p.lang ?? LocaleService.instance.locale.value?.languageCode ?? 'fr';
      _lat = p.locationLat;
      _lng = p.locationLng;
      _syncLocationSelectionFromText();
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
      final fullName = InputSanitizer.sanitizeOptionalText(
        _nameCtrl.text,
        maxLength: 80,
      );
      final avatarUrl = InputSanitizer.safeUrl(_avatarUrl);
      final phone = InputSanitizer.sanitizePhone(_phoneCtrl.text);
      final wilaya = InputSanitizer.sanitizeOptionalText(
        _wilayaCtrl.text,
        maxLength: 60,
      );
      final daira = InputSanitizer.sanitizeOptionalText(
        _dairaCtrl.text,
        maxLength: 60,
      );
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
        role: _profileRoleString(_profile?.role, _isSeller),
      );
      await LocaleService.instance.setLocale(_lang);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.tr(context, 'profile.updated'))),
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

  Future<void> _loadLocations() async {
    setState(() {
      _loadingLocations = true;
      _locationLoadError = null;
    });
    final items = await LocationDataService.instance.fetchWilayas();
    if (!mounted) return;
    setState(() {
      _wilayas = items;
      _loadingLocations = false;
      if (items.isEmpty) {
        _locationLoadError = L10n.tr(context, 'listing.add.error_no_wilayas');
      }
    });
    _syncLocationSelectionFromText();
  }

  void _syncLocationSelectionFromText() {
    if (_wilayas.isEmpty) return;
    final wilayaText = _wilayaCtrl.text.trim().toLowerCase();
    if (wilayaText.isNotEmpty) {
      final match = _wilayas.firstWhere(
        (w) =>
            (w['name_fr'] ?? '').toLowerCase() == wilayaText ||
            (w['name_ar'] ?? '').toLowerCase() == wilayaText ||
            (w['code'] ?? '').toLowerCase() == wilayaText,
        orElse: () => const {},
      );
      final code = match['code'];
      if (code != null && code.isNotEmpty) {
        _selectedWilayaCode = code;
        _loadCommunes(code);
      }
    }
  }

  Future<void> _loadCommunes(String code) async {
    setState(() {
      _loadingLocations = true;
      _locationLoadError = null;
      _communes = const [];
    });
    final items = await LocationDataService.instance.fetchCommunes(code);
    if (!mounted) return;
    setState(() {
      _communes = items;
      _loadingLocations = false;
      if (items.isEmpty) {
        _locationLoadError = L10n.tr(context, 'listing.add.error_no_communes');
      }
    });
    _syncCommuneSelectionFromText();
  }

  String _profileRoleString(UserRole? role, bool isSeller) {
    switch (role) {
      case UserRole.superadmin:
        return 'superadmin';
      case UserRole.seller:
      case UserRole.buyer:
      case null:
        return isSeller ? 'seller' : 'buyer';
    }
  }

  void _syncCommuneSelectionFromText() {
    if (_communes.isEmpty) return;
    final communeText = _dairaCtrl.text.trim().toLowerCase();
    if (communeText.isEmpty) return;
    final match = _communes.firstWhere(
      (c) =>
          (c['name_fr'] ?? '').toLowerCase() == communeText ||
          (c['name_ar'] ?? '').toLowerCase() == communeText ||
          (c['id'] ?? '').toLowerCase() == communeText,
      orElse: () => const {},
    );
    final id = match['id'];
    if (id != null && id.isNotEmpty) {
      _selectedCommuneId = id;
    }
  }

  bool _hasArabicLetters(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }

  String _pickLocalizedName(BuildContext context, String fr, String ar) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    if (!isAr) return fr.isNotEmpty ? fr : ar;
    if (_hasArabicLetters(ar)) return ar;
    return fr.isNotEmpty ? fr : ar;
  }

  String _formatWilayaLabel(String code, String name) {
    final raw = code.trim();
    if (raw.isEmpty) return name;
    final numeric = int.tryParse(raw);
    final normalized = numeric != null ? raw.padLeft(2, '0') : raw;
    return '$normalized - $name';
  }

  String _wilayaLabel(BuildContext context) {
    final code = _selectedWilayaCode;
    if (code == null || code.isEmpty) {
      return L10n.tr(context, 'listing.add.select_wilaya');
    }
    final match = _wilayas.where((w) => w['code'] == code).toList();
    if (match.isEmpty) return code;
    final fr = match.first['name_fr'] ?? code;
    final ar = match.first['name_ar'] ?? fr;
    final name = _pickLocalizedName(context, fr, ar);
    return _formatWilayaLabel(code, name);
  }

  String _communeLabel(BuildContext context) {
    final id = _selectedCommuneId;
    if (id == null || id.isEmpty) {
      return L10n.tr(context, 'listing.add.select_commune');
    }
    final match = _communes.where((c) => c['id'] == id).toList();
    if (match.isEmpty) return id;
    final fr = match.first['name_fr'] ?? id;
    final ar = match.first['name_ar'] ?? fr;
    return _pickLocalizedName(context, fr, ar);
  }

  String _wilayaItemLabel(BuildContext context, Map<String, String> item) {
    final fr = item['name_fr'] ?? '';
    final ar = item['name_ar'] ?? fr;
    final name = _pickLocalizedName(context, fr, ar);
    final code = item['code'] ?? '';
    return _formatWilayaLabel(code, name);
  }

  String _communeItemLabel(BuildContext context, Map<String, String> item) {
    final fr = item['name_fr'] ?? '';
    final ar = item['name_ar'] ?? fr;
    return _pickLocalizedName(context, fr, ar);
  }

  Future<Map<String, String>?> _showLocationPicker({
    required BuildContext context,
    required String title,
    required List<Map<String, String>> items,
    required String Function(Map<String, String>) itemLabel,
  }) {
    final searchCtrl = TextEditingController();
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (sheetContext, setState) {
              final query = searchCtrl.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? items
                  : items.where((item) {
                      final label = itemLabel(item).toLowerCase();
                      final code = (item['code'] ?? '').toLowerCase();
                      return label.contains(query) || code.contains(query);
                    }).toList();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      title,
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: L10n.tr(sheetContext, 'common.search'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        return ListTile(
                          title: Text(itemLabel(item)),
                          onTap: () => Navigator.of(sheetContext).pop(item),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPickerField({
    required String label,
    required String value,
    required VoidCallback? onTap,
    required IconData icon,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          enabled: onTap != null,
        ),
        child: Row(
          children: [
            Expanded(child: Text(value)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
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
        if (data.wilaya != null) {
          _wilayaCtrl.text = data.wilaya!;
        }
        if (data.daira != null) {
          _dairaCtrl.text = data.daira!;
        }
      }
    });
    _syncLocationSelectionFromText();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
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
        appBar: AppBar(title: Text(L10n.tr(context, 'profile.title'))),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadProfile,
                child: Text(L10n.tr(context, 'common.reload')),
              ),
            ],
          ),
        ),
      );
    }

    final safeAvatar = InputSanitizer.safeUrl(_avatarUrl);
    final isSeller = _isSeller;
    final isSuperAdmin = _profile?.role == UserRole.superadmin;

    return Scaffold(
      appBar: AppBar(title: Text(L10n.tr(context, 'profile.title'))),
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
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
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
                            isSeller
                                ? L10n.tr(context, 'profile.mode_seller')
                                : L10n.tr(context, 'profile.mode_buyer'),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : _useMyLocation,
                      icon: const Icon(Icons.my_location_outlined),
                      tooltip: L10n.tr(context, 'profile.use_location'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            labelText: L10n.tr(context, 'profile.full_name'),
                            prefixIcon: const Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _saving ? null : _pickAvatar,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: Text(
                                L10n.tr(context, 'profile.photo_upload'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (safeAvatar != null)
                              TextButton(
                                onPressed: _saving ? null : _removeAvatar,
                                child: Text(L10n.tr(context, 'common.delete')),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _bioCtrl,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: L10n.tr(context, 'profile.bio'),
                            prefixIcon: const Icon(Icons.notes_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: L10n.tr(context, 'profile.phone'),
                            prefixIcon: const Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildPickerField(
                                label: L10n.tr(context, 'profile.wilaya'),
                                value: _wilayaLabel(context),
                                icon: Icons.map_outlined,
                                onTap: (_loadingLocations || _wilayas.isEmpty)
                                    ? null
                                    : () async {
                                        final selected =
                                            await _showLocationPicker(
                                              context: context,
                                              title: L10n.tr(
                                                context,
                                                'profile.wilaya',
                                              ),
                                              items: _wilayas,
                                              itemLabel: (item) =>
                                                  _wilayaItemLabel(
                                                    context,
                                                    item,
                                                  ),
                                            );
                                        if (!mounted || selected == null) {
                                          return;
                                        }
                                        final code = selected['code'] ?? '';
                                        setState(() {
                                          _selectedWilayaCode = code.isNotEmpty
                                              ? code
                                              : null;
                                          _wilayaCtrl.text =
                                              selected['name_fr'] ?? code;
                                          _selectedCommuneId = null;
                                          _dairaCtrl.text = '';
                                          _communes = const [];
                                        });
                                        if (code.isNotEmpty) {
                                          await _loadCommunes(code);
                                        }
                                      },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildPickerField(
                                label: L10n.tr(context, 'profile.daira'),
                                value: _communeLabel(context),
                                icon: Icons.place_outlined,
                                onTap:
                                    (_loadingLocations ||
                                        _selectedWilayaCode == null ||
                                        _communes.isEmpty)
                                    ? null
                                    : () async {
                                        final selected =
                                            await _showLocationPicker(
                                              context: context,
                                              title: L10n.tr(
                                                context,
                                                'profile.daira',
                                              ),
                                              items: _communes,
                                              itemLabel: (item) =>
                                                  _communeItemLabel(
                                                    context,
                                                    item,
                                                  ),
                                            );
                                        if (!mounted || selected == null) {
                                          return;
                                        }
                                        final communeId = selected['id'] ?? '';
                                        setState(() {
                                          _selectedCommuneId =
                                              communeId.isNotEmpty
                                              ? communeId
                                              : null;
                                          _dairaCtrl.text =
                                              selected['name_fr'] ??
                                              (communeId.isNotEmpty
                                                  ? communeId
                                                  : '');
                                        });
                                      },
                              ),
                            ),
                          ],
                        ),
                        if (_loadingLocations)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (_locationLoadError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _locationLoadError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _lang,
                          decoration: InputDecoration(
                            labelText: L10n.tr(context, 'profile.language'),
                            prefixIcon: const Icon(Icons.language_outlined),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'fr',
                              child: Text(L10n.tr(context, 'profile.lang_fr')),
                            ),
                            DropdownMenuItem(
                              value: 'ar',
                              child: Text(L10n.tr(context, 'profile.lang_ar')),
                            ),
                          ],
                          onChanged: (v) async {
                            final code = v ?? 'fr';
                            setState(() => _lang = code);
                            await LocaleService.instance.setLocale(code);
                          },
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          value: _isPublic,
                          onChanged: (v) => setState(() => _isPublic = v),
                          title: Text(L10n.tr(context, 'profile.public')),
                          subtitle: Text(
                            L10n.tr(context, 'profile.public_hint'),
                          ),
                        ),
                        SwitchListTile(
                          value: _isSeller,
                          onChanged: (v) => setState(() => _isSeller = v),
                          title: Text(L10n.tr(context, 'profile.seller_mode')),
                          subtitle: Text(
                            L10n.tr(context, 'profile.seller_mode_hint'),
                          ),
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
                          label: Text(L10n.tr(context, 'auth.sign_out')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onError,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _saving
                                ? L10n.tr(context, 'common.saving')
                                : L10n.tr(context, 'common.save'),
                          ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      if (isSuperAdmin) const Divider(height: 1),
                      if (isSuperAdmin)
                        ListTile(
                          leading: const Icon(
                            Icons.admin_panel_settings_outlined,
                          ),
                          title: Text(L10n.tr(context, 'admin.errors_title')),
                          subtitle: Text(
                            L10n.tr(context, 'admin.errors_subtitle'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AppErrorsPage(),
                            ),
                          ),
                        ),
                      if (isSuperAdmin) const Divider(height: 1),
                      if (isSuperAdmin)
                        ListTile(
                          leading: const Icon(Icons.gpp_good_outlined),
                          title: Text(
                            L10n.tr(context, 'admin.moderation.title'),
                          ),
                          subtitle: Text(
                            L10n.tr(context, 'admin.moderation.subtitle'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ModerationAdminPage(),
                            ),
                          ),
                        ),
                      if (isSeller) const Divider(height: 1),
                      if (isSeller)
                        ListTile(
                          leading: const Icon(Icons.sell_outlined),
                          title: Text(L10n.tr(context, 'seller_orders.title')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SellerOrdersPage(),
                            ),
                          ),
                        ),
                      if (isSeller) const Divider(height: 1),
                      if (isSeller)
                        ListTile(
                          leading: const Icon(Icons.analytics_outlined),
                          title: Text(L10n.tr(context, 'profile.dashboard')),
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
                          title: Text(L10n.tr(context, 'profile.my_listings')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MyListingsPage(),
                            ),
                          ),
                        ),
                      if (isSeller) const Divider(height: 1),
                      if (isSeller)
                        ListTile(
                          leading: const Icon(Icons.local_shipping_outlined),
                          title: Text(
                            L10n.tr(context, 'profile.shipments_board'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ShipmentsDashboardPage(),
                            ),
                          ),
                        ),
                      if (isSeller) const Divider(height: 1),
                      if (isSeller)
                        ListTile(
                          leading: const Icon(
                            Icons.settings_applications_outlined,
                          ),
                          title: Text(
                            L10n.tr(context, 'profile.courier_settings'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CourierSettingsPage(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  L10n.tr(
                    context,
                    'profile.geo',
                    params: {
                      'lat': _lat?.toStringAsFixed(4) ?? '--',
                      'lng': _lng?.toStringAsFixed(4) ?? '--',
                    },
                  ),
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
