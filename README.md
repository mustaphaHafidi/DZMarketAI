# DZMarketAI

DZMarketAI est une marketplace Flutter (FR/AR) pour l'Algerie, appuyee sur Supabase self-hosted.

## Etat actuel (Mars 2026)
- Lancement public web effectue (`https://app.dzmarket.pro`).
- Validation charge mixte confirmee:
  - stable: `220 listings + 5 auth` (60m et 120m)
  - limite observee: `240 listings + 5 auth` (degradation p95)
  - budget d'exploitation recommande: `195 listings + 4 auth`
- Correctifs recents:
  - URL labels publiques nettoyees (`https://api.dzmarket.pro/...`)
  - route web sans `#` (PathUrlStrategy)
  - `job-runner` compatible schema `shipments` legacy + debug reminders transporteur

## Fonctionnel
- Auth email/password + reset mot de passe.
- Parcourir, filtres, favoris, fiches produit.
- Offres et achat.
- Mes commandes / Mes ventes.
- Livraison multi-transporteurs: Yalidine, Ecotrack, ZR Express, Guepex.
- Bordereau + ouverture label PDF.
- Chat, notifications, retours, moderation superadmin.

## Stack
- Front: Flutter (Android/Web, iOS pipeline en cours).
- Backend: Supabase self-host (Postgres, Auth, Storage, Realtime, Edge Functions).
- Infra: Hetzner + Caddy + Kong.
- Monitoring/ops: scripts PowerShell + k6.

## Arborescence
- `lib/`: application Flutter.
- `assets/i18n/`: traductions FR/AR.
- `supabase/functions/`: Edge Functions metier.
- `supabase/migrations/`: migrations SQL.
- `load/`: scenarios k6.
- `scripts/`: automation QA/ops/load.
- `docs/`: runbooks et plan de capacite.

## Commandes utiles

### Run Android USB (prod flavor)
```powershell
flutter run -d <DEVICE_ID> --flavor prod -t lib/main.dart --dart-define-from-file=test/test_env.json
```

### Build web + package
```powershell
flutter build web --release --dart-define-from-file=test/test_env.json
powershell -NoProfile -Command "Compress-Archive -Path '.\\build\\web\\*' -DestinationPath '.\\dzmarket-web.zip' -Force"
```

### Qualite locale
```powershell
.\scripts\run_quality_gate.ps1
```

### SLI prod rapide
```powershell
.\scripts\sli_quick_check.ps1 -WindowMinutes 10 -SampleCount 30
```

### Charge mixte (listings + auth)
```powershell
.\scripts\run_k6_mix_matrix.ps1 -EnvFile .\load\env.local -ListingsVus "220" -AuthVus 5 -Duration 60m -RunSliCheck
```

## Documentation principale
- `docs/GO_NO_GO_PUBLIC_LAUNCH.md`
- `docs/PUBLIC_LAUNCH_RUNBOOK_J0_J1.md`
- `docs/QA_SMOKE_AND_LOCAL_CHECKLIST.md`
- `docs/SLO_SLI_DZMARKET.md`
- `docs/LOAD_TEST_PLAN_1M.md`
- `E2E_MANUAL_TEST_CASES.md`
- `PLAN_1M_USERS.md`
- `NEXT_STEPS.md`

## Securite
- Ne jamais committer de secrets.
- `SERVICE_ROLE_KEY` uniquement cote serveur.
- Rotation immediate de toute cle exposee.
- Labels et tokens transporteur traites cote backend uniquement.
