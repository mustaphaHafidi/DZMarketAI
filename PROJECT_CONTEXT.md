# PROJECT_CONTEXT

Last updated: 2026-02-13

## 1) Project objective
DZMarket is a mobile-first Algerian marketplace app (Flutter + Supabase) for:
- Acheter / vendre des articles.
- Negocier via offres en chat.
- Passer commande (COD et flux livraison).
- Gerer expedition multi-transporteurs.
- Suivre commande via chat + timeline transporteur.
- Moderation et supervision via superadmin.

## 2) Active actors and core business rules
Active roles:
- `buyer`
- `seller`
- `superadmin`

Legacy:
- DB role `admin` is mapped to `superadmin` in app behavior.

Core chat rule:
- Always one canonical chat room per `(buyer_id, seller_id, product_id)`.
- This remains true across all delivery modes, multiple orders, and offer cycles.

Offer rule:
- Offer lifecycle is chat-driven (propose, accept, refuse, counter-offer).
- Seller-side "Mes ventes" must not create shipment workload from an offer-only action.

Delivery rule:
- Courier-backed delivery can generate a label from seller side.
- "Livraison a convenir" is chat-first and must not force label generation.

## 3) Tech stack
Frontend:
- Flutter (Android first, plus iOS/Web/Desktop targets).
- Service/repository architecture in `lib/src/services`.
- FR/AR localizations in `assets/i18n`.

Backend:
- Supabase Postgres + RLS + Realtime + Storage + Edge Functions.
- SQL RPC for atomic operations (`create_order`, `send_message`, `ensure_order_conversation`, etc.).

Ops:
- CI workflow: `.github/workflows/ci.yml`
- Daily cron workflow: `.github/workflows/job-runner-cron.yml`

## 4) External services
Couriers integrated:
- Yalidine
- EcoTrack
- ZR Express
- Guepex

Moderation provider:
- Sightengine via `supabase/functions/moderate-content`.

Reference docs:
- `GUEPEX_INTEGRATION_DOCUMENTATION.md`
- `skill_yallidine/SKILL.md`
- `skill_ecotrack/ecotrack.md`
- `skill_zrexpress/zrexpress.md`

## 5) Folder structure (high level)
- `lib/`: Flutter app source.
- `assets/i18n/`: FR/AR translations.
- `supabase.sql`: baseline schema/bootstrap (idempotent).
- `supabase/migrations/`: timestamped migrations.
- `supabase/functions/`: Edge Functions.
- `.github/workflows/`: CI and cron jobs.
- `docs/`: product/business docs.
- `test/`, `integration_test/`: automated tests.

## 6) Conventions
Language:
- Every user-facing text should be available in FR and AR.

Naming:
- Dart: camelCase.
- SQL: snake_case.
- Status enums: lowercase tokens.

Data/flow:
- Keep dedupe keys stable for system chat events.
- Prefer idempotent SQL changes in `supabase.sql`.
- Mirror production-impact DB changes in migrations.

## 7) DB and migration rules
- `supabase.sql` is baseline for fresh environments.
- Every DB change should also exist in `supabase/migrations/*.sql`.
- Apply latest migrations before E2E validation.

Recent key migrations:
- `20260211190000_chat_single_room_per_thread.sql`
- `20260212003000_order_duplicate_guard_refine.sql`
- `20260212170000_arranged_delivery_guards.sql`
- `20260212200000_courier_parcel_rules.sql`
- `20260213010000_guepex_courier_support.sql`

## 8) Runtime and env variables
Flutter runtime defines:
- `APP_ENV`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Edge Function secrets:
- Common: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- Moderation: `SIGHTENGINE_USER`, `SIGHTENGINE_SECRET`, optional `SIGHTENGINE_MODELS`, `SIGHTENGINE_TEXT_CATEGORIES`, `MODERATION_FAIL_OPEN`
- Courier optional: `ECOTRACK_BASE_URL`, `GUEPEX_BASE_URL`
- Job-runner optional: `RETURNS_SYNC_MAX_ORDERS`, `RETURNS_SYNC_PAGE_SIZE`, `LABEL_REMINDER_MAX_ORDERS`

Policy note:
- `MODERATION_FAIL_OPEN=false` means strict blocking if moderation service is unavailable.

Reliability note:
- Courier calls are protected with retry/backoff (`429/5xx/timeout`) and per-carrier throttling via `consume_rate_limit`.
- Functions covered: `create_shipment`, `courier-locations`, `validate-courier`, `job-runner`.

## 9) Useful commands
Run app:
```bash
flutter pub get
flutter run --flavor dev -t lib/main.dart --dart-define-from-file=test/test_env.json
```

Run on USB:
```bash
flutter run -d <DEVICE_ID> --flavor dev -t lib/main.dart --dart-define-from-file=test/test_env.json --no-resident
```

Quality checks:
```bash
flutter analyze
flutter test
```

Backend deploy:
```bash
supabase db push
supabase functions deploy validate-courier
supabase functions deploy courier-locations
supabase functions deploy create_shipment
supabase functions deploy job-runner
supabase functions deploy moderate-content
```

## 10) Important files and paths
- `README.md`
- `PROJECT_CONTEXT.md`
- `NEXT_STEPS.md`
- `NEXT_UPDATES.md`
- `supabase.sql`
- `supabase/functions/create_shipment/index.ts`
- `supabase/functions/job-runner/index.ts`
- `supabase/functions/moderate-content/index.ts`
- `supabase/functions/courier-locations/index.ts`
- `supabase/functions/validate-courier/index.ts`
- `.github/workflows/job-runner-cron.yml`
- `E2E_MANUAL_TEST_CASES.md`
- `E2E_MANUAL_TEST_CASES_AR.md`
