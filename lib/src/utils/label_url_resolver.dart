import 'package:dzmarket/src/config/app_config.dart';
import 'package:dzmarket/src/config/supabase_options.dart';

const Set<String> _internalSupabaseHosts = {
  'kong',
  'supabase-kong',
  'localhost',
  '127.0.0.1',
  '0.0.0.0',
  '::1',
};
const Set<String> _internalProxyPorts = {'8000', '8443'};

bool _isInternalHost(String host) {
  final normalized = host.trim().toLowerCase();
  return _internalSupabaseHosts.contains(normalized);
}

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

Uri _stripDefaultPort(Uri uri) {
  if (uri.scheme == 'https') return uri.replace(port: 443);
  if (uri.scheme == 'http') return uri.replace(port: 80);
  return uri;
}

Uri _normalizePublicProxyPort(Uri uri, {Uri? preferredApiBase}) {
  final host = uri.host.toLowerCase();
  final preferredHost = preferredApiBase?.host.toLowerCase();
  final isApiHost = host.startsWith('api.') || (preferredHost == host);
  final isInternalPort =
      uri.hasPort && _internalProxyPorts.contains(uri.port.toString());
  if (isApiHost && isInternalPort) {
    return _stripDefaultPort(uri);
  }
  return uri;
}

String normalizeLabelUrl(String? rawUrl) {
  final trimmed = rawUrl?.trim() ?? '';
  if (trimmed.isEmpty) return '';

  final uri = _parseAbsoluteHttpUri(trimmed);
  if (uri == null) return trimmed;

  final runtimeSupabaseUrl = AppConfig.current?.supabaseUrl ?? '';
  final supabaseBase =
      _parseAbsoluteHttpUri(runtimeSupabaseUrl) ??
      _parseAbsoluteHttpUri(SupabaseOptions.supabaseUrl) ??
      _webApiBaseFallback();
  if (!_isInternalHost(uri.host)) {
    return _normalizePublicProxyPort(uri, preferredApiBase: supabaseBase)
        .toString();
  }
  if (supabaseBase == null) return uri.toString();

  final rewritten = uri.replace(
    scheme: supabaseBase.scheme,
    host: supabaseBase.host,
    port: supabaseBase.hasPort ? supabaseBase.port : null,
  );
  return _normalizePublicProxyPort(rewritten, preferredApiBase: supabaseBase)
      .toString();
}

Uri? resolveLabelUri(String? rawUrl) {
  final normalized = normalizeLabelUrl(rawUrl);
  if (normalized.isEmpty) return null;
  return Uri.tryParse(normalized);
}
