# NEXT_STEPS

Last updated: 2026-02-12

## 1) Current state snapshot
Project is in active stabilization mode with strong progress on:
- Shipping rules consistency (arranged delivery vs courier label generation).
- Canonical chat thread behavior.
- Offline UX hardening.
- Branding/app icon rollout across platforms.

Release readiness is not complete yet; a focused P0 pass is still needed.

## 2) Recent changes (already done)
Backend/DB:
- Added arranged-delivery guards (`20260212170000_arranged_delivery_guards.sql`).
- Added courier parcel rule table and limits (`20260212200000_courier_parcel_rules.sql`).
- Refined duplicate-order guard and canonical chat logic from prior migrations.

Edge functions:
- `create_shipment`: supports arranged delivery bypass for label generation and enforces parcel rules.
- `job-runner`: reminders, stale order cancellation, return sync, retention cleanup, reliability metrics.
- `moderate-content`: fail-open support via `MODERATION_FAIL_OPEN`.

CI/Ops:
- `job-runner-cron.yml` now evaluates anomalies and opens/updates GitHub alerts.

Mobile UX:
- Better offline behavior and reduced noisy errors.
- Product image compatibility filtering (HEIC/HEIF handling).
- Checkout courier limits moved to optional detail action instead of persistent warning block.
- Listing photo cap behavior aligned with product flow.

## 3) Known issues / risks to verify now
1. Listing publish may fail with moderation 503 if moderation env is missing and fail-open is disabled.
2. Courier label flow must never trigger for arranged delivery (`livraison a convenir` / pickup-like modes).
3. Some legacy images may still not render if source URLs are invalid/unreachable.
4. Fresh environment setup can drift if migration order is skipped.

## 4) Reproduction commands
Local quality:
```bash
flutter analyze
flutter test
```

Run on USB:
```bash
flutter run -d <DEVICE_ID> --flavor dev -t lib/main.dart --dart-define-from-file=test/test_env.json --no-resident
```

Deploy critical functions:
```bash
supabase functions deploy create_shipment
supabase functions deploy job-runner
supabase functions deploy moderate-content
```

Manual API smoke (cron function):
```bash
curl -X POST "$SUPABASE_URL/functions/v1/job-runner" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data '{"source":"manual-smoke"}'
```

## 5) Prioritized TODO
### P0 (blocking for release)
- Validate all required function secrets in Supabase project:
  - `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
  - `SIGHTENGINE_USER`, `SIGHTENGINE_SECRET` (or explicitly keep fail-open policy)
- End-to-end test for 3 actors on latest DB migrations:
  - buyer order
  - seller shipment generation
  - superadmin moderation/errors
- Confirm arranged delivery does not request/generate shipping label.
- Confirm one chat room per buyer+seller+product for repeated orders.

### P1 (high value after P0)
- Full FR/AR manual matrix replay:
  - `E2E_MANUAL_TEST_CASES.md`
  - `E2E_MANUAL_TEST_CASES_AR.md`
- Validate courier limit UX copy and error messages for all 3 couriers.
- Final pass on offline UX consistency (browse/chat/profile).

### P2 (post-stabilization)
- Performance pass for image loading/cache under low network.
- Analytics/Crashlytics config cleanup (invalid firebase app id warnings if present).
- Stronger dashboards around conversion and shipment SLA.

## 6) Checklist before release candidate
- [ ] `flutter analyze` clean.
- [ ] `flutter test` pass.
- [ ] Critical functions deployed (`create_shipment`, `job-runner`, `moderate-content`).
- [ ] Latest migrations applied in target Supabase project.
- [ ] No open P0 bug.
- [ ] Manual smoke test done on real Android USB device.
- [ ] Cron run verified and GitHub alerts behavior validated.
- [ ] FR/AR texts complete for all new UX messages.

## 7) Notes for next handoff
- Keep using `supabase.sql` as baseline and keep it aligned with migrations.
- Do not introduce new features before P0 closure.
- Track all production-impact decisions in `NEXT_UPDATES.md` and this file.
