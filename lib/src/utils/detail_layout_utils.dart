import 'dart:ui';

bool shouldUseWideDetailLayout({
  required Size screenSize,
  required bool isWeb,
}) {
  if (isWeb) return true;
  return screenSize.shortestSide >= 600;
}
