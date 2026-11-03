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
- Keep the active `/var/www/dzmarket-web` and exactly **one** rollback directory
  (the one from the deploy just performed). This instruction already existed
  in prose but was not being followed in practice — as of 2026-10-13 the
  server had 3 rollback dirs and 1 orphaned staged release left over from
  past deploys (~160MB+53MB dead weight). Treat the checklist below as the
  literal steps, run every time, not an aspiration:
  1. Before swapping in the new release, list existing
     `/var/www/dzmarket-web-rollback-*` dirs. Delete all but the one that is
     about to become the newest (i.e. delete every rollback dir that already
     existed before this deploy started).
  2. After the swap, confirm `/var/www/dzmarket-web-releases/` is empty (the
     rename into `/var/www/dzmarket-web` should consume it, not copy it) —
     if a stale timestamped dir is still sitting there from a previous
     deploy, remove it.
  3. Delete the uploaded archive from `/tmp/` (`/tmp/dzmarket-web*.tar.gz`,
     `/tmp/dzmarket-web*.zip`) right after extraction succeeds, not "later."
  4. Only after the new deploy is verified healthy (5 URL checks pass,
     `config.json` intact) should step 1's deletions actually run — never
     delete the *only* rollback before the new build is confirmed good.
- Locally (this repo, not the server): delete `dzmarket-web-deploy-*.tar.gz`
  / `.zip` packaging artifacts from the repo root and one-off
  `build/deploy-web-*.sh` / `finish-deploy-web-*.sh` scripts once a deploy
  is done and verified — they are gitignored, fully regenerable, and
  otherwise accumulate (23MB+ each) on a machine with limited free disk.
- Preserve the production `/var/www/dzmarket-web/config.json` runtime config when
  the local build does not contain it; never replace it with an example file.
- Serve `www.dzmarket.pro` and `app.dzmarket.pro` from the same artifact while
  keeping their host-specific behavior in the Flutter router; do not redirect
  the marketing root to the app root.
- Never remove Supabase volumes, `/opt/supabase/docker/volumes`, DB files, buckets, uploads, `.env` files, keys, or active containers as part of routine cleanup.
  Docker images on `dzm-app-01` were checked 2026-10-13: all 13 images were
  100% active (0% reclaimable) — there was no dangling-image bloat to clear.
  Re-check with `docker system df` before ever running `docker image prune`;
  only prune if it reports non-zero `RECLAIMABLE`.
