# DZMarket Project Map

Read this for general orientation only. Prefer live code over old docs.

## App Shape

- Flutter app with Supabase backend and Firebase services.
- Main app bootstrap: `lib/main.dart`.
- Router and auth redirects: `lib/src/router.dart`.
- App shell: `lib/src/app.dart`.
- Core services: `lib/src/services/`.
- Feature UI: `lib/src/features/`.
- Supabase migrations: `supabase/migrations/`.
- Edge functions: `supabase/functions/`.
- Android app id: `com.dzmarket.app`.
- iOS bundle id: `com.dzmarket.app`.

## Bootstrap

`lib/main.dart` initializes:

- locale and network preferences
- runtime config from dart defines
- Supabase with manual auth callback handling
- Firebase, Crashlytics, FCM push
- app error logging
- translations, connectivity, in-app notifications

If startup fails on production builds, check missing `SUPABASE_URL` or `SUPABASE_ANON_KEY` first.

## Routing

`lib/src/router.dart` owns:

- sign-in, sign-up, reset password
- `/auth/callback` and `/auth/call`
- legal routes
- notifications
- seller orders/dashboard/listings/shipments/couriers
- admin errors/moderation
- product detail, order chat, order tracking
- public browse policy and marketing landing behavior

## Source Of Truth

- Current code beats `docs/HANDOVER_PC2.md`; the handover is useful only as historical context.
- `pubspec.yaml` version may differ from CI override values in `codemagic.yaml`.
- Production server state must be verified live before claiming a deploy or fix is complete.

