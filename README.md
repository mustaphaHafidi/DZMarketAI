# DZMarketAI

DZMarketAI is a Flutter marketplace app for Algeria with Supabase backend.

## Product Scope
- Mobile-first buyer/seller flows.
- Built-in chat per listing thread.
- Multi-courier shipping (Yalidine, Ecotrack, ZR Express).
- Superadmin moderation and app-error monitoring.

## Active Roles
- `buyer`
- `seller`
- `superadmin`

Note:
- Legacy `admin` values are treated as `superadmin` in the app model.

## Main Workflows
- Auth and profile setup (FR/AR).
- Browse -> filters -> product detail.
- Offer or buy now.
- Order creation with stock reservation.
- Seller label generation and shipment tracking.
- One canonical chat thread per `buyer + seller + product`.

## Tech Stack
- Flutter (Android, iOS, Web, Desktop targets).
- Supabase (Postgres, RLS, Storage, Realtime, Edge Functions).
- Firebase Analytics/Crashlytics (client telemetry).

## Repo Layout
- `lib/` app source.
- `assets/i18n/` FR/AR translations.
- `supabase.sql` main DB schema/bootstrap (idempotent sections).
- `supabase/migrations/` incremental SQL migrations.
- `supabase/functions/` Edge Functions.
- `.github/workflows/` CI + cron ops workflow.
- `infra/` self-host plan and infra notes.

## Local Run
1. Install Flutter and dependencies.
2. Run:

```bash
flutter pub get
flutter run --flavor dev -t lib/main.dart \
  --dart-define=APP_ENV=dev \
  --dart-define=SUPABASE_URL=<YOUR_SUPABASE_URL> \
  --dart-define=SUPABASE_ANON_KEY=<YOUR_SUPABASE_ANON_KEY>
```

USB device example:

```bash
flutter run -d <DEVICE_ID> --flavor dev -t lib/main.dart \
  --dart-define=APP_ENV=dev \
  --dart-define=SUPABASE_URL=<YOUR_SUPABASE_URL> \
  --dart-define=SUPABASE_ANON_KEY=<YOUR_SUPABASE_ANON_KEY> \
  --no-dds
```

## Database and Backend
- Apply base schema from `supabase.sql`.
- Apply new migrations from `supabase/migrations/`.
- Deploy required functions:

```bash
supabase functions deploy create_shipment
supabase functions deploy job-runner
supabase functions deploy validate-courier
supabase functions deploy courier-locations
```

## Jobs and Operations
- `ci.yml`: analyze + tests on push/PR.
- `job-runner-cron.yml`: daily `03:00 UTC` background checks.
  - Runs `job-runner` function.
  - Opens/updates GitHub issues on failures or anomalies.

## Key Docs
- `E2E_MANUAL_TEST_CASES.md` full manual QA matrix (FR).
- `E2E_MANUAL_TEST_CASES_AR.md` Arabic QA matrix (same IDs).
- `SKILL_DZmarketAI.md` current architecture and rules.
- `Skill_DB.md` DB and Supabase reference.
- `PLAN_1M_USERS.md` scale plan.
- `infra/SELF_HOST_SUPABASE_PLAN.md` self-host rollout path.

## Security Notes
- Do not commit secrets.
- Keep `SUPABASE_SERVICE_ROLE_KEY` only in secure env.
- Keep label files private (`labels` bucket).

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

