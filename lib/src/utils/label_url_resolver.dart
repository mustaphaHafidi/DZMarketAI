import 'package:dzmarket/src/config/supabase_options.dart';

const Set<String> _internalSupabaseHosts = {
  'kong',
  'supabase-kong',
  'localhost',
  '127.0.0.1',
  '0.0.0.0',
  '::1',
};

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

String normalizeLabelUrl(String? rawUrl) {
  final trimmed = rawUrl?.trim() ?? '';
  if (trimmed.isEmpty) return '';

  final uri = _parseAbsoluteHttpUri(trimmed);
  if (uri == null) return trimmed;
  if (!_isInternalHost(uri.host)) return uri.toString();

  final supabaseBase = _parseAbsoluteHttpUri(SupabaseOptions.supabaseUrl);
  if (supabaseBase == null) return uri.toString();

  final rewritten = uri.replace(
    scheme: supabaseBase.scheme,
    host: supabaseBase.host,
    port: supabaseBase.hasPort ? supabaseBase.port : null,
  );
  return rewritten.toString();
}

Uri? resolveLabelUri(String? rawUrl) {
  final normalized = normalizeLabelUrl(rawUrl);
  if (normalized.isEmpty) return null;
  return Uri.tryParse(normalized);
}
