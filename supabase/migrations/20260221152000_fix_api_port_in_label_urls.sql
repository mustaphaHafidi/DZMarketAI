-- Ensure label URLs never expose internal Kong ports on the public API host.

create or replace function public.rewrite_internal_label_url(
  raw_url text,
  public_base text default 'https://api.dzmarket.pro'
)
returns text
language sql
immutable
as $$
  with vars as (
    select
      trim(raw_url) as raw,
      regexp_replace(trim(public_base), '/+$', '') as base
  )
  select
    case
      when coalesce(raw, '') = '' then raw_url
      when coalesce(base, '') = '' then raw
      else regexp_replace(
        regexp_replace(
          raw,
          '^https?://(kong|supabase-kong|localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::1\\]|::1)(:\\d+)?',
          base,
          'i'
        ),
        '^https?://api\\.dzmarket\\.pro:(8000|8443)(?=/)',
        base,
        'i'
      )
    end
  from vars
$$;

update public.orders
set label_url = public.rewrite_internal_label_url(label_url)
where coalesce(label_url, '') ~* '^https?://api\\.dzmarket\\.pro:(8000|8443)(/|$)';

update public.shipments
set label_url = public.rewrite_internal_label_url(label_url)
where coalesce(label_url, '') ~* '^https?://api\\.dzmarket\\.pro:(8000|8443)(/|$)';

update public.messages
set payload = jsonb_set(
  payload,
  '{label_url}',
  to_jsonb(public.rewrite_internal_label_url(payload->>'label_url')),
  true
)
where payload is not null
  and jsonb_typeof(payload) = 'object'
  and payload ? 'label_url'
  and coalesce(payload->>'label_url', '') ~* '^https?://api\\.dzmarket\\.pro:(8000|8443)(/|$)';
