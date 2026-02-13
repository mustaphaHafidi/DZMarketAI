# NEXT_STEPS

Last updated: 2026-02-13

## 1) Current state snapshot
Project is in stabilization mode and technically close to release candidate.
Major backend and UX paths now work with:
- One canonical chat room per buyer/seller/product.
- Multi-courier shipping including Guepex.
- Moderation flow wired in listing creation.
- Improved chat hub UX and better offline behavior.

## 2) Recent changes (already done)
Backend and DB:
- Added courier parcel rule support and guards in `supabase.sql` and migrations.
- Added Guepex courier support end-to-end.
- Added offers compatibility guards for legacy DB columns (`updated_at`, `counter_amount`, etc.).

Edge Functions:
- `create_shipment` supports Guepex and better tracking fallback behavior.
- `validate-courier` and `courier-locations` support Guepex credentials and territory loading.
- `moderate-content` deployed with strict policy option (`MODERATION_FAIL_OPEN`).
- `job-runner` remains active for reliability and transport sync.
- Added anti-surge controls on courier APIs:
- retry/backoff on transient failures (`429`, `5xx`, timeout),
- per-carrier throttling using `consume_rate_limit`,
- same reliability layer aligned across `create_shipment`, `validate-courier`, `courier-locations`, `job-runner`.

Mobile app:
- Chat hub redesigned for cleaner cards, compact offline banner, improved search/unread.
- Offer cards interaction deduped in chat room (only latest card actionable per offer).
- Listing creation improved:
- category picker with search and recent history,
- moderation outcome handling in publish flow,
- crash fix for unmodifiable list in category step.

Ops:
- `moderate-content` deployed successfully.
- `MODERATION_FAIL_OPEN=false` configured for strict moderation behavior.

## 3) Known issues / active risks
1. Offer flow needs final E2E validation for no duplicate visual cards in all edge cases.
2. Arranged delivery chat messages must stay coherent and must not trigger label generation in seller sales flow.
3. Some legacy environments may still miss columns if not fully migrated (run `supabase db push`).
4. Firebase warning (`Invalid google_app_id`) can pollute logs if flavor config is not clean.
5. Carrier throttle thresholds may need production tuning (too strict = delays, too loose = API bans).

## 4) Reproduction and validation commands
Quality:
```bash
flutter analyze
flutter test
```

Run on USB:
```bash
flutter run -d <DEVICE_ID> --flavor dev -t lib/main.dart --dart-define-from-file=test/test_env.json --no-resident
```

Deploy core functions:
```bash
supabase functions deploy validate-courier
supabase functions deploy courier-locations
supabase functions deploy create_shipment
supabase functions deploy job-runner
supabase functions deploy moderate-content
```

## 5) Prioritized TODO
### P0 (release blocking)
- Run full offer lifecycle E2E in real accounts:
- buyer creates offer,
- seller accepts/refuses/counters from same chat message flow,
- buyer receives updates and can re-offer.
- Verify arranged delivery does not create shipment work items in seller sales.
- Verify latest `supabase.sql` executes cleanly on fresh and existing DBs.

### P1 (high value)
- Complete FR/AR manual replay of updated cases in `E2E_MANUAL_TEST_CASES.md`.
- Improve product detail visual hierarchy for conversion (without touching core logic).
- Add monitoring panel for courier API failures by carrier and rate-limit hit counters.

### P2 (post-RC)
- Tighten analytics and crash dashboards by feature domain.
- Add richer moderation review queue metrics.
- Improve low-network media loading strategy.

## 6) Checklist before release candidate
- [ ] `flutter analyze` clean.
- [ ] `flutter test` pass.
- [ ] DB up to date via migrations and `supabase.sql` sanity.
- [ ] Functions deployed (`validate-courier`, `courier-locations`, `create_shipment`, `job-runner`, `moderate-content`).
- [ ] Offer lifecycle validated E2E on device.
- [ ] Arranged delivery flow validated E2E (no wrong shipment generation).
- [ ] FR/AR copy reviewed for new UX and moderation messages.

## 7) Handoff notes
- Keep documenting production-impact updates in this file and `NEXT_UPDATES.md`.
- Avoid new large features until P0 closure is complete.
