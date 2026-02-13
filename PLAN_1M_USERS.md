# Plan 1M users/an - DZMarket (Supabase self-host + PostgreSQL)

## 1) Objectif et hypotheses (validees)
- Budget Phase 1: 200-300 EUR/mois.
- MAU cible Phase 1: 100k-500k.
- Media: 3 photos max/annonce, 4 MB max/photo.
- Zone: public DZ uniquement, hebergement EU proche (latence OK).

## 2) Architecture cible (simple + pro)
- Supabase self-host (Auth/REST/Realtime/Storage/Edge).
- PostgreSQL (primary + 1 replica en phase 2).
- MinIO (stockage objets) + CDN.
- Redis (cache + rate limit + sessions, phase 2).
- Observabilite: Grafana + Loki + Prometheus.
- Cloudflare (DNS, SSL, cache, WAF).

## 3) Phases d'evolution
### Phase 1 (100k -> 500k MAU, budget 200-300 EUR)
- 3 serveurs (cible stable):
  - DB: 16 vCPU / 32 GB RAM / NVMe (priorite performances write).
  - App/Edge/Realtime: 8 vCPU / 16 GB.
  - Storage (MinIO): 4-8 vCPU / 16 GB + disque large.
- Backups automatiques DB (quotidien + hebdo).
- Alerting (erreurs API, latence, disque).
- Cache CDN pour images.

### Phase 2 (500k -> 800k MAU)
- Ajouter replica PostgreSQL (lecture).
- Isoler Realtime sur serveur dedie.
- Redis obligatoire.
- Workers/cron dedies (jobs, tracking).

### Phase 3 (800k -> 1M/an)
- HA DB (primary + replica + failover).
- Load balancer API/Edge.
- Storage en cluster (ou S3 compatible).
- Monitoring pro + rotations de logs.

## 4) Points critiques app (performance)
- Chat: 30 derniers messages + pagination stricte.
- Index DB: orders, messages, products, reads, shipments.
- Images: compression + thumbnails, limiter taille.
- Stats vendeur: pre-calcul (table "seller_stats").

## 5) Securite et conformite
- Secrets en .env / GitHub Secrets.
- Tokens transporteurs chiffrés.
- RLS stricte, audit logs.
- Backups off-site (hebdo).

## 6) Domaines .dz
- app.dz -> Web
- api.app.dz -> Supabase API
- SSL via Cloudflare

## 7) Budget (ordre de grandeur)
- Phase 1: 200-300 EUR/mois (objectif).
- Phase 2: 400-800 EUR/mois.
- Phase 3: 800-1500 EUR/mois.

## 8) Estimation stockage (photos)
- 3 photos/annonce, 4 MB max => 12 MB/annonce brut.
- Avec compression + thumbnails: viser 4-6 MB/annonce reel.
- Ex: 200k annonces => ~0.8-1.2 TB.
- Prevoir disque storage 2-3 TB minimum (evolution).

## 9) Prochaines actions recommandees
- Choisir provider (OVH/Hetzner).
- Preparer stack Docker Compose prod.
- Lancer monitoring + backups.
- Definir seuils upgrade (MAU, latence, storage).

## 10) Checklist avant lancement public
- Tests de charge (auth, upload, chat, orders).
- Rollback plan (DB + storage).
- SLA simple + pages status.
- Support client (retours colis, litiges).

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

