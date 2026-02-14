# Migration Inventory (Execution State)

Updated: 2026-02-14

## 1) Source platform (old hosted Supabase)
- Supabase URL: `https://maumwzbvzbcamvlivqpe.supabase.co`
- Project ref: `maumwzbvzbcamvlivqpe`
- Primary DB connection used for migration export:
  - host: `aws-1-eu-north-1.pooler.supabase.com`
  - user: `postgres.maumwzbvzbcamvlivqpe`
  - sslmode: `require`
- DNS cutover values: pending final decision

## 2) Target platform (Hetzner)
- Private network: `dzmarket-net` (`10.30.0.0/16`, `eu-central`)
- Servers:
  - `dzm-db-01`: public `46.225.88.249`, private `10.30.0.2`, role `postgres`
  - `dzm-app-01`: public `91.107.239.5`, private `10.30.0.3`, role `supabase stack`
  - `dzm-storage-01`: public `91.98.227.237`, private `10.30.0.4`, role `minio`

## 3) Active Edge functions (target set)
- `validate-courier`
- `courier-locations`
- `create_shipment`
- `job-runner`
- `moderate-content`
- `estimate-shipping`
- `admin-moderation`
- `seller-delivery-settings`

Critical cutover set:
- `validate-courier`
- `courier-locations`
- `create_shipment`
- `job-runner`
- `moderate-content`
- `estimate-shipping`

## 4) Data migration evidence

### DB row counts (source and target matched)
- `auth.users`: 31
- `public.profiles`: 28
- `public.products`: 30
- `public.orders`: 88
- `public.messages`: 54

### Storage objects
- Migration result: `DONE 70 / 70`
- Bucket details:
  - `avatars`: 5
  - `labels`: 29
  - `messages`: 2
  - `products`: 34

## 5) Background jobs and cron
- GitHub workflow: `.github/workflows/job-runner-cron.yml`
- Frequency: daily (`03:00 UTC`)
- Operational requirement:
  - update secrets to new target (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`)

## 6) Migration ownership (to finalize)
- Migration lead: `TBD`
- DB lead: `TBD`
- DNS lead: `TBD`
- Rollback owner: `TBD`

## 7) Cutover window (to finalize)
- Planned date: `TBD`
- Start time: `TBD`
- End time: `TBD`
- User comms ready: `TBD`

## 8) Technical fixes already done
- Supabase self-host health fixes:
  - storage healthcheck updated to `127.0.0.1`
  - override persisted in `docker-compose.override.yml`
- Key alignment fixes:
  - regenerated local `ANON_KEY` and `SERVICE_ROLE_KEY` from `JWT_SECRET`
  - corrected `VAULT_ENC_KEY` and `PG_META_CRYPTO_KEY` lengths (32 chars)
- DB migration chain cleaned:
  - UTF-8 BOM issues fixed in SQL migrations

## 9) Open risks
- Some secrets were handled in terminal/chat during migration.
- Action required:
  - rotate old hosted Supabase JWT secret
  - rotate temporary migration passwords
  - verify no real secret is committed to git
