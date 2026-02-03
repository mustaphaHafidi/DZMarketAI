# DZMarket

Marketplace app built with Flutter and Supabase.

## Prerequisites

- Flutter SDK matching the Dart constraint in `pubspec.yaml` (currently `sdk: ^3.9.2`)
- Android Studio / Xcode / VS tooling for your target platform
- A Supabase project (URL + anon key; service role key for seeding)

## Setup

```powershell
cd C:\src\IA\dzmarket
flutter pub get
```

## Environment

Local tests and live integration flows read values from `test/test_env.json`.
Start from the template:

```powershell
Copy-Item test\test_env.example.json test\test_env.json
```

Fill in the values in `test\test_env.json` (Supabase URL, anon key, test users, etc.).

Runtime config for web lives in `web/config.json` (copy from `web/config.example.json`).
For Android build flavors, use `--dart-define` values (see "Build flavors").

## Run

```powershell
flutter run
```

## Build flavors (Android)

Flavors are `dev`, `staging`, and `prod`. Pass the flavor and defines:

```powershell
flutter run --flavor dev --dart-define=APP_ENV=dev --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Firebase on Android uses `google-services.json` per flavor:

```
android/app/src/dev/google-services.json
android/app/src/staging/google-services.json
android/app/src/prod/google-services.json
```

Google Maps API key (Android):

```powershell
flutter run --flavor dev -PGOOGLE_MAPS_API_KEY=your_key_here
```

Release signing:

```powershell
Copy-Item android\key.properties.example android\key.properties
# Update android\key.properties with your keystore values.
```

## Firebase

Analytics and Crashlytics are enabled in release builds by default. You can override:

```powershell
--dart-define=ENABLE_ANALYTICS=false --dart-define=ENABLE_CRASHLYTICS=false
```

Web Firebase config comes from `web/config.json` (see `web/config.example.json`).
Android uses `google-services.json` per flavor.

Firebase setup (placeholders to replace):

```
android/app/src/dev/google-services.json
android/app/src/staging/google-services.json
android/app/src/prod/google-services.json
web/config.json
```

Run commands:

```powershell
flutter run --flavor dev -t lib/main.dart --dart-define=APP_ENV=dev
flutter run --flavor staging -t lib/main.dart --dart-define=APP_ENV=staging
flutter run --flavor prod -t lib/main.dart --dart-define=APP_ENV=prod

flutter run -d chrome --dart-define=APP_ENV=dev
flutter build web --dart-define=APP_ENV=prod
```

## Analyze

```powershell
flutter analyze
```

## Tests

Unit/widget tests:

```powershell
flutter test
```

Integration tests:

```powershell
flutter test integration_test\courier_flow_test.dart
```

Live courier flow (requires test env and an emulator/device):

```powershell
.\scripts\run_live_courier_test.ps1
```

## CI

Local CI equivalent:

```powershell
.\scripts\ci.ps1
```

## Supabase seed

The seed script uses the Supabase REST API with a service role key.
Set the environment variables, then run:

```powershell
$env:SUPABASE_URL="https://your-project.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"
.\scripts\seed_supabase.ps1
```

## Notes

- `test/test_env.json` contains secrets; keep it local.
- If you change data models, update Supabase migrations in `supabase/migrations`.
