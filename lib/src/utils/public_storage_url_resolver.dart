import 'package:dzmarket/src/config/app_config.dart';
import 'package:dzmarket/src/config/supabase_options.dart';

const String _publicStorageMarker = '/storage/v1/object/public/';
const Set<String> _internalStorageHosts = {
  'kong',
  'supabase-kong',
  'localhost',
  '127.0.0.1',
  '0.0.0.0',
  '::1',
};
const Set<String> _internalProxyPorts = {'8000', '8443'};

Uri? _parseAbsoluteHttpUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null) return null;
  if (!uri.hasScheme || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

Uri? _webApiBaseFallback() {
  final current = _parseAbsoluteHttpUri(Uri.base.toString());
  if (current == null) return null;
  final host = current.host.toLowerCase();
  if (host.startsWith('app.')) {
    return current.replace(host: 'api.${current.host.substring(4)}');
  }
  return null;
}

Uri? _preferredPublicStorageBase() {
  return _parseAbsoluteHttpUri(AppConfig.current?.supabaseUrl ?? '') ??
      _parseAbsoluteHttpUri(SupabaseOptions.supabaseUrl) ??
      _webApiBaseFallback();
}

bool _isInternalHost(String host) =>
    _internalStorageHosts.contains(host.trim().toLowerCase());

Uri _stripDefaultPort(Uri uri) {
  if (uri.scheme == 'https') return uri.replace(port: 443);
  if (uri.scheme == 'http') return uri.replace(port: 80);
  return uri;
}

Uri _normalizeProxyPort(Uri uri, {Uri? preferredBase}) {
  final preferredHost = preferredBase?.host.toLowerCase();
  final isPreferredHost = preferredHost != null &&
      preferredHost.isNotEmpty &&
      uri.host.toLowerCase() == preferredHost;
  final hasInternalPort =
      uri.hasPort && _internalProxyPorts.contains(uri.port.toString());
  if (isPreferredHost && hasInternalPort) {
    return _stripDefaultPort(uri);
  }
  return uri;
}

Uri _upgradeHttps(Uri uri, {Uri? preferredBase}) {
  if (uri.scheme != 'http') return uri;
  if (preferredBase?.scheme == 'https' && !_isInternalHost(uri.host)) {
    return uri.replace(scheme: 'https');
  }
  return uri;
}

String normalizePublicStorageUrl(String? rawUrl) {
  final trimmed = rawUrl?.trim() ?? '';
  if (trimmed.isEmpty) return '';

  final uri = _parseAbsoluteHttpUri(trimmed);
  if (uri == null) return trimmed;

  final preferredBase = _preferredPublicStorageBase();
  final isPublicStoragePath = uri.path.contains(_publicStorageMarker);
  if (isPublicStoragePath && preferredBase != null) {
    final rewritten = uri.replace(
      scheme: preferredBase.scheme,
      host: preferredBase.host,
      port: preferredBase.hasPort ? preferredBase.port : null,
    );
    return _normalizeProxyPort(
      _upgradeHttps(rewritten, preferredBase: preferredBase),
      preferredBase: preferredBase,
    ).toString();
  }

  if (_isInternalHost(uri.host) && preferredBase != null) {
    final rewritten = uri.replace(
      scheme: preferredBase.scheme,
      host: preferredBase.host,
      port: preferredBase.hasPort ? preferredBase.port : null,
    );
    return _normalizeProxyPort(
      _upgradeHttps(rewritten, preferredBase: preferredBase),
      preferredBase: preferredBase,
    ).toString();
  }

  return _normalizeProxyPort(
    _upgradeHttps(uri, preferredBase: preferredBase),
    preferredBase: preferredBase,
  ).toString();
}
