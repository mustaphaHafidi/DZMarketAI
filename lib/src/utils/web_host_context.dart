import 'package:flutter/foundation.dart';

const _marketingHosts = {'www.dzmarket.pro', 'dzmarket.pro'};

bool isMarketingWebHost({String? host, bool? isWebOverride}) {
  final isWeb = isWebOverride ?? kIsWeb;
  if (!isWeb) return false;
  final resolvedHost = (host ?? Uri.base.host).toLowerCase();
  return _marketingHosts.contains(resolvedHost);
}

bool shouldShowMarketingLanding({
  required String matchedLocation,
  Uri? uri,
  String? host,
  bool? isWebOverride,
}) {
  if (!isMarketingWebHost(host: host, isWebOverride: isWebOverride)) {
    return false;
  }
  final resolvedUri = uri ?? Uri.base;
  final tab = resolvedUri.queryParameters['tab'];
  return matchedLocation == '/' && (tab == null || tab.isEmpty);
}
