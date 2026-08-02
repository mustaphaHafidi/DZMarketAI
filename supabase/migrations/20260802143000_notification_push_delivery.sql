-- Track server-side mobile push delivery for notification_events.
alter table public.notification_events
  add column if not exists push_sent_at timestamptz,
  add column if not exists push_attempts integer not null default 0,
  add column if not exists push_error text;

create index if not exists notification_events_push_pending_idx
  on public.notification_events (push_sent_at, push_attempts, created_at)
  where push_sent_at is null;
