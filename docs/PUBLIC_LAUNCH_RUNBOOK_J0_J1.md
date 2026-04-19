# DZMarket - Public Launch Runbook (J0/J1)

Last update: 2026-03-03

## Objectif
Piloter un rollout public sans degrader les parcours critiques.

## Preconditions
- Derniere version prod deployee.
- Acces SSH actif (serveur app).
- Cle SSH valide locale (`dzmarket_hetzner`).

## J0 - Execution

### T0
```powershell
curl.exe -I https://app.dzmarket.pro
curl.exe -I https://api.dzmarket.pro
.\scripts\sli_quick_check.ps1 -WindowMinutes 10 -SampleCount 30 -SshKeyPath "$env:USERPROFILE\.ssh\dzmarket_hetzner"
```

### T+30 min
- Smoke manuel P0 (auth, listing, achat, ventes, label, i18n).
- Rejouer `sli_quick_check`.

### T+2h
- Nouvelle fenetre SLI.
- Verifier DB/containers/logs caddy.

### T+4h puis T+6h/T+12h/T+24h
- `sli_quick_check` toutes les 2h.
- `auth_smoke_check` au moins 2 fois (debut + fin J0).

## J1 (24h -> 48h)
- Continuer monitoring renforce toutes les 2-4h.
- Ouvrir incident si:
  - 5xx soutenus
  - p95 hors seuil
  - panne auth/label/checkout

## Rollback
Declenchement immediat si parcours P0 casse:
1. Revenir au bundle web precedent.
2. Recharger services critiques (kong/auth/functions si necessaire).
3. Rejouer `sli_quick_check` + smoke minimal.

## Definition de stabilite post-lancement
- 48h sans incident P1/P2.
- SLI PASS sur toutes les fenetres.
- Auth smoke PASS.
- Flux `achat -> bordereau -> label` stable.
