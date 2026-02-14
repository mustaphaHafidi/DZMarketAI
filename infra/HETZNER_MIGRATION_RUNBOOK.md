# Hetzner Migration Runbook

Last update: 2026-02-14  
Owner: DZMarket team

## Scope
- Migrate DZMarket backend from hosted Supabase to Hetzner.
- 3-server target:
  - Server A: `dzm-db-01` (PostgreSQL)
  - Server B: `dzm-app-01` (Supabase self-host stack)
  - Server C: `dzm-storage-01` (MinIO)
- Zero data loss objective.
- Rollback possible by switching app config and DNS back to old platform.

## References
- `infra/SELF_HOST_SUPABASE_PLAN.md`
- `infra/supabase/README.md`
- `infra/hetzner/MIGRATION_INVENTORY.md`
- `infra/hetzner/ENV_MAPPING_DRAFT.md`
- `infra/hetzner/SERVERS_CONFIG_AND_KEYS.md`

## Current status snapshot
- Hetzner network and servers are provisioned.
- Supabase self-host stack is running on `dzm-app-01` and healthy.
- Core DB data is migrated and validated by table counts.
- Storage files are migrated (`DONE 70 / 70`), with bucket-level validation.
- Remaining work is cutover hardening and secrets rotation.

## Migration phases and status
1. Preparation and readiness: done
2. Provision Hetzner infra: done
3. Deploy target stack: done
4. Data migration + validation: done
5. Production cutover: in progress
6. Hypercare (72h) and tuning: pending

---

## What is already validated

### Data validation
- `auth.users`: 31
- `public.profiles`: 28
- `public.products`: 30
- `public.orders`: 88
- `public.messages`: 54

### Storage validation
- `avatars`: 5
- `labels`: 29
- `messages`: 2
- `products`: 34
- Total objects: 70

### Platform health
- `kong`, `auth`, `rest`, `realtime`, `pooler`, `studio`, `db` healthy
- `storage` health check fixed via override file (`docker-compose.override.yml`)

---

## Cutover checklist (production)

### Pre-cutover
- [ ] Rotate any secret that was copied in chat/terminal history.
- [ ] Freeze write-heavy admin operations during switchover window.
- [ ] Confirm final env mapping ownership in `infra/hetzner/ENV_MAPPING_DRAFT.md`.
- [ ] Verify app runtime can access new Supabase URL and anon key.
- [ ] Keep old Supabase project alive for rollback.

### Cutover execution
- [ ] Update app env to new backend URL/key.
- [ ] Deploy mobile/web build pointing to Hetzner API.
- [ ] Run smoke tests:
  - [ ] login / signup
  - [ ] create listing + upload photos
  - [ ] chat + offers
  - [ ] order + shipping estimate
  - [ ] moderation flow

Helper automation (PowerShell, local):
- `scripts/hetzner_finalize_cutover.ps1`
- Example:
  - `.\scripts\hetzner_finalize_cutover.ps1 -AppServerIp 91.107.239.5 -Repo mustaphaHafidi/DZMarketAI`

### Post-cutover (first 72h)
- [ ] Monitor API errors, DB CPU/RAM, disk, object storage growth.
- [ ] Monitor cron and background jobs.
- [ ] Track payment/order failure rate.
- [ ] Keep rollback owner on-call.

---

## Rollback policy (short)
- Keep old Supabase project online for at least 48h after cutover.
- Rollback trigger examples:
  - auth failures > acceptable threshold
  - order creation failures
  - persistent storage upload failures
- Rollback actions:
  - restore old `SUPABASE_URL` + `ANON_KEY` in app config
  - redeploy app
  - revert DNS if public API domain changed

---

## Security notes
- Never commit real secrets to git (`.env`, JWT keys, DB passwords, MinIO secrets).
- Use placeholders in docs and store actual values in password manager.
- Rotate:
  - old hosted Supabase `JWT secret` (if legacy keys were exposed)
  - temporary migration passwords used during import
