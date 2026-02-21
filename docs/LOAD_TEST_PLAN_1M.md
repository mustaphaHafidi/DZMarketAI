# Load Test Plan - DZMarket 1M Users/Year

## 1) Goal
Validate that DZMarket can scale progressively toward 1M users/year with controlled latency, failure rate, and cost.

## 2) Test Tooling
Primary:
- k6 for API load tests (HTTP + thresholds)

Optional:
- Playwright for end-to-end browser validation after load
- SQL scripts for DB query timing checks

## 3) Environment and Safety
- Run heavy load on staging first.
- Production tests must be off-peak and rate-limited.
- Use test users, test listings, and isolated labels/orders when possible.
- Keep rollback ready (web rollback + DB rollback).

## 4) Core Scenarios

### Scenario A - Browse heavy
- Endpoints: listings, filters, product details
- Mix: 70% reads
- Target: p95 < 350 ms, error rate < 1%

### Scenario B - Auth burst
- Endpoints: sign-in, refresh token, password reset request
- Mix: burst profile
- Target: p95 < 300 ms, error rate < 1%

### Scenario C - Commerce write path
- Endpoints: create offer, create order, stock lock related APIs
- Mix: 20% writes
- Target: p95 < 500 ms, no data inconsistency

### Scenario D - Seller operations
- Endpoints: create listing, upload images, seller dashboard reads
- Target: listing creation success > 99%, upload failure < 2%

### Scenario E - Shipment and label
- Endpoints: generate shipment, open signed label URL
- Target: label open success > 99.5%, no internal host/port leakage in URLs

## 5) Test Types and Ramp

### Baseline (30 min)
- 100-300 VUs equivalent
- Validate correctness + first bottlenecks

### Step load (60 min)
- Increase every 10 min (e.g. 300 -> 600 -> 900 -> 1200 VUs)
- Observe saturation points and recovery behavior

### Spike (15 min)
- Sudden x2 or x3 traffic jump
- Validate rate-limit and graceful degradation

### Soak (4-8 hours)
- Stable high load near expected peak
- Detect memory leaks, queue growth, DB drift

## 6) Pass/Fail Criteria

Pass if all are true:
- 5xx < 1% sustained
- No critical endpoint p95 breach for more than 2 consecutive windows
- No DB saturation (connections/locks) requiring manual restart
- No corruption in orders/stock/messages

Fail if one is true:
- 5xx >= 3% for 5 minutes
- p95 > 1.5 s on auth/orders for 10 minutes
- Label generation/open consistently failing

## 7) Execution Checklist
Before:
1. Confirm monitoring dashboards active.
2. Confirm alert channels active.
3. Prepare test dataset and cleanup SQL.

During:
1. Monitor p95/p99 and 5xx in real time.
2. Track DB CPU/RAM/connections.
3. Log timestamp of each ramp step.

After:
1. Export raw metrics.
2. Write bottleneck summary and scaling decision.
3. Create follow-up issues with owner + ETA.

## 8) Minimal k6 Structure (example)
- `load/auth.js`
- `load/listings.js`
- `load/orders.js`
- `load/shipments.js`
- `load/config.js` (base URL, keys, env)

## 9) Reporting Template
- Test date/time:
- Build/version:
- Environment:
- Peak load reached:
- SLO pass/fail:
- Main bottleneck:
- Immediate actions (24h):
- Short-term actions (7d):
- Long-term scaling actions (30d):
