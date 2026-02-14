# Hetzner Servers Config + Keys (End-to-End)

Updated: 2026-02-14

> This document stores operational config only.  
> Never commit real secret values in this file.

## 0) Topology

| Server | Public IP | Private IP | Role |
|---|---|---|---|
| `dzm-db-01` | `46.225.88.249` | `10.30.0.2` | PostgreSQL |
| `dzm-app-01` | `91.107.239.5` | `10.30.0.3` | Supabase self-host stack |
| `dzm-storage-01` | `91.98.227.237` | `10.30.0.4` | MinIO |

Network:
- name: `dzmarket-net`
- CIDR: `10.30.0.0/16`
- zone: `eu-central`

## 1) SSH access model

- Local key path (Windows): `%USERPROFILE%\.ssh\dzmarket_hetzner`
- Example connect commands:
  - `ssh -i "$env:USERPROFILE\.ssh\dzmarket_hetzner" root@46.225.88.249`
  - `ssh -i "$env:USERPROFILE\.ssh\dzmarket_hetzner" root@91.107.239.5`
  - `ssh -i "$env:USERPROFILE\.ssh\dzmarket_hetzner" root@91.98.227.237`

## 2) Server A (`dzm-db-01`) config

### OS and base
- Ubuntu 24.04
- timezone: `Africa/Algiers`

### Firewall (UFW)
- allow `22/tcp` from anywhere
- allow `5432/tcp` from `10.30.0.3`

### PostgreSQL
- version: 16.x
- role/database created:
  - role: `dzmarket_app`
  - database: `dzmarket`
- listen addresses configured:
  - `10.30.0.2`
  - `localhost`
- `pg_hba.conf` entries:
  - `host dzmarket dzmarket_app 10.30.0.3/32 scram-sha-256`
  - `host dzmarket dzmarket_app 10.30.0.4/32 scram-sha-256`

### Validation commands
- `ss -ltnp | grep 5432`
- `systemctl status postgresql --no-pager`

## 3) Server B (`dzm-app-01`) config

### OS and base
- Ubuntu 24.04
- Docker Engine + Docker Compose plugin installed
- timezone: `Africa/Algiers`

### Firewall (UFW)
- allow `22/tcp`
- allow `80/tcp`
- allow `443/tcp`

### Supabase stack location
- path: `/opt/supabase/docker`
- run command:
  - `docker compose -f docker-compose.yml -f docker-compose.s3.yml up -d`

### Health fix applied
- storage healthcheck override was added and persisted:
  - `docker-compose.override.yml`
  - healthcheck uses `http://127.0.0.1:5000/status`

### Runtime status check
- `docker compose -f docker-compose.yml -f docker-compose.s3.yml ps`
- expected healthy services:
  - `kong`, `auth`, `rest`, `realtime`, `storage`, `pooler`, `studio`, `db`, `imgproxy`, `meta`, `vector`

## 4) Server C (`dzm-storage-01`) config

### OS and base
- Ubuntu 24.04
- Docker installed and enabled

### Firewall (UFW)
- allow `22/tcp`
- allow `9000/tcp` from `10.30.0.3`
- allow `9001/tcp` from `10.30.0.3`

### MinIO
- data dir: `/data/minio`
- container: `minio`
- bind: `10.30.0.4:9000` and `10.30.0.4:9001`
- health check:
  - `curl -I http://10.30.0.4:9000/minio/health/live`

## 5) Keys and secrets map

## 5.1 Old hosted Supabase (migration source)
- Project URL: `https://maumwzbvzbcamvlivqpe.supabase.co`
- Needed during migration:
  - legacy `service_role` JWT (from dashboard `Settings > API Keys > Legacy`)
  - old DB password (for pooler export)
- Action after cutover:
  - rotate old JWT secret
  - rotate old DB password

## 5.2 New self-host Supabase (migration target)
- Secrets are in:
  - `/opt/supabase/docker/.env` on `dzm-app-01`
- Keys used by app/functions:
  - `ANON_KEY`
  - `SERVICE_ROLE_KEY`
  - `JWT_SECRET`
- Useful command:
  - `grep -nE "JWT_SECRET|ANON_KEY|SERVICE_ROLE_KEY|POSTGRES_PASSWORD" /opt/supabase/docker/.env`

## 5.3 DB and storage secrets
- DB password source:
  - `ALTER ROLE dzmarket_app WITH PASSWORD '<strong-password>';` on `dzm-db-01`
- MinIO root creds source:
  - env passed in `docker run` on `dzm-storage-01`

## 5.4 Secret handling rules
- Never commit:
  - `.env`
  - raw JWT keys
  - DB passwords
  - MinIO passwords
- Keep only placeholders in docs and git.
- Use password manager for real values.

## 6) Data migration state

### DB copy result
- Source to target counts validated:
  - `auth.users`: 31
  - `public.profiles`: 28
  - `public.products`: 30
  - `public.orders`: 88
  - `public.messages`: 54

### Storage copy result
- Script run result: `DONE 70 / 70`
- Buckets:
  - `avatars`: 5
  - `labels`: 29
  - `messages`: 2
  - `products`: 34

### Validation command (target)
- `docker exec supabase-db psql -U postgres -d postgres -c "select bucket_id,count(*) from storage.objects group by bucket_id order by bucket_id;"`

## 7) Final cutover checklist

- [ ] App env switched to Hetzner API URL and anon key
- [ ] CI secrets updated (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`)
- [ ] Edge function secrets updated on target
- [ ] Smoke tests passed (auth, listing, upload, chat, order)
- [ ] Rollback owner on-call
- [ ] Old platform secrets rotated

## 8) Recommended next hardening

- Disable direct public exposure for internal-only services.
- Restrict SSH by source IP if possible.
- Add fail2ban and basic intrusion alerts.
- Add backup jobs:
  - PostgreSQL logical backup + restore test
  - MinIO bucket replication/snapshot policy
- Add monitoring dashboard for:
  - API latency
  - DB load
  - storage growth
  - job-runner health
