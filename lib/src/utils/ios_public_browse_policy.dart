import 'package:flutter/foundation.dart';

bool allowsAnonymousBrowse({TargetPlatform? platform, bool? isWebOverride}) {
  return true;
}

bool allowsIosAnonymousBrowse({TargetPlatform? platform, bool? isWebOverride}) {
  final isWeb = isWebOverride ?? kIsWeb;
  if (isWeb) return false;
  return (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
}

bool isAnonymousBrowseHomeTabAllowed(String? tab) {
  return tab == null || tab.isEmpty || tab == 'listings';
}

bool isAnonymousRouteAllowed({
  required String matchedLocation,
  required Uri uri,
  TargetPlatform? platform,
  bool? isWebOverride,
}) {
  if (!allowsAnonymousBrowse(
    platform: platform,
    isWebOverride: isWebOverride,
  )) {
    return false;
  }

  if (matchedLocation == '/' &&
      isAnonymousBrowseHomeTabAllowed(uri.queryParameters['tab'])) {
    return true;
  }

  return matchedLocation == '/product/:id' ||
      matchedLocation.startsWith('/product/');
}
