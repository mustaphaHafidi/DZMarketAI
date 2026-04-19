# Plan 1M Utilisateurs/An - DZMarket

Last update: 2026-03-03

## 1) Objectif
Atteindre 1M utilisateurs/an avec croissance progressive, SLO tenus, et couts maitrises.

## 2) Hypotheses de charge
- Parcours dominant: browse listings (lecture).
- Flux critiques: auth, commande, bordereau/label, notifications.
- Saisonnalite forte (soir/weekend + pics promotionnels).

## 3) Capacite validee aujourd'hui
- Mix stable certifie: `220 listings + 5 auth`.
- Echec constate: `240 listings + 5 auth` (p95 listings depasse).
- Budget prod recommande (marge ~15%): `195 listings + 4 auth`.

## 4) Lecture business du budget `195 + 4`
Ordre de grandeur actuel:
- ~185-200 parcours listings simultanes stables
- ~4 logins simultanes stables
- API sans erreur soutenue si trafic reste dans ce budget

## 5) Architecture cible
- Front: Flutter web/mobile.
- API: Supabase self-host (Kong/Auth/PostgREST/Realtime/Storage/Functions).
- Infra: Hetzner + Caddy + MinIO + PostgreSQL.
- Domains: `app.dzmarket.pro`, `api.dzmarket.pro`, `www.dzmarket.pro` -> redirect app.

## 6) Phases de croissance
### Phase A (actuelle)
- Exploitation large avec budget `195 + 4`.
- Monitoring renforce et runbooks actifs.

### Phase B
- Optimisation read-path browse (indexes, select, pagination stricte).
- Cache court TTL sur browse anonyme.
- Re-test `230+5`, puis `240+5`.

### Phase C
- Si `240+5` stable:
  - recalcul budget prod
  - plan scale infra (DB lectures/cache/LB) selon cout/impact.

## 7) Seuils d'upgrade
- p95 listings > 350ms soutenu
- auth p95 > 1500ms soutenu
- API 5xx > 1%
- DB connections > 75%
- CPU ou RAM > 80% soutenu

## 8) Checklist operationnelle hebdo
1. `sli_quick_check`
2. `auth_smoke_check`
3. echantillon smoke manuel P0
4. revue couts + capacity tracker
5. decision: keep / optimize / scale

## 9) Commandes de reference
```powershell
.\scripts\run_k6_mix_matrix.ps1 -EnvFile .\load\env.local -ListingsVus "220,230,240" -AuthVus 5 -Duration 30m -RunSliCheck
.\scripts\run_k6_mix_matrix.ps1 -EnvFile .\load\env.local -ListingsVus "220" -AuthVus 5 -Duration 120m -RunSliCheck
.\scripts\sli_quick_check.ps1 -WindowMinutes 10 -SampleCount 30 -SshKeyPath "$env:USERPROFILE\.ssh\dzmarket_hetzner"
```
