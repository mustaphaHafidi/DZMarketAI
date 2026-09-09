const defaultEcotrackBaseUrl = 'https://api.ecotrack.dz';

String? normalizeEcotrackBaseUrl(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return defaultEcotrackBaseUrl;

  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme.toLowerCase() != 'https') return null;
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
  if (uri.path.isNotEmpty && uri.path != '/') return null;
  if (uri.port != 0 && uri.port != 443) return null;

  final host = uri.host.toLowerCase();
  if (host.isEmpty || !host.contains('.')) return null;
  return 'https://$host';
}
