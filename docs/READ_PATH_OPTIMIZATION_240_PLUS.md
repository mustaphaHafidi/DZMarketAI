# Read-Path Optimization Plan (Unlock 240+ Listings VUs)

## Goal
Move from current stable capacity (`220 listings + 5 auth`) to `240+ listings + 5 auth` while keeping:
- listings p95 < 350 ms
- http_req_failed < 1%

## Priority 1 - Query/Index
1. Measure top browse queries during load:
   - `/rest/v1/products?select=...&order=created_at.desc&limit=24`
   - filtered price query
   - filtered location query
2. Capture query plans:
   - `EXPLAIN (ANALYZE, BUFFERS)` on each browse query.
3. Add/adjust indexes for hot predicates and ordering:
   - `created_at desc`
   - `price`
   - `location_wilaya`
4. Re-run `220+5` for 30m to confirm no regression.

## Priority 2 - Caching
1. Add short TTL cache (30-120s) for anonymous browse endpoints.
2. Cache key dimensions:
   - query string
   - language
   - pagination
3. Keep cache bypass for authenticated/private reads.
4. Re-test `230+5`, then `240+5`.

## Priority 3 - API/DB Guardrails
1. Keep strict pagination (`limit <= 24`).
2. Avoid wide `select *` in browse flows.
3. Monitor DB active connections and lock wait during tests.
4. Alert on p95 drift before threshold breach.

## Validation Sequence
1. Baseline check: `220+5 / 30m`
2. Target check: `240+5 / 30m`
3. Soak check on winning profile: `120m`
4. Run `scripts/sli_quick_check.ps1` from SSH-stable host.

## Exit Criteria
- `240+5` passes 30m and 120m.
- SLI quick check PASS.
- No increase in 5xx or unhealthy containers.
