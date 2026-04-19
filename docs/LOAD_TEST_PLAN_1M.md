# Load Test Plan - DZMarket (1M Users/Year)

Last update: 2026-03-03

## 1) But
Valider la capacite DZMarket pour une montee progressive vers 1M utilisateurs/an, sans depassement SLO.

## 2) Outils
- k6: charge API
- scripts PowerShell:
  - `scripts/run_k6_phase.ps1`
  - `scripts/run_k6_mix_matrix.ps1`
  - `scripts/sli_quick_check.ps1`
  - `scripts/auth_smoke_check.ps1`

## 3) SLO de reference charge
- Listings p95 < 350 ms
- Auth p95 < 1500 ms
- Taux erreurs < 1%

## 4) Scenarios cibles
- `load/listings.js` : lecture browse/filters
- `load/auth.js` : login/password flow
- `load/orders.js` : flux commandes
- `load/shipments.js` : labels/shipping

## 5) Resultats valides (dernieres campagnes)

| Campagne | Duree | Verdict |
|---|---:|---|
| 220 listings + 5 auth | 30m | PASS |
| 220 listings + 5 auth | 60m | PASS |
| 220 listings + 5 auth | 120m (soak) | PASS |
| 230 listings + 5 auth | 30m | borderline / instable selon fenetre |
| 240 listings + 5 auth | 30m | FAIL (p95 listings depasse) |

Conclusion capacite:
- Capacite stable certifiee: `220 + 5`.
- Budget prod recommande avec marge: `195 + 4`.

## 6) Execution standard

### A. Matrix de validation
```powershell
.\scripts\run_k6_mix_matrix.ps1 -EnvFile .\load\env.local -ListingsVus "220,230,240" -AuthVus 5 -Duration 30m -RunSliCheck
```

### B. Soak cible stable
```powershell
.\scripts\run_k6_mix_matrix.ps1 -EnvFile .\load\env.local -ListingsVus "220" -AuthVus 5 -Duration 120m -RunSliCheck
```

### C. Verif SLI rapide
```powershell
.\scripts\sli_quick_check.ps1 -WindowMinutes 10 -SampleCount 30
```

## 7) Regles PASS/FAIL
PASS si:
- Tous les seuils du scenario passent.
- `sli_quick_check` passe.
- Aucun incident critique (auth, ordre, label).

FAIL si:
- p95 depasse la cible sur fenetre soutenue.
- taux erreurs >= 1%.
- degradation operatoire (timeouts auth repetes, echec labels, 5xx soutenus).

## 8) Suite roadmap perf
1. Optimiser read-path browse (indexes + select plus fin).
2. Ajouter cache court TTL sur browse anonyme.
3. Revalider `230+5`, puis `240+5`.
4. Si PASS stable: recalculer budget prod.
