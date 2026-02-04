# Project Configuration (DZMarketAI)

## Packages & Flavors
- Android namespace/applicationId: `com.dzmarket.app`
- Flavors: `dev` (suffix .dev, name DZMarketAI Dev), `staging` (suffix .staging, name DZMarketAI Staging), `prod` (no suffix, name DZMarketAI)
- Google Maps placeholder: `GOOGLE_MAPS_API_KEY`

## Firebase
- Prod google-services.json present for package `com.dzmarket.app`
- Dev/staging google-services.json: placeholders (need real files)
- Web config: `web/config.json` with dev/staging/prod; values currently REPLACE_ME placeholders with __PLACEHOLDER__ flags.

## Supabase
- SUPABASE_URL: https://maumwzbvzbcamvlivqpe.supabase.co
- SUPABASE_ANON_KEY: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1hdW13emJ2emJjYW12bGl2cXBlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ3MDk5ODAsImV4cCI6MjA4MDI4NTk4MH0.fSrV_4iVQcmykf2hkk_CPN8w8E3iEsbiM8m5Cxxjd7Q

## Run Commands
- Dev:    flutter run --flavor dev -t lib/main.dart --dart-define=APP_ENV=dev --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
- Stg:    flutter run --flavor staging -t lib/main.dart --dart-define=APP_ENV=staging --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
- Prod:   flutter run --flavor prod -t lib/main.dart --dart-define=APP_ENV=prod --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
- Web:    flutter run -d chrome --dart-define=APP_ENV=dev (or staging/prod)
- Doctor: .\scripts\doctor_firebase.ps1

## Files of Interest
- android/app/src/prod/google-services.json (real for com.dzmarket.app)
- android/app/src/dev|staging/google-services.json (placeholders)
- web/config.json (placeholders)
- lib/src/config/firebase_web_config_loader.dart (rootBundle loader, returns null on placeholders)
- scripts/doctor_firebase.ps1 (checks placeholder/missing)

## Known Issues/Notes
- App crashes at startup if SUPABASE_URL/ANON_KEY not supplied via dart-define.
- To run without Firebase, need real google-services.json per flavor or adjust plugin; currently prod only is real.
