-- Rewrite historical internal label URLs (kong/local) to public API domain.
-- This unblocks browser "open label" flows that previously opened black pages.

create or replace function public.rewrite_internal_label_url(
  raw_url text,
  public_base text default 'https://api.dzmarket.pro'
)
returns text
language sql
immutable
as $$
  select
    case
      when coalesce(trim(raw_url), '') = '' then raw_url
      when coalesce(trim(public_base), '') = '' then trim(raw_url)
      else regexp_replace(
        trim(raw_url),
        '^https?://(kong|supabase-kong|localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::1\\]|::1)(:\\d+)?',
        regexp_replace(trim(public_base), '/+$', ''),
        'i'
      )
    end
$$;

update public.orders
set label_url = public.rewrite_internal_label_url(label_url)
where coalesce(label_url, '') ~* '^https?://(kong|supabase-kong|localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::1\\]|::1)(:\\d+)?';

update public.shipments
set label_url = public.rewrite_internal_label_url(label_url)
where coalesce(label_url, '') ~* '^https?://(kong|supabase-kong|localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::1\\]|::1)(:\\d+)?';

update public.messages
set payload = jsonb_set(
  payload,
  '{label_url}',
  to_jsonb(public.rewrite_internal_label_url(payload->>'label_url')),
  true
)
where payload ? 'label_url'
  and coalesce(payload->>'label_url', '') ~* '^https?://(kong|supabase-kong|localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::1\\]|::1)(:\\d+)?';
