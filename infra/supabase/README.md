# Supabase Self-Host (App/Edge Node)

This folder documents deployment on the App/Edge server when DB and object storage are external.

## Prerequisites
- Docker + Docker Compose plugin.
- External PostgreSQL server ready.
- External MinIO/S3-compatible storage ready.

## 1) Get official stack baseline

```bash
git clone https://github.com/supabase/supabase.git
cd supabase/docker
cp docker-compose.yml ../../infra/supabase/docker-compose.prod.yml
cp .env.example ../../infra/supabase/.env.example
```

## 2) Configure `.env`
Create `.env` from `.env.example` and fill:
- Postgres: `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
- Auth keys: `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`
- Public URLs: `SITE_URL`, `API_EXTERNAL_URL`, `SUPABASE_PUBLIC_URL`
- Storage: `MINIO_ENDPOINT`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`

## 3) Start services

```bash
docker compose -f docker-compose.prod.yml up -d
```

## 4) Recommended exposure
- `api.app.dz` -> Kong/API (HTTPS)
- `studio.app.dz` -> Studio (optional, protected)
- DB and MinIO admin ports must stay private/internal.

## 5) Post-start checklist
- Apply schema: `supabase.sql` + migrations.
- Deploy functions: `create_shipment`, `job-runner`, `courier-locations`, `validate-courier`.
- Verify cron workflow secrets (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`) in GitHub.

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

