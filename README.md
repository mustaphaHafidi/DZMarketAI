# DZMarketAI

DZMarketAI is a Flutter marketplace app for Algeria, backed by Supabase.

## Product Scope
- Mobile-first buyer/seller flows.
- Single canonical chat thread per `buyer + seller + product`.
- Offer flow handled inside chat (accept/refuse/counter-offer).
- Multi-courier shipping: Yalidine, EcoTrack, ZR Express, Guepex.
- Superadmin moderation and app-error monitoring.

## Active Roles
- `buyer`
- `seller`
- `superadmin`

Legacy note:
- DB role `admin` is mapped to `superadmin` in the app model.

## Main Workflows
- Auth and profile setup (FR/AR).
- Browse -> filters -> product detail.
- Buyer sends offer from product detail -> seller responds in same chat room.
- Buy now with stock reservation (`create_order` RPC).
- Seller shipment generation (`create_shipment` Edge Function).
- Arranged delivery ("livraison a convenir") stays chat-driven and must not require label generation.

## Tech Stack
- Flutter (Android first, plus iOS/Web/Desktop targets).
- Supabase Postgres + RLS + Storage + Realtime + Edge Functions.
- Firebase Analytics/Crashlytics telemetry.

## Repo Layout
- `lib/` app source.
- `assets/i18n/` FR/AR translations.
- `supabase.sql` baseline schema (idempotent blocks).
- `supabase/migrations/` incremental SQL migrations.
- `supabase/functions/` Edge Functions.
- `.github/workflows/` CI and cron jobs.
- `docs/` product/business documentation.

## Local Run
```bash
flutter pub get
flutter run --flavor dev -t lib/main.dart --dart-define-from-file=test/test_env.json
```

USB run:
```bash
flutter run -d <DEVICE_ID> --flavor dev -t lib/main.dart --dart-define-from-file=test/test_env.json --no-resident
```

## Database and Backend
```bash
supabase db push
supabase functions deploy validate-courier
supabase functions deploy courier-locations
supabase functions deploy create_shipment
supabase functions deploy job-runner
supabase functions deploy moderate-content
```

## Jobs and Operations
- `ci.yml`: analyze + tests on push/PR.
- `job-runner-cron.yml`: daily `03:00 UTC` reliability checks.
- Cron validates courier sync and opens/updates GitHub alerts on anomalies.

## Key Docs
- `PROJECT_CONTEXT.md`
- `NEXT_STEPS.md`
- `NEXT_UPDATES.md`
- `infra/HETZNER_MIGRATION_RUNBOOK.md`
- `infra/hetzner/MIGRATION_INVENTORY.md`
- `infra/hetzner/ENV_MAPPING_DRAFT.md`
- `infra/hetzner/SERVERS_CONFIG_AND_KEYS.md`
- `E2E_MANUAL_TEST_CASES.md`
- `E2E_MANUAL_TEST_CASES_AR.md`
- `GUEPEX_INTEGRATION_DOCUMENTATION.md`
- `SKILL_DZmarketAI.md`
- `Skill_DB.md`

## Security Notes
- Never commit secrets.
- Keep `SUPABASE_SERVICE_ROLE_KEY` server-side only.
- Keep labels private in `storage.buckets.labels`.
- For strict moderation mode, set `MODERATION_FAIL_OPEN=false` in Edge Function secrets.

