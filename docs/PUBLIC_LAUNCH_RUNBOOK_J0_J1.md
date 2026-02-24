# DZMarket - Public Launch Runbook (J0/J1)

## Scope
- Controlled public launch with progressive traffic ramp.
- Goal: keep core flows stable while opening to all users.

## Preconditions
- Latest release deployed on production.
- SSH access available on production server.
- `.\scripts\sli_quick_check.ps1` available locally.

## J0 Timeline

### T0 - Launch Start
1. Health checks:
```cmd
curl.exe -I https://app.dzmarket.pro
curl.exe -I https://api.dzmarket.pro
```
2. SLI check:
```powershell
.\scripts\sli_quick_check.ps1 -WindowMinutes 10 -SampleCount 30
```
3. If PASS: open to ~25% traffic.

### T+30 min
1. Manual smoke:
- login/logout
- create listing
- checkout/order
- seller `Mes ventes` -> `Ouvrir label`
- forgot/reset password
2. Run SLI check again.

### T+2h
- If stable: open to ~50% traffic.
- Run SLI check.

### T+4h
- If stable: open to 100% traffic.
- Run SLI check.

### T+6h / T+12h / T+24h
- Re-run SLI check each slot.
- Verify:
  - auth and mail flows
  - listing creation
  - order + shipment label flows
  - DB active connections
  - container health

## J1 Timeline (24h-48h)
- Run SLI check every 2-4h:
```powershell
.\scripts\sli_quick_check.ps1 -WindowMinutes 10 -SampleCount 30
```
- Keep incident channel active.
- If stable for 48h: exit reinforced monitoring mode.

## Rollback Trigger (Immediate)
Rollback if any of these persists:
- repeated critical user failures
- sustained high latency beyond SLO
- core flow broken (auth/order/label)

## Rollback Actions
1. Reduce traffic exposure.
2. Redeploy previous web bundle.
3. Validate auth/kong/db services.
4. Re-run `sli_quick_check.ps1`.
5. Resume rollout only after PASS.

## Go/No-Go Rule
- GO: SLI PASS + smoke PASS + no P1/P2.
- NO-GO: any critical flow unstable or SLI consistently failing.
