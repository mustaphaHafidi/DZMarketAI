# Env Mapping (Execution Draft)

Updated: 2026-02-14

> Security rule: keep real secret values out of git. Use password manager or server-local `.env` only.

## A) Supabase self-host core (dzm-app-01)

| Variable | Current source | Target value | Server | Owner | Validated |
|---|---|---|---|---|---|
| JWT_SECRET | `/opt/supabase/docker/.env` | Set (generated) | B | TBD | Y |
| ANON_KEY | derived from `JWT_SECRET` | Set (generated) | B | TBD | Y |
| SERVICE_ROLE_KEY | derived from `JWT_SECRET` | Set (generated) | B | TBD | Y |
| POSTGRES_HOST | `/opt/supabase/docker/.env` | `db` (current runtime) | B | TBD | Y |
| POSTGRES_PORT | `/opt/supabase/docker/.env` | `5432` | B | TBD | Y |
| POSTGRES_DB | `/opt/supabase/docker/.env` | `postgres` (current runtime) | B | TBD | Y |
| POSTGRES_PASSWORD | `/opt/supabase/docker/.env` | Set | B | TBD | Y |
| SITE_URL | `/opt/supabase/docker/.env` | TBD final public URL | B | TBD | N |
| API_EXTERNAL_URL | `/opt/supabase/docker/.env` | TBD final public URL | B | TBD | N |
| SUPABASE_PUBLIC_URL | `/opt/supabase/docker/.env` | TBD final public URL | B | TBD | N |

## B) External DB path (optional target state)

| Variable | Current source | Target value | Server | Owner | Validated |
|---|---|---|---|---|---|
| POSTGRES_HOST | DB server private IP | `10.30.0.2` | A/B | TBD | Y |
| POSTGRES_DB | DB bootstrap | `dzmarket` | A/B | TBD | Y |
| POSTGRES_USER | DB bootstrap | `dzmarket_app` | A/B | TBD | Y |
| POSTGRES_PASSWORD | DB bootstrap | Set (server-local only) | A/B | TBD | Y |

## C) Storage path

| Variable | Current source | Target value | Server | Owner | Validated |
|---|---|---|---|---|---|
| MINIO_ENDPOINT | architecture decision | `10.30.0.4:9000` (external target) | B/C | TBD | Y |
| MINIO_ACCESS_KEY | storage server env | `minioadmin` (temporary, rotate) | C | TBD | Y |
| MINIO_SECRET_KEY | storage server env | Set (temporary, rotate) | C | TBD | Y |

## D) App + Functions + CI

| Variable | Current source | Target value | Server | Owner | Validated |
|---|---|---|---|---|---|
| SUPABASE_URL | app env + CI secrets | `https://api.<your-domain>` | App/CI | TBD | N |
| SUPABASE_ANON_KEY | app env | from Hetzner self-host `.env` | App/CI | TBD | N |
| SUPABASE_SERVICE_ROLE_KEY | CI + edge runtime | from Hetzner self-host `.env` | Functions/CI | TBD | N |
| MODERATION_FAIL_OPEN | function secrets | `false` (strict) | Functions | TBD | Y |
| SIGHTENGINE_USER | function secrets | set in secret manager | Functions | TBD | N |
| SIGHTENGINE_SECRET | function secrets | set in secret manager | Functions | TBD | N |
| YALIDINE_API_* | function secrets | set in secret manager | Functions | TBD | N |
| ECOTRACK_API_* | function secrets | set in secret manager | Functions | TBD | N |
| ZR_API_* | function secrets | set in secret manager | Functions | TBD | N |
| GUEPEX_API_* | function secrets | set in secret manager | Functions | TBD | N |

## Notes
- Old hosted Supabase legacy key was used for migration only; rotate old JWT secret after cutover.
- Do not put any real key in:
  - `README.md`
  - tracked `.md` files
  - CI logs
