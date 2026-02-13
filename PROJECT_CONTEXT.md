# PROJECT_CONTEXT

Last updated: 2026-02-12

## 1) Project objective
DZMarket is a mobile-first Algerian marketplace app (Flutter + Supabase) for:
- Acheter / vendre des articles.
- Passer commande (principalement COD).
- Gerer livraison multi-transporteurs.
- Suivre statut de commande et chat vendeur/acheteur.
- Moderation et supervision via superadmin.

## 2) Active actors and business scope
Active roles in app:
- `buyer`
- `seller`
- `superadmin`

Legacy note:
- DB role `admin` is treated as `superadmin` in app model.

Core rule:
- One canonical chat room per `(buyer_id, seller_id, product_id)` regardless of delivery mode/courier/order count.

## 3) Tech stack
Frontend:
- Flutter (Android first, also iOS/Web/Desktop targets).
- State/services pattern in `lib/src/services`.
- FR/AR i18n JSON files in `assets/i18n/`.

Backend:
- Supabase Postgres + RLS + Realtime + Storage + Edge Functions.
- SQL RPC for atomic flows (`create_order`, `send_message`, `ensure_order_conversation`, etc.).

Ops:
- GitHub Actions CI: `.github/workflows/ci.yml`.
- Daily cron monitor: `.github/workflows/job-runner-cron.yml`.

## 4) External services
Couriers integrated:
- Yalidine
- EcoTrack
- ZR Express

Content moderation:
- Sightengine via Edge Function `moderate-content`.

Courier integration reference docs:
- `skill_yallidine/SKILL.md`
- `skill_ecotrack/ecotrack.md`
- `skill_zrexpress/zrexpress.md`

## 5) Folder structure (high level)
- `lib/`: Flutter app source (features/models/services/widgets).
- `assets/i18n/`: translations FR/AR.
- `assets/branding/`: branding UI assets.
- `supabase.sql`: consolidated idempotent schema/bootstrap.
- `supabase/migrations/`: incremental SQL migrations.
- `supabase/functions/`: Edge Functions (shipment, cron, moderation, etc.).
- `.github/workflows/`: CI and operations workflows.
- `docs/`: project dossier and supporting docs.
- `test/`, `integration_test/`: tests.
- `logos/`: source brand/logo files.

## 6) Conventions
Language/UX:
- UI text must exist in FR and AR.
- Add any new label in both:
  - `assets/i18n/fr.json`
  - `assets/i18n/ar.json`

Code/data:
- Dart: camelCase.
- SQL: snake_case.
- Status values: lowercase tokens.
- Keep role model aligned to 3 active actors (buyer/seller/superadmin).

Chat/order logic:
- System events are posted in chat via `post_order_event`.
- Dedupe keys must be stable to avoid duplicate system messages.

## 7) DB and migration rules (important)
Baseline + incremental model:
- `supabase.sql` is the central baseline schema (idempotent blocks).
- Every production DB change should be added as a timestamped file in `supabase/migrations/`.
- Keep `supabase.sql` synchronized with validated migration logic so fresh environments are reproducible.

Current recent migrations:
- `20260211190000_chat_single_room_per_thread.sql`
- `20260212003000_order_duplicate_guard_refine.sql`
- `20260212170000_arranged_delivery_guards.sql`
- `20260212200000_courier_parcel_rules.sql`

## 8) Runtime/env variables
Flutter app required defines:
- `APP_ENV` (`dev|staging|prod`)
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Supabase functions required/optional secrets:
- Common: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- Moderation: `SIGHTENGINE_USER`, `SIGHTENGINE_SECRET`, optional `SIGHTENGINE_MODELS`, `SIGHTENGINE_TEXT_CATEGORIES`, `MODERATION_FAIL_OPEN`
- Courier: optional `ECOTRACK_BASE_URL`
- Cron tuning: `RETURNS_SYNC_MAX_ORDERS`, `RETURNS_SYNC_PAGE_SIZE`, `APP_ERRORS_RETENTION_DAYS`, etc.

## 9) Useful commands
App run:
```bash
flutter pub get
flutter run --flavor dev -t lib/main.dart --dart-define-from-file=test/test_env.json
```

USB run:
```bash
flutter run -d <DEVICE_ID> --flavor dev -t lib/main.dart --dart-define-from-file=test/test_env.json --no-resident
```

Quality:
```bash
flutter analyze
flutter test
```

Supabase function deploy:
```bash
supabase functions deploy create_shipment
supabase functions deploy job-runner
supabase functions deploy moderate-content
supabase functions deploy validate-courier
supabase functions deploy courier-locations
```

## 10) Important files and paths
- `README.md`
- `config.md`
- `supabase.sql`
- `supabase/functions/create_shipment/index.ts`
- `supabase/functions/job-runner/index.ts`
- `supabase/functions/moderate-content/index.ts`
- `.github/workflows/job-runner-cron.yml`
- `E2E_MANUAL_TEST_CASES.md`
- `E2E_MANUAL_TEST_CASES_AR.md`
- `NEXT_UPDATES.md`
- `NEXT_STEPS.md`
- `logos/Logo_DZM1.png`
