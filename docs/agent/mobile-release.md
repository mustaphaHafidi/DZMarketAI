# Mobile Release Notes

Read this for Android/iOS release, Firebase, push, Codemagic, Play Console, TestFlight.

## Current Identities

- Android package: `com.dzmarket.app`.
- Android flavors: `dev`, `staging`, `prod`.
- iOS bundle id: `com.dzmarket.app`.
- Codemagic workflow: `DZMarket iOS TestFlight`.
- Codemagic build host: macOS, not this Windows machine.

## Runtime Inputs

Use variable names only; never expose values.

- `APP_FLAVOR`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `FIREBASE_IOS_PLIST_BASE64`
- `GOOGLE_WEB_CLIENT_ID`
- `GOOGLE_IOS_CLIENT_ID`
- `ENABLE_ANALYTICS`
- `ENABLE_CRASHLYTICS`

## iOS Firebase And Push

- `GoogleService-Info.plist` configures the iOS app for Firebase.
- Real iOS push also requires Apple APNs configuration in Firebase Console.
- APNs `.p8` keys are Apple Developer keys; they are not App Store Connect signing keys.
- For DZMarket, the APNs key should be scoped to topic `com.dzmarket.app` when possible.
- Upload APNs key in Firebase Cloud Messaging for production before expecting TestFlight/App Store push.

## Android Firebase And Push

- Android uses FCM and the package `com.dzmarket.app`.
- Android production uses the `prod` flavor.
- For Play release, build an AAB, not only APK.
- Do not claim Play publication while Play Console shows review/pending status.

## Release Rules

- Increment build number before store redeploy.
- Keep user-requested marketing version unless App Store requires a higher version.
- Run targeted tests before build.
- Verify uploaded build in App Store Connect/TestFlight or Play Console before reporting complete.
- iOS IPA release build must be produced by Codemagic or a real Mac.

## Useful Checks

```powershell
flutter test --no-test-assets
dart analyze
flutter build appbundle --release --flavor prod -t lib/main.dart
```

Codemagic iOS is configured in `codemagic.yaml`; confirm its build name/number before launching.

