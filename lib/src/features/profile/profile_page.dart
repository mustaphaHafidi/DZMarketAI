import 'dart:async';

import 'package:dzmarket/src/models/account_deletion_request.dart';
import 'package:dzmarket/src/models/profile.dart';
import 'package:dzmarket/src/services/app_error_service.dart';
import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/connectivity_service.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/location_data_service.dart';
import 'package:dzmarket/src/services/location_service.dart';
import 'package:dzmarket/src/services/notification_inbox_service.dart';
import 'package:dzmarket/src/services/storage_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/services/user_safety_service.dart';
import 'package:dzmarket/src/widgets/user_avatar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Unified profile page (buyer/seller) with editable fields and seller tools.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final NotificationInboxService _notificationInboxService =
      NotificationInboxService();
  final DateFormat _dateFmt = DateFormat('dd/MM HH:mm');
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
  AccountDeletionRequestSummary? _deletionRequest;
  String? _selectedWilayaCode;
  String? _selectedCommuneId;
  String? _lastLoggedError;

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
    final localeCode =
        LocaleService.instance.locale.value?.languageCode ?? 'fr';
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _error = L10n.trLocale(localeCode, 'profile.login_required');
          _loading = false;
        });
        return;
      }
      await AuthService.instance.ensureProfileExists();
      final results = await Future.wait<dynamic>([
        AuthService.instance.fetchProfile(),
        AuthService.instance.fetchLatestAccountDeletionRequest(),
      ]);
      if (!mounted) return;
      final p = results[0] as Profile?;
      final deletionRequest = results[1] as AccountDeletionRequestSummary?;
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
      _deletionRequest = deletionRequest;
      _syncLocationSelectionFromText();
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyProfileError(localeCode, e);
      });
    } catch (e, stackTrace) {
      _logProfileError(e, stackTrace, contextTag: 'profile.load');
      if (!mounted) return;
      setState(() {
        _error = _friendlyProfileError(localeCode, e);
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
        avatarTouched: true,
        phone: phone,
        wilaya: wilaya,
        daira: daira,
        locationLat: _lat,
        locationLng: _lng,
        bio: bio,
        isPublic: _isPublic,
        lang: lang,
        isSeller: _isSeller,
      );
      await LocaleService.instance.setLocale(_lang);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.tr(context, 'profile.updated'))),
      );
      await _loadProfile();
    } catch (e, stackTrace) {
      _logProfileError(e, stackTrace, contextTag: 'profile.save');
      if (!mounted) return;
      final localeCode = Localizations.localeOf(context).languageCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyProfileError(localeCode, e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadLocations() async {
    setState(() {
      _loadingLocations = true;
      _locationLoadError = null;
    });
    List<Map<String, String>> items = const [];
    try {
      items = await LocationDataService.instance.fetchWilayas();
    } catch (error, stackTrace) {
      _logProfileError(error, stackTrace, contextTag: 'profile.load_locations');
    }
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
    List<Map<String, String>> items = const [];
    try {
      items = await LocationDataService.instance.fetchCommunes(code);
    } catch (error, stackTrace) {
      _logProfileError(error, stackTrace, contextTag: 'profile.load_communes');
    }
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

  bool _looksOfflineError(Object? error) {
    final msg = error?.toString().toLowerCase() ?? '';
    if (msg.isEmpty) return !ConnectivityService.instance.isOnline.value;
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('dns') ||
        msg.contains('network') ||
        msg.contains('connection closed') ||
        msg.contains('timed out') ||
        msg.contains('clientexception') ||
        msg.contains('no address associated with hostname');
  }

  String _friendlyProfileError(String localeCode, Object error) {
    if (_looksOfflineError(error)) {
      return L10n.trLocale(localeCode, 'common.offline_action');
    }
    return L10n.trLocale(
      localeCode,
      'profile.load_error_friendly',
      fallback: L10n.trLocale(localeCode, 'common.offline_action'),
    );
  }

  void _logProfileError(
    Object error,
    StackTrace? stackTrace, {
    required String contextTag,
  }) {
    final signature = '$contextTag|${error.toString()}';
    if (_lastLoggedError == signature) return;
    _lastLoggedError = signature;
    unawaited(
      AppErrorService.instance.logError(error, stackTrace, context: contextTag),
    );
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

  static const Map<String, String> _latinFoldMap = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
  };

  String _normalizeGeoToken(String? value) {
    var normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return '';
    for (final entry in _latinFoldMap.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    normalized = normalized
        .replaceAll(
          RegExp(
            r'\b(wilaya|province|state|commune|daira|da[iï]ra|district)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r"[’'`´_-]"), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized;
  }

  bool _isSoftLocationMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if (a.length >= 4 && b.length >= 4) {
      return a.contains(b) || b.contains(a);
    }
    return false;
  }

  Map<String, String>? _matchWilayaFromText(String? raw) {
    final target = _normalizeGeoToken(raw);
    if (target.isEmpty) return null;
    final targetDigits = target.replaceAll(RegExp(r'[^0-9]'), '');
    for (final item in _wilayas) {
      final code = (item['code'] ?? '').trim();
      if (code.isEmpty) continue;
      final codeNoLeadingZero = code.replaceFirst(RegExp(r'^0+'), '');
      if (target == code || target == codeNoLeadingZero) return item;
      if (targetDigits.isNotEmpty &&
          (targetDigits == code || targetDigits == codeNoLeadingZero)) {
        return item;
      }
      final fr = _normalizeGeoToken(item['name_fr']);
      final ar = _normalizeGeoToken(item['name_ar']);
      if (_isSoftLocationMatch(target, fr) ||
          _isSoftLocationMatch(target, ar)) {
        return item;
      }
    }
    return null;
  }

  Map<String, String>? _matchCommuneFromText(String? raw) {
    final target = _normalizeGeoToken(raw);
    if (target.isEmpty) return null;
    for (final item in _communes) {
      final id = _normalizeGeoToken(item['id']);
      final fr = _normalizeGeoToken(item['name_fr']);
      final ar = _normalizeGeoToken(item['name_ar']);
      if (_isSoftLocationMatch(target, id) ||
          _isSoftLocationMatch(target, fr) ||
          _isSoftLocationMatch(target, ar)) {
        return item;
      }
    }
    return null;
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
    required BuildContext context,
    required String label,
    required String value,
    required VoidCallback? onTap,
    required IconData icon,
    bool isPlaceholder = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final valueStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: onTap == null ? colors.onSurfaceVariant : colors.onSurface,
    );
    final textStyle = isPlaceholder
        ? Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant)
        : valueStyle;
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
            Expanded(
              child: Text(
                value,
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: onTap == null
                  ? colors.onSurfaceVariant.withValues(alpha: 0.6)
                  : colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _useMyLocation() async {
    setState(() => _saving = true);
    if (_wilayas.isEmpty && !_loadingLocations) {
      await _loadLocations();
    }
    final data = await LocationService.instance.fetchLocation();
    if (!mounted) return;
    if (data == null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.tr(context, 'profile.location_permission_denied')),
        ),
      );
      return;
    }

    final countryCode = data.countryCode?.trim().toUpperCase();
    if (countryCode != null && countryCode.isNotEmpty && countryCode != 'DZ') {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.tr(context, 'profile.location_outside_algeria')),
        ),
      );
      return;
    }

    final matchedWilaya = _matchWilayaFromText(data.wilaya);
    if (matchedWilaya == null) {
      setState(() {
        _saving = false;
        _lat = data.latitude;
        _lng = data.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.tr(context, 'profile.location_not_detected')),
        ),
      );
      return;
    }

    final wilayaCode = matchedWilaya['code'] ?? '';
    final wilayaName = matchedWilaya['name_fr'] ?? wilayaCode;
    setState(() {
      _lat = data.latitude;
      _lng = data.longitude;
      _selectedWilayaCode = wilayaCode.isNotEmpty ? wilayaCode : null;
      _wilayaCtrl.text = wilayaName;
      _selectedCommuneId = null;
      _dairaCtrl.text = '';
      _communes = const [];
    });
    if (wilayaCode.isNotEmpty) {
      await _loadCommunes(wilayaCode);
      if (mounted && data.daira?.trim().isNotEmpty == true) {
        final matchedCommune = _matchCommuneFromText(data.daira);
        if (matchedCommune != null) {
          final communeId = matchedCommune['id'] ?? '';
          setState(() {
            _selectedCommuneId = communeId.isNotEmpty ? communeId : null;
            _dairaCtrl.text = matchedCommune['name_fr'] ?? communeId;
          });
        }
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.tr(context, 'profile.location_updated'))),
    );
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.image,
    );
    final file = result?.files.first;
    if (file?.bytes == null) return;
    final previousAvatar = InputSanitizer.safeUrl(_avatarUrl);
    setState(() => _saving = true);
    try {
      final urls = await StorageService().uploadImages(
        files: [file!.bytes!],
        fileNames: [file.name],
        bucket: 'avatars',
      );
      final nextAvatar = urls.isNotEmpty ? urls.first : null;
      await _persistAvatarChange(
        nextAvatar: nextAvatar,
        previousAvatar: previousAvatar,
      );
    } catch (e, stackTrace) {
      _logProfileError(e, stackTrace, contextTag: 'profile.pick_avatar');
      if (!mounted) return;
      final localeCode = Localizations.localeOf(context).languageCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyProfileError(localeCode, e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _persistAvatarChange({
    required String? nextAvatar,
    String? previousAvatar,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const FormatException('login_required');
    }
    final safeNextAvatar = InputSanitizer.safeUrl(nextAvatar);
    final safePreviousAvatar = InputSanitizer.safeUrl(previousAvatar);
    try {
      await AuthService.instance.updateProfile(
        id: user.id,
        avatarUrl: safeNextAvatar,
        avatarTouched: true,
      );
      if (!mounted) return;
      setState(() {
        _avatarUrl = safeNextAvatar;
      });
      if (safePreviousAvatar != null &&
          safePreviousAvatar.isNotEmpty &&
          safePreviousAvatar != safeNextAvatar) {
        unawaited(
          StorageService()
              .deletePublicUrls([safePreviousAvatar], bucket: 'avatars')
              .catchError((_) {}),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.tr(context, 'profile.updated'))),
      );
    } catch (e, stackTrace) {
      if (safeNextAvatar != null &&
          safeNextAvatar.isNotEmpty &&
          safeNextAvatar != safePreviousAvatar) {
        unawaited(
          StorageService()
              .deletePublicUrls([safeNextAvatar], bucket: 'avatars')
              .catchError((_) {}),
        );
      }
      _logProfileError(e, stackTrace, contextTag: 'profile.persist_avatar');
      rethrow;
    }
  }

  Future<void> _removeAvatar() async {
    final previousAvatar = InputSanitizer.safeUrl(_avatarUrl);
    if (previousAvatar == null || previousAvatar.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _persistAvatarChange(
        nextAvatar: null,
        previousAvatar: previousAvatar,
      );
    } catch (e, stackTrace) {
      _logProfileError(e, stackTrace, contextTag: 'profile.remove_avatar');
      if (!mounted) return;
      final localeCode = Localizations.localeOf(context).languageCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyProfileError(localeCode, e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSupportEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: UserSafetyService.supportEmail,
      queryParameters: const {'subject': 'DZMarket Support'},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _requestAccountDeletion() async {
    if (_deletionRequest?.isOpen ?? false) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trWithLocaleFallback(
              context,
              'profile.account_deletion_pending_banner',
              fr: 'Une demande de suppression est deja en cours de traitement.',
              ar: 'يوجد بالفعل طلب حذف قيد المعالجة.',
            ),
          ),
        ),
      );
      return;
    }
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _trWithLocaleFallback(
            dialogContext,
            'profile.delete_account_confirm_title',
            fr: 'Demander la suppression du compte',
            ar: 'طلب حذف الحساب',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _trWithLocaleFallback(
                dialogContext,
                'profile.delete_account_confirm_body',
                fr:
                    'Cette action envoie une demande de suppression de votre compte DZMarket. Le traitement est effectue manuellement sous 30 jours maximum. Certaines donnees peuvent etre conservees temporairement pour des obligations legales, comptables, antifraude et de securite.',
                ar:
                    'يرسل هذا الاجراء طلبا لحذف حسابك في DZMarket. تتم المعالجة يدويا خلال 30 يوما كحد اقصى. قد نحتفظ ببعض البيانات مؤقتا لالتزامات قانونية ومحاسبية ولمكافحة الاحتيال ولاغراض الامن.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _trWithLocaleFallback(
                  dialogContext,
                  'profile.delete_account_reason_label',
                  fr: 'Raison (optionnel)',
                  ar: 'السبب (اختياري)',
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _trWithLocaleFallback(
                dialogContext,
                'profile.delete_account_cta',
                fr: 'Envoyer la demande',
                ar: 'ارسال الطلب',
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthService.instance.requestAccountDeletion(
        reason: reasonCtrl.text,
      );
      if (!mounted) return;
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trWithLocaleFallback(
              context,
              'profile.delete_account_success',
              fr:
                  'Demande de suppression envoyee. Votre compte sera traite sous 30 jours maximum.',
              ar:
                  'تم ارسال طلب حذف الحساب. ستتم معالجة حسابك خلال 30 يوما كحد اقصى.',
            ),
          ),
        ),
      );
      await AuthService.instance.signOut();
      if (!mounted) return;
      context.go('/sign-in');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trWithLocaleFallback(
              context,
              'profile.delete_account_failed',
              fr:
                  'Impossible d envoyer la demande de suppression pour le moment.',
              ar: 'تعذر ارسال طلب حذف الحساب حاليا.',
            ),
          ),
        ),
      );
    } finally {
      reasonCtrl.dispose();
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  bool _isArabicLocale(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ar';
  }

  String _localizedFallback(
    BuildContext context, {
    required String fr,
    required String ar,
  }) {
    return _isArabicLocale(context) ? ar : fr;
  }

  String _trWithLocaleFallback(
    BuildContext context,
    String key, {
    required String fr,
    required String ar,
    Map<String, String>? params,
  }) {
    return L10n.tr(
      context,
      key,
      fallback: _localizedFallback(context, fr: fr, ar: ar),
      params: params,
    );
  }

  String _deletionStatusLabelWithLocale(BuildContext context, String status) {
    switch (status) {
      case 'processing':
        return _trWithLocaleFallback(
          context,
          'admin.moderation.deletion_processing',
          fr: 'En traitement',
          ar: 'قيد المعالجة',
        );
      case 'completed':
        return _trWithLocaleFallback(
          context,
          'admin.moderation.deletion_completed',
          fr: 'Cloturee',
          ar: 'مغلقة',
        );
      case 'rejected':
        return _trWithLocaleFallback(
          context,
          'admin.moderation.deletion_rejected',
          fr: 'Rejetee',
          ar: 'مرفوضة',
        );
      case 'cancelled':
        return _trWithLocaleFallback(
          context,
          'admin.moderation.deletion_cancelled',
          fr: 'Annulee',
          ar: 'ملغاة',
        );
      case 'pending':
      default:
        return _trWithLocaleFallback(
          context,
          'admin.moderation.deletion_pending',
          fr: 'En attente',
          ar: 'قيد الانتظار',
        );
    }
  }

  String _deletionStatusLabel(String status) {
    switch (status) {
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
      case 'pending':
      default:
        return L10n.tr(
          context,
          'admin.moderation.deletion_pending',
          fallback: 'En attente',
        );
    }
  }

  Color _deletionStatusColor(String status) {
    switch (status) {
      case 'processing':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.blueGrey;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  Widget buildAccountDeletionTileLegacy(BuildContext context) {
    final request = _deletionRequest;
    final hasOpenRequest = request?.isOpen ?? false;
    final note = request?.adminNote?.trim() ?? '';
    final processedAt = request?.processedAt;
    final requestedAt = request?.requestedAt;

    if (request != null) {
      final statusColor = _deletionStatusColor(request.status);
      final detailLines = <String>[];
      if (requestedAt != null) {
        detailLines.add(
          L10n.tr(
            context,
            'profile.account_deletion_requested_at',
            fallback: 'Demandée le {date}',
            params: {'date': _dateFmt.format(requestedAt)},
          ),
        );
      }
      if (processedAt != null) {
        detailLines.add(
          L10n.tr(
            context,
            'profile.account_deletion_processed_at',
            fallback: 'Traitée le {date}',
            params: {'date': _dateFmt.format(processedAt)},
          ),
        );
      }
      if (note.isNotEmpty) {
        detailLines.add(
          L10n.tr(
            context,
            'profile.account_deletion_admin_note',
            fallback: 'Note admin: {note}',
            params: {'note': note},
          ),
        );
      }

      return ListTile(
        leading: Icon(
          hasOpenRequest
              ? Icons.hourglass_top_outlined
              : Icons.assignment_turned_in_outlined,
        ),
        title: Text(
          hasOpenRequest
              ? L10n.tr(
                  context,
                  'profile.account_deletion_in_progress',
                  fallback: 'Demande de suppression en cours',
                )
              : L10n.tr(
                  context,
                  'profile.account_deletion_last_request',
                  fallback: 'Dernière demande de suppression',
                ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            _buildInlineStatusChip(
              _deletionStatusLabel(request.status),
              statusColor,
            ),
            if (detailLines.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(detailLines.join('\n')),
            ],
            const SizedBox(height: 6),
            Text(
              hasOpenRequest
                  ? L10n.tr(
                      context,
                      'profile.account_deletion_open_hint',
                      fallback:
                          'Votre demande est deja ouverte. Aucun doublon ne sera cree tant qu elle est en attente ou en traitement.',
                    )
                  : L10n.tr(
                      context,
                      'profile.account_deletion_hint',
                      fallback:
                          'Demande initiee dans l app, traitement sous 30 jours maximum.',
                    ),
            ),
          ],
        ),
        trailing: hasOpenRequest
            ? const Icon(Icons.info_outline)
            : const Icon(Icons.chevron_right),
        onTap: hasOpenRequest
            ? null
            : (_saving ? null : _requestAccountDeletion),
      );
    }

    return ListTile(
      leading: const Icon(Icons.delete_sweep_outlined),
      title: Text(
        L10n.tr(
          context,
          'profile.account_deletion',
          fallback: 'Demander la suppression du compte',
        ),
      ),
      subtitle: Text(
        L10n.tr(
          context,
          'profile.account_deletion_hint',
          fallback:
              'Demande initiee dans l app, traitement sous 30 jours maximum.',
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _saving ? null : _requestAccountDeletion,
    );
  }

  Widget _buildLocalizedAccountDeletionTile(BuildContext context) {
    final request = _deletionRequest;
    final hasOpenRequest = request?.isOpen ?? false;
    final note = request?.adminNote?.trim() ?? '';
    final processedAt = request?.processedAt;
    final requestedAt = request?.requestedAt;

    if (request != null) {
      final statusColor = _deletionStatusColor(request.status);
      final detailLines = <String>[];
      if (requestedAt != null) {
        detailLines.add(
          _trWithLocaleFallback(
            context,
            'profile.account_deletion_requested_at',
            fr: 'Demandee le {date}',
            ar: 'طُلبت في {date}',
            params: {'date': _dateFmt.format(requestedAt)},
          ),
        );
      }
      if (processedAt != null) {
        detailLines.add(
          _trWithLocaleFallback(
            context,
            'profile.account_deletion_processed_at',
            fr: 'Traitee le {date}',
            ar: 'عولجت في {date}',
            params: {'date': _dateFmt.format(processedAt)},
          ),
        );
      }
      if (note.isNotEmpty) {
        detailLines.add(
          _trWithLocaleFallback(
            context,
            'profile.account_deletion_admin_note',
            fr: 'Note admin: {note}',
            ar: 'ملاحظة الادارة: {note}',
            params: {'note': note},
          ),
        );
      }

      return ListTile(
        leading: Icon(
          hasOpenRequest
              ? Icons.hourglass_top_outlined
              : Icons.assignment_turned_in_outlined,
        ),
        title: Text(
          hasOpenRequest
              ? _trWithLocaleFallback(
                  context,
                  'profile.account_deletion_in_progress',
                  fr: 'Demande de suppression en cours',
                  ar: 'طلب حذف الحساب قيد المعالجة',
                )
              : _trWithLocaleFallback(
                  context,
                  'profile.account_deletion_last_request',
                  fr: 'Derniere demande de suppression',
                  ar: 'اخر طلب حذف للحساب',
                ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            _buildInlineStatusChip(
              _deletionStatusLabelWithLocale(context, request.status),
              statusColor,
            ),
            if (detailLines.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(detailLines.join('\n')),
            ],
            const SizedBox(height: 6),
            Text(
              hasOpenRequest
                  ? _trWithLocaleFallback(
                      context,
                      'profile.account_deletion_open_hint',
                      fr:
                          'Votre demande est deja ouverte. Aucun doublon ne sera cree tant qu elle est en attente ou en traitement.',
                      ar:
                          'طلبك مفتوح بالفعل. لن يتم انشاء طلب جديد ما دام في انتظار المعالجة او قيد المعالجة.',
                    )
                  : _trWithLocaleFallback(
                      context,
                      'profile.account_deletion_hint',
                      fr:
                          'Demande initiee dans l app, traitement sous 30 jours maximum.',
                      ar:
                          'يتم تقديم الطلب من داخل التطبيق، وتتم معالجته خلال 30 يوما كحد اقصى.',
                    ),
            ),
          ],
        ),
        trailing: hasOpenRequest
            ? const Icon(Icons.info_outline)
            : const Icon(Icons.chevron_right),
        onTap: hasOpenRequest ? null : (_saving ? null : _requestAccountDeletion),
      );
    }

    return ListTile(
      leading: const Icon(Icons.delete_sweep_outlined),
      title: Text(
        _trWithLocaleFallback(
          context,
          'profile.account_deletion',
          fr: 'Demander la suppression du compte',
          ar: 'طلب حذف الحساب',
        ),
      ),
      subtitle: Text(
        _trWithLocaleFallback(
          context,
          'profile.account_deletion_hint',
          fr: 'Demande initiee dans l app, traitement sous 30 jours maximum.',
          ar:
              'يتم تقديم الطلب من داخل التطبيق، وتتم معالجته خلال 30 يوما كحد اقصى.',
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _saving ? null : _requestAccountDeletion,
    );
  }

  Widget _buildInlineStatusChip(String label, Color color) {
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

  Widget _buildProfileHeader({
    required BuildContext context,
    required String? safeAvatar,
    required bool isSeller,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: colors.surface,
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.65),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(
                radius: 28,
                avatarUrl: safeAvatar,
                fullName: _nameCtrl.text.trim(),
                email: _profile?.email,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nameCtrl.text.trim().isEmpty
                          ? (_profile?.email ?? '')
                          : _nameCtrl.text.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _profile?.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: colors.primaryContainer.withValues(alpha: 0.45),
                ),
                child: Text(
                  isSeller
                      ? L10n.tr(context, 'profile.mode_seller')
                      : L10n.tr(context, 'profile.mode_buyer'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _useMyLocation,
                  icon: const Icon(Icons.my_location_outlined),
                  label: Text(L10n.tr(context, 'profile.use_location')),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _looksOfflineError(_error)
                      ? Icons.wifi_off_rounded
                      : Icons.error_outline,
                  size: 28,
                ),
                const SizedBox(height: 10),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loadProfile,
                  child: Text(L10n.tr(context, 'common.reload')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final safeAvatar = InputSanitizer.safeUrl(_avatarUrl);
    final isSeller = _isSeller;
    final isSuperAdmin = _profile?.role == UserRole.superadmin;
    final colors = Theme.of(context).colorScheme;
    Widget sectionCard({
      required String title,
      required List<Widget> children,
    }) {
      final content = <Widget>[];
      for (var i = 0; i < children.length; i++) {
        if (i > 0) content.add(const Divider(height: 1));
        content.add(children[i]);
      }
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          children: [
            ListTile(
              title: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const Divider(height: 1),
            ...content,
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(L10n.tr(context, 'profile.title'))),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProfile,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileHeader(
                      context: context,
                      safeAvatar: safeAvatar,
                      isSeller: isSeller,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: colors.outlineVariant.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              L10n.tr(context, 'profile.section_account'),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _nameCtrl,
                              style: Theme.of(context).textTheme.bodyLarge,
                              decoration: InputDecoration(
                                labelText: L10n.tr(
                                  context,
                                  'profile.full_name',
                                ),
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
                                    child: Text(
                                      L10n.tr(context, 'common.delete'),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _bioCtrl,
                              maxLines: 2,
                              style: Theme.of(context).textTheme.bodyLarge,
                              decoration: InputDecoration(
                                labelText: L10n.tr(context, 'profile.bio'),
                                prefixIcon: const Icon(Icons.notes_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: Theme.of(context).textTheme.bodyLarge,
                              decoration: InputDecoration(
                                labelText: L10n.tr(context, 'profile.phone'),
                                prefixIcon: const Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Column(
                              children: [
                                _buildPickerField(
                                  context: context,
                                  label: L10n.tr(context, 'profile.wilaya'),
                                  value: _wilayaLabel(context),
                                  icon: Icons.map_outlined,
                                  isPlaceholder:
                                      _selectedWilayaCode == null ||
                                      _selectedWilayaCode!.isEmpty,
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
                                            _selectedWilayaCode =
                                                code.isNotEmpty ? code : null;
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
                                const SizedBox(height: 12),
                                _buildPickerField(
                                  context: context,
                                  label: L10n.tr(context, 'profile.daira'),
                                  value: _communeLabel(context),
                                  icon: Icons.place_outlined,
                                  isPlaceholder:
                                      _selectedCommuneId == null ||
                                      _selectedCommuneId!.isEmpty,
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
                                          final communeId =
                                              selected['id'] ?? '';
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
                              key: ValueKey(_lang),
                              initialValue: _lang,
                              decoration: InputDecoration(
                                labelText: L10n.tr(context, 'profile.language'),
                                prefixIcon: const Icon(Icons.language_outlined),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'fr',
                                  child: Text(
                                    L10n.tr(context, 'profile.lang_fr'),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'ar',
                                  child: Text(
                                    L10n.tr(context, 'profile.lang_ar'),
                                  ),
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
                              title: Text(
                                L10n.tr(context, 'profile.seller_mode'),
                              ),
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
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
                    sectionCard(
                      title: L10n.tr(context, 'profile.section_tools'),
                      children: [
                        StreamBuilder<int>(
                          stream: _notificationInboxService.watchUnreadCount(),
                          builder: (context, snap) {
                            final unread = snap.data ?? 0;
                            return ListTile(
                              leading: const Icon(Icons.notifications_outlined),
                              title: Text(
                                L10n.tr(context, 'notifications.title'),
                              ),
                              subtitle: Text(
                                unread > 0
                                    ? L10n.tr(
                                        context,
                                        'notifications.unread_count',
                                        params: {'count': '$unread'},
                                      )
                                    : L10n.tr(
                                        context,
                                        'notifications.all_caught_up',
                                      ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (unread > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        unread > 99 ? '99+' : '$unread',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () => context.push('/notifications'),
                            );
                          },
                        ),
                        if (isSeller)
                          ListTile(
                            leading: const Icon(Icons.sell_outlined),
                            title: Text(
                              L10n.tr(context, 'seller_orders.title'),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/seller/orders'),
                          ),
                        if (isSeller)
                          ListTile(
                            leading: const Icon(Icons.analytics_outlined),
                            title: Text(L10n.tr(context, 'profile.dashboard')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/seller/dashboard'),
                          ),
                        if (isSeller)
                          ListTile(
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text(
                              L10n.tr(context, 'profile.my_listings'),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/seller/listings'),
                          ),
                        if (isSeller)
                          ListTile(
                            leading: const Icon(Icons.local_shipping_outlined),
                            title: Text(
                              L10n.tr(context, 'profile.shipments_board'),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/seller/shipments'),
                          ),
                        if (isSeller)
                          ListTile(
                            leading: const Icon(
                              Icons.settings_applications_outlined,
                            ),
                            title: Text(
                              L10n.tr(context, 'profile.courier_settings'),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/seller/couriers'),
                          ),
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
                            onTap: () => context.push('/admin/errors'),
                          ),
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
                            onTap: () => context.push('/admin/moderation'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    sectionCard(
                      title: L10n.tr(context, 'profile.section_security'),
                      children: [_buildLocalizedAccountDeletionTile(context)],
                    ),
                    const SizedBox(height: 16),
                    sectionCard(
                      title: L10n.tr(context, 'profile.section_help_legal'),
                      children: [
                        ListTile(
                          leading: const Icon(Icons.privacy_tip_outlined),
                          title: Text(
                            L10n.tr(
                              context,
                              'profile.privacy_policy',
                              fallback: 'Politique de confidentialite',
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/legal/privacy'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(
                            L10n.tr(
                              context,
                              'profile.terms',
                              fallback: 'Conditions d utilisation',
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/legal/terms'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.support_agent_outlined),
                          title: Text(
                            L10n.tr(
                              context,
                              'profile.contact_support',
                              fallback: 'Contacter le support',
                            ),
                          ),
                          subtitle: const Text(UserSafetyService.supportEmail),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: _openSupportEmail,
                        ),
                      ],
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
        ),
      ),
    );
  }
}
