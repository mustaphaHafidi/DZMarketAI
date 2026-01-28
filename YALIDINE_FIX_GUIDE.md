# Yalidine API Request Troubleshooting Guide

## The Issue
You've confirmed that your curl request works:
```bash
curl "https://api.yalidine.app/v1/wilayas/" \
  -H "X-API-ID: 50753201115255761407" \
  -H "X-API-TOKEN: uzTwKESIkqAaGViHNj4t8lCgrsRZU9LxFMOoQDP163pYbynfWemBd2v50X7Jch"
```

But the same request fails in your Flutter app. A standalone Dart test script confirms **the request itself works fine in Dart** (status 200, valid JSON response).

## Root Causes & Solutions

### 1. ✅ **URL Trailing Slash** (FIXED)
**Issue:** The code was missing a trailing slash
```dart
// ❌ Before (missing slash)
final uri = Uri.parse('https://api.yalidine.app/v1/wilayas');

// ✅ After (with slash, matching curl)
final uri = Uri.parse('https://api.yalidine.app/v1/wilayas/');
```

### 2. ✅ **Database Column Error** (FIXED)
**Issue:** The `loadSellerDeliverySettings` method queried non-existent columns
```dart
// ❌ Before
.select('api_key, api_secret, sender_id, extra, from_wilaya, receiver_name, ...')

// ✅ After (only real columns)
.select('api_key, api_secret, sender_id, extra')
```

### 3. **HTTP Client Configuration** (Check if needed)
If requests still fail in the Flutter app, verify:

```dart
// Option A: Disable SSL/TLS verification (development only!)
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

**⚠️ WARNING:** This disables certificate validation and should **NEVER** be used in production. Only use for debugging on emulators or development environments.

### 4. **Request Timeout** (Check if needed)
The current timeout is 8 seconds, which should be adequate:
```dart
final resp = await http
    .get(uri, headers: {...})
    .timeout(const Duration(seconds: 8));
```

If needed, increase it:
```dart
.timeout(const Duration(seconds: 15))
```

### 5. **Headers & Encoding**
The current implementation is correct:
```dart
headers: {
  'X-API-ID': apiKey,
  'X-API-TOKEN': apiSecret,
  'Accept': 'application/json',
}
```

The `http` package handles UTF-8 encoding automatically.

### 6. **Network Connectivity (Flutter-specific)**
In a Flutter app running on an emulator or device, check:
- **Emulator:** Network settings, ensure internet access is enabled
- **Device:** App has internet permission in `AndroidManifest.xml` and `Info.plist`
- **Web:** Check for CORS issues (the Yalidine API response includes `access-control-allow-origin: *`, so CORS should be fine)

## Testing the Fix

The following changes have been made to `ShippingService`:

1. ✅ Updated `_validateYalidine()` to use the correct URL with trailing slash
2. ✅ Fixed `loadSellerDeliverySettings()` to query only existing database columns

## Verification

To verify the fixes work:

```bash
# Run the standalone Dart test (succeeds if no network issues)
dart run bin/test_yalidine.dart

# Run the Flutter app and test courier settings
flutter run
```

## Summary

**The root issue was:**
- Missing trailing slash in the Yalidine URL
- Non-existent database columns being queried

**These have been fixed.** If requests still fail in the Flutter app, the issue is likely:
1. Network connectivity (emulator/device internet access)
2. SSL/TLS certificate validation (use the HttpOverrides solution above for development)
3. API credentials have changed or are incorrect

Verify by checking the network request details in your IDE's debugger or by adding debug logging to the `_validateYalidine()` method.
