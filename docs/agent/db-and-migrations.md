# DB And Migrations Notes

Read this for schema, SQL, RPC, RLS, and production DB work.

## Source Of Truth

- Main migration folder: `supabase/migrations/`.
- Legacy snapshot: `supabase.sql` can be useful for search, but migrations and live DB state win.
- Edge functions may depend on schema fallback behavior; inspect both SQL and function code before changing.

## Safe Migration Flow

1. Inspect current code path and live schema.
2. Prefer additive migrations: new columns, indexes, or functions with backwards compatibility.
3. Avoid destructive schema changes unless a backup and rollback are ready.
4. Apply migration first in local/staging when possible.
5. Run targeted tests.
6. Apply production migration with a timestamped SQL file.
7. Verify live tables/RPC behavior after deploy.

## Important Areas

- `register_device_token`: mobile FCM token registration.
- `notification_events`: in-app notifications and push delivery tracking.
- `post_order_event`: order/chat notification event creation.
- `orders`, `shipments`, `messages`, `conversations`: high-risk business tables.
- RLS policies: never bypass without a service role edge function reason.

## Production Guardrails

- Do not paste secrets in SQL files.
- Do not run broad deletes without an explicit bounded predicate.
- For chat/order fixes, preserve idempotency and dedupe keys.
- For stock changes, confirm whether the flow is real order, arranged delivery, or chat-only.

