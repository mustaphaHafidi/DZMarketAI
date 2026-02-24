# DZMarket - Go/No-Go Public Launch Checklist

## 1) Gate Technique (must be PASS)

```powershell
.\scripts\run_quality_gate.ps1
.\scripts\run_k6_mix_matrix.ps1 -EnvFile .\load\env.local -ListingsVus "220" -AuthVus 5 -Duration 60m -RunSliCheck
.\scripts\sli_quick_check.ps1
```

Go criteria:
- `run_quality_gate.ps1` = PASS
- `mix_matrix 220+5 / 60m` = PASS
- `sli_quick_check.ps1` = PASS

## 2) Smoke Manuel Production (must be PASS)

Validate end-to-end on `https://app.dzmarket.pro`:
- Login/Logout (FR + AR)
- Sign-up + confirmation email
- Forgot/reset password flow
- Add listing as seller
- Buyer checkout/order flow
- Seller `Mes ventes` -> generate bordereau -> `Ouvrir label`
- Notifications + profile screens (FR + AR)

Go criteria:
- No blocking bug (P1/P2)
- No blank pages
- No major i18n key leaks (`auth.*`, `listing.*`, etc.)

## 3) Release Freeze

```powershell
git checkout main
git pull
git tag -a v1.0.0 -m "DZMarket public launch"
git push origin main --tags
```

Go criteria:
- Tag pushed successfully
- Release notes prepared

## 4) Backup + Rollback Ready

Before opening traffic:
- DB backup completed
- Previous web bundle archived (`dzmarket-web.zip` old version)
- Rollback command tested once on staging or prod dry run

Go criteria:
- Restore path documented
- Rollback can be done in < 15 min

## 5) Soft Launch (24h)

Open to limited real users for 24h.

Monitor every 2h:
- API p95
- HTTP error rate
- Auth timeouts
- DB active connections
- Label generation/open
- Mail delivery (confirmation + recovery)

Go criteria:
- No P1/P2 incident during 24h
- SLOs remain within thresholds

## 6) Public Launch (Large)

If Soft Launch is stable:
- Open access to all users
- Publish communication (web + social)
- Keep reinforced monitoring for 48h

Go criteria:
- No sustained degradation
- No critical flow broken

## 7) Post-Launch (48h)

```powershell
.\scripts\sli_quick_check.ps1
.\scripts\run_k6_mix_matrix.ps1 -EnvFile .\load\env.local -ListingsVus "220" -AuthVus 5 -Duration 30m -RunSliCheck
```

Then start optimization track for `240+5`.
