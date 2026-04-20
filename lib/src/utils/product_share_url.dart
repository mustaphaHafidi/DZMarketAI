Uri buildProductShareUri({
  required String productId,
  Uri? currentUri,
  Uri? fallbackBase,
}) {
  final base = currentUri ?? Uri.base;
  final safeFallbackBase =
      fallbackBase ?? Uri.parse('https://app.dzmarket.pro');
  final scheme = base.scheme.isNotEmpty && base.scheme != 'file'
      ? base.scheme
      : safeFallbackBase.scheme;
  final host = base.host.isNotEmpty ? base.host : safeFallbackBase.host;
  final port = base.hasPort ? base.port : null;
  return Uri(
    scheme: scheme,
    host: host,
    port: port,
    path: '/product/$productId',
  );
}
