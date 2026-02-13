# Supabase self-host (PostgreSQL) - Plan d'implementation DZMarket

## 1) Objectif (Phase 1)
- 100k-500k MAU, budget 200-300 EUR/mois.
- 3 serveurs: DB / App+Edge / Storage.
- Cloudflare pour DNS + SSL + cache images.

## 2) Architecture cible
### Serveur A - PostgreSQL (DB)
- 16 vCPU / 32 GB RAM / NVMe.
- Postgres 15+.
- Sauvegardes quotidiennes + hebdo off-site.
- Monitoring (CPU, RAM, disque, connexions).

### Serveur B - Supabase App/Edge/Realtime
- 8 vCPU / 16 GB RAM.
- Docker + Docker Compose.
- Services: Kong, Auth, PostgREST, Realtime, Storage API, Edge Functions, Studio.

### Serveur C - Storage (MinIO)
- 4-8 vCPU / 16 GB RAM + 2-3 TB.
- Bucket public (products, avatars, messages) + policies.
- Cache CDN via Cloudflare.

## 3) DNS / SSL
- app.dz -> Web (Cloudflare)
- api.app.dz -> Supabase API (Kong)
- storage.app.dz -> MinIO (optionnel)
- SSL via Cloudflare (Full Strict).

## 4) Etapes de mise en place
### Etape 1 - Postgres
- Installer Postgres 15+.
- Creer roles et DB.
- Activer sauvegardes (pg_dump).
- Ajuster max_connections, shared_buffers, work_mem selon RAM.

### Etape 2 - Supabase (App/Edge)
- Installer Docker + Compose.
- Utiliser une config self-host officielle (voir README infra/supabase).
- Pointer vers la DB externe (Serveur A).

### Etape 3 - MinIO
- Deployer MinIO sur Serveur C.
- Configurer access/secret.
- Brancher Storage API Supabase vers MinIO.

## 5) Monitoring / alertes
- Grafana + Loki + Prometheus.
- Alertes: latence API, erreurs 5xx, CPU > 70%, disque > 70%.
- Workflow GitHub `job-runner-cron.yml` pour verifier quotidiennement:
  - echec API courier,
  - anomalies returns=0 avec streak,
  - erreurs job-runner.

## 6) Checklist avant lancement
- Tests de charge auth + upload + chat.
- Verifier backups et restauration.
- Verifier RLS et policies Storage.
- Activer WAF Cloudflare.

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

