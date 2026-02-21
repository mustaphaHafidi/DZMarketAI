# SLO and SLI - DZMarket

## 1) Scope
This file defines service objectives for public traffic on:
- Web app: `app.dzmarket.pro`
- API: `api.dzmarket.pro`

Critical user journeys covered:
- Sign in / sign up
- Browse listings
- Open chat and send message
- Create listing
- Create order
- Open shipping label

## 2) SLO Targets (monthly)

| Journey | Availability SLO | Latency SLO |
|---|---:|---:|
| Browse listings (`GET /rest/v1/products`) | 99.9% | p95 < 350 ms |
| Auth (`/auth/v1/*`) | 99.9% | p95 < 300 ms |
| Chat send/read (messages endpoints + realtime fallback) | 99.7% | p95 < 400 ms |
| Create listing (metadata only) | 99.5% | p95 < 700 ms |
| Upload listing images (storage signed upload) | 99.5% | p95 < 1.5 s |
| Create order (`orders` + stock lock flow) | 99.7% | p95 < 500 ms |
| Open label URL (signed storage URL) | 99.7% | p95 < 700 ms |

Notes:
- Latency SLO is measured server-side at edge/API where possible.
- Mobile network variability is excluded from server SLO.

## 3) Error Budget
- Monthly budget for 99.9% availability: 43m 49s downtime
- Monthly budget for 99.7% availability: 2h 11m 27s downtime
- Monthly budget for 99.5% availability: 3h 39m 14s downtime

Policy:
- If remaining error budget < 25%, freeze non-critical releases.
- If remaining error budget < 10%, only reliability fixes are allowed.

## 4) SLI Definitions

### Availability SLI
`availability = successful_requests / total_requests`
- Success = HTTP 2xx/3xx (and expected 4xx for validated business cases)
- Failure = HTTP 5xx, timeouts, gateway errors

Data sources:
- Caddy access logs
- Kong upstream status metrics
- Synthetic probes (health checks)

### Latency SLI
- p50/p95/p99 by endpoint group
- Endpoint groups: auth, listings, orders, chat, storage-signed-urls

Data sources:
- Kong request latency
- Caddy request duration
- Optional app telemetry events

## 5) Alerting Rules

P1 (page immediately):
- API 5xx rate > 3% for 5 min
- p95 latency > 1.5 s for 10 min on auth or orders
- DB unavailable, replica lag critical, or disk > 90%

P2 (high priority):
- API 5xx rate > 1% for 10 min
- p95 latency > 800 ms for 15 min on listings/chat
- Storage upload failures > 2% for 10 min

P3 (normal priority):
- CPU > 70% for 30 min
- RAM > 80% for 30 min
- DB connections > 75% max

## 6) Operational Dashboards (minimum)
- Traffic: requests/min, unique users/day
- Reliability: 2xx/4xx/5xx by endpoint group
- Latency: p50/p95/p99 by endpoint group
- DB: CPU, RAM, connections, slow queries, lock waits
- Storage: object volume, upload failures, egress
- Business critical: order creation success, label open success

## 7) Review Cadence
- Daily: quick check of 5xx, p95, infrastructure saturation
- Weekly: capacity review and scaling decision
- Monthly: SLO report, error budget policy, threshold tuning
