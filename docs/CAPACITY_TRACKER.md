# Capacity Tracker - DZMarket

Last update: 2026-03-03

## 1) Snapshot hebdomadaire

| Week | MAU estimate | Mix test reference | Listings p95 (ms) | Auth p95 (ms) | API 5xx % | DB connections % | Decision |
|---|---:|---|---:|---:|---:|---:|---|
| 2026-W09 | n/a | 220 listings + 5 auth (60m) | 258 | 1310 | 0.00 | 2 | KEEP |
| 2026-W10 |  |  |  |  |  |  |  |
| 2026-W11 |  |  |  |  |  |  |  |

## 2) Seuils guardrails
- Listings p95 warning: > 350 ms
- Auth p95 warning: > 1500 ms
- API 5xx warning: > 1%
- DB connections warning: > 75%
- CPU warning: > 70%
- RAM warning: > 80%

## 3) Regles de decision
Scale/optimisation requis si, sur 2 revues consecutives:
- depassement p95 listings ou auth
- 5xx > 1% soutenu
- DB connections > 75%

## 4) Action log

| Date | Trigger | Action | Owner | ETA | Status |
|---|---|---|---|---|---|
| 2026-03-02 | reminders transporteur non emis (schema legacy) | patch job-runner + redeploy | Dev/Ops | done | Closed |
| YYYY-MM-DD |  |  |  |  |  |

## 5) Cible d'exploitation actuelle
- Budget prod recommande: `195 listings + 4 auth`
- Budget technique max valide: `220 listings + 5 auth`
