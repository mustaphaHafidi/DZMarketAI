# Capacity Tracker - DZMarket

Use this file each week to decide when to scale infra and optimize hotspots.

## 1) Weekly Snapshot Table

| Week | MAU estimate | Peak req/min | API p95 (ms) | API 5xx % | App CPU % | DB CPU % | DB connections % | App RAM % | DB RAM % | Storage used % | Monthly cost EUR | Decision |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| YYYY-W01 |  |  |  |  |  |  |  |  |  |  |  |  |
| YYYY-W02 |  |  |  |  |  |  |  |  |  |  |  |  |
| YYYY-W03 |  |  |  |  |  |  |  |  |  |  |  |  |

## 2) Capacity Thresholds
- App CPU warning: > 70% (15 min)
- App RAM warning: > 80% (15 min)
- DB CPU warning: > 70% (15 min)
- DB connections warning: > 75% max
- Storage warning: > 75% used
- Critical: any metric > 90%

## 3) Decision Rules
Scale up now if one condition is true for 2 consecutive weekly reviews:
- p95 > 400 ms on critical endpoints
- 5xx > 1% sustained windows
- DB connections > 75% at peak
- Storage growth projects > 85% usage before next review

Scale optimization before scale-up if:
- High latency is from missing indexes or heavy queries
- Image payloads are oversized
- Caching opportunities are not used

## 4) Actions Log

| Date | Trigger | Action | Owner | ETA | Status |
|---|---|---|---|---|---|
| YYYY-MM-DD | Example: DB conn 82% | Add read replica | Infra | +7d | Open |

## 5) Cost Guardrails
- Phase A target: 200-400 EUR/month
- Phase B target: 400-900 EUR/month
- Phase C target: 900-1800 EUR/month

If cost increases > 20% month over month:
1. Identify top cost driver (compute, storage, egress)
2. Validate business gain from the extra spend
3. Decide keep/reduce with measurable SLO impact

## 6) Monthly Summary (copy each month)
- Reliability trend:
- Latency trend:
- Growth trend:
- Cost trend:
- Top 3 risks:
- Top 3 actions next month:
