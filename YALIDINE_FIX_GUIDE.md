# Yalidine API Request Troubleshooting Guide

## The Issue
You confirmed that your curl request works, but the same request fails in the Flutter app.

Example (placeholders only):
```bash
curl "https://api.yalidine.app/v1/wilayas/" \
  -H "X-API-ID: <YALIDINE_API_ID>" \
  -H "X-API-TOKEN: <YALIDINE_API_TOKEN>"
```

## Root Causes & Solutions

### 1) URL Trailing Slash (FIXED)
**Issue:** The code was missing a trailing slash.
```dart
// Before (missing slash)
final uri = Uri.parse('https://api.yalidine.app/v1/wilayas');

// After (with slash, matching curl)
final uri = Uri.parse('https://api.yalidine.app/v1/wilayas/');
```

### 2) Database Column Error (FIXED)
**Issue:** loadSellerDeliverySettings queried non-existent columns.
```dart
// Before
.select('api_key, api_secret, sender_id, extra, from_wilaya, receiver_name, ...')

// After (only real columns)
.select('api_key, api_secret, sender_id, extra')
```

### 3) HTTP Client Configuration (dev only)
If requests still fail in Flutter, verify SSL/TLS and timeouts.

```dart
// Dev only: ignore bad certificates
import 'dart:io';
HttpOverrides.global = MyHttpOverrides();

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}
```

**WARNING:** Never use this in production.

### 4) Request Timeout
Increase timeout if needed:
```dart
final resp = await http.get(uri, headers: {...})
  .timeout(const Duration(seconds: 15));
```

### 5) Headers & Encoding
Use:
```dart
headers: {
  'X-API-ID': apiKey,
  'X-API-TOKEN': apiSecret,
  'Accept': 'application/json',
}
```

## Verification
- validate-courier (Edge) must return ok for the vendor token.
- courier-locations should load wilayas/communes with the same credentials.

## Summary
The root issue was:
- Missing trailing slash in the Yalidine URL
- Non-existent database columns being queried

If requests still fail after these fixes, check:
1) Network connectivity (device/emulator)
2) SSL/TLS (dev only)
3) API credentials validity

No secrets should ever be stored in the repository.
