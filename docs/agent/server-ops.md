# Server Ops Notes

Read this for production checks, Supabase self-hosting, Hetzner, web deploy, and logs.

## Scope

- Production web/API is served from the DZMarket Hetzner app server.
- The stack uses Caddy and self-hosted Supabase containers.
- Do not assume nginx.
- Do not print secrets from `.env`, service role keys, Firebase service accounts, or JWT secrets.

## Safe Flow

1. Identify target: app/API/logs, DB, or storage.
2. Verify SSH with the configured key.
3. Run read-only health/log queries first.
4. Take backup or capture current state before changing production config.
5. Restart only the minimum required service.

## Common Read-Only Checks

- Use the configured DZMarket Hetzner SSH key and host from the local operator notes.
- Check container health before changes.
- Check `https://app.dzmarket.pro` and `https://api.dzmarket.pro` headers before and after deploy.

## Push Diagnostics

Check whether the problem is token registration or FCM/APNs delivery:

- `device_tokens` has no `ios`: app/device did not register an iOS FCM token.
- `notification_events.push_error = no_device_tokens`: no push send attempted.
- `THIRD_PARTY_AUTH_ERROR` or `APNS_AUTH_ERROR`: Firebase/APNs setup problem.
- `UNREGISTERED`: stale token; backend should remove it.

## Deploy Safety

- Prefer exact source state, then deploy artifact from that state.
- Do not mix unrelated local worktree changes into a deploy.
- Never copy local secrets into tracked docs.
- On every web deploy, replace the old web files only after the new artifact is ready.
- Keep the active `/var/www/dzmarket-web` and one recent rollback directory.
- After deploy verification, remove only old inactive web backups, `/tmp/dzmarket-web*` archives, Docker build cache, unused Docker images, and old system journals/logs.
- Never remove Supabase volumes, `/opt/supabase/docker/volumes`, DB files, buckets, uploads, `.env` files, keys, or active containers as part of routine cleanup.
