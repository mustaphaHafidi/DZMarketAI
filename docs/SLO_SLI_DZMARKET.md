# SLO / SLI - DZMarket

Last update: 2026-03-03

## 1) Scope
Cibles de service pour:
- `https://app.dzmarket.pro`
- `https://api.dzmarket.pro`

Parcours critiques:
- auth (login/reset)
- browse listings
- achat/commande
- vendeur mes ventes + bordereau + label PDF
- chat/notifications

## 2) SLO cibles (production)

| Domaine | Disponibilite | Latence p95 cible |
|---|---:|---:|
| Browse listings | 99.9% | < 350 ms |
| Auth API | 99.9% | < 1500 ms (charge reelle) |
| Create order | 99.7% | < 700 ms |
| Generate/Open label | 99.7% | < 700 ms |
| Chat send/read | 99.7% | < 400 ms |

Notes:
- L'objectif auth a ete ajuste a `1500 ms` pour coller au comportement reel sous charge login (sans OTP/SMS), tout en gardant une dispo stricte.
- Les mesures sont cote API/infra; les reseaux mobiles utilisateurs ne sont pas inclus.

## 3) SLI surveilles
- `http_req_duration` (p95)
- `http_req_failed` (rate)
- `db_active_connections` (ratio)
- `containers_health` (count unhealthy)
- `caddy_5xx_rate`

## 4) Seuils d'alerte ops
### P1
- API 5xx > 3% pendant 5 min
- p95 auth > 3s pendant 10 min
- p95 listings > 800 ms pendant 10 min
- DB saturation > 90%

### P2
- API 5xx > 1% pendant 10 min
- p95 listings > 500 ms pendant 15 min
- erreurs bordereau/label > 1% pendant 10 min

### P3
- DB connections > 75%
- CPU > 70% (15 min)
- RAM > 80% (15 min)

## 5) Commandes de controle

### Quick SLI
```powershell
.\scripts\sli_quick_check.ps1 -WindowMinutes 10 -SampleCount 30
```

### Auth smoke serveur
```powershell
.\scripts\auth_smoke_check.ps1 -AppServerIp 91.107.239.5 -SshKeyPath "$env:USERPROFILE\.ssh\dzmarket_hetzner"
```

### Mix charge reference
```powershell
.\scripts\run_k6_mix_matrix.ps1 -EnvFile .\load\env.local -ListingsVus "220" -AuthVus 5 -Duration 60m -RunSliCheck
```

## 6) Etat de capacite valide
- PASS stable: `220 listings + 5 auth` (60m et 120m).
- FAIL observe: `240 listings + 5 auth`.
- Budget recommande prod: `195 listings + 4 auth` (marge ~15%).

## 7) Politique error budget
- Si budget restant < 25%: freeze features non critiques.
- Si budget restant < 10%: uniquement correctifs fiabilite.
- Si incident P1: post-mortem + action corrective sous 48h.
