# DZMarketAI

DZMarketAI est une marketplace Flutter (FR/AR) pour l'Algerie, appuyee sur Supabase self-hosted.

## Etat actuel
Pour reprendre le projet sans charger trop de contexte, commencer par
`docs/agent/README.md`, puis lire uniquement la fiche correspondant a la tache.

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
- `docs/agent/README.md`: point d'entree agent.
- `docs/agent/project-map.md`: architecture rapide.
- `docs/agent/mobile-release.md`: Android/iOS, Codemagic, Firebase, APNs.
- `docs/agent/server-ops.md`: Hetzner, Supabase, logs prod.
- `docs/agent/db-and-migrations.md`: SQL, RPC, migrations, RLS.
- `docs/agent/qa-regression.md`: tests et gates release.
- `docs/agent/known-issues.md`: cautions recentes.
- `docs/agent/doc-inventory.md`: anciens docs et classement.

## Securite
- Ne jamais committer de secrets.
- `SERVICE_ROLE_KEY` uniquement cote serveur.
- Rotation immediate de toute cle exposee.
- Labels et tokens transporteur traites cote backend uniquement.
