# DZMarketAI Configuration

This file documents runtime configuration without exposing secrets.

## Android Flavors
- Base package: `com.dzmarket.app`
- `dev`: app id suffix `.dev`, app name `DZMarketAI Dev`
- `staging`: app id suffix `.staging`, app name `DZMarketAI Staging`
- `prod`: no suffix, app name `DZMarketAI`

Source:
- `android/app/build.gradle.kts`

## Required Dart Defines
- `APP_ENV` (`dev`, `staging`, `prod`)
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

If missing, app startup fails by design (`main.dart` guard).

## Run Commands

### Dev
```bash
flutter run --flavor dev -t lib/main.dart \
  --dart-define=APP_ENV=dev \
  --dart-define=SUPABASE_URL=<YOUR_SUPABASE_URL> \
  --dart-define=SUPABASE_ANON_KEY=<YOUR_SUPABASE_ANON_KEY>
```

### Staging
```bash
flutter run --flavor staging -t lib/main.dart \
  --dart-define=APP_ENV=staging \
  --dart-define=SUPABASE_URL=<YOUR_SUPABASE_URL> \
  --dart-define=SUPABASE_ANON_KEY=<YOUR_SUPABASE_ANON_KEY>
```

### Prod
```bash
flutter run --flavor prod -t lib/main.dart \
  --dart-define=APP_ENV=prod \
  --dart-define=SUPABASE_URL=<YOUR_SUPABASE_URL> \
  --dart-define=SUPABASE_ANON_KEY=<YOUR_SUPABASE_ANON_KEY>
```

### USB (debug stability)
```bash
flutter run -d <DEVICE_ID> --flavor dev -t lib/main.dart \
  --dart-define=APP_ENV=dev \
  --dart-define=SUPABASE_URL=<YOUR_SUPABASE_URL> \
  --dart-define=SUPABASE_ANON_KEY=<YOUR_SUPABASE_ANON_KEY> \
  --no-dds
```

## Firebase Notes
- Keep per-flavor `google-services.json` valid.
- Keep Web config values outside Git when possible.

## Security
- Never commit `SUPABASE_SERVICE_ROLE_KEY`.
- Keep transporter tokens server-side only (Edge Functions or encrypted DB fields).

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

