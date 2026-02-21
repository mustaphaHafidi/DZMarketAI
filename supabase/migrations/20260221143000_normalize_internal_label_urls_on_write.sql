-- Normalize internal label URLs on every write (orders/shipments/messages).
-- Prevents browser clients from receiving non-public hosts such as kong/localhost.

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

create or replace function public.normalize_internal_label_url_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.label_url is not null then
    new.label_url := public.rewrite_internal_label_url(new.label_url);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_orders_normalize_label_url on public.orders;
create trigger trg_orders_normalize_label_url
before insert or update of label_url on public.orders
for each row
execute function public.normalize_internal_label_url_row();

drop trigger if exists trg_shipments_normalize_label_url on public.shipments;
create trigger trg_shipments_normalize_label_url
before insert or update of label_url on public.shipments
for each row
execute function public.normalize_internal_label_url_row();

create or replace function public.normalize_internal_label_url_message_payload()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.payload is not null and jsonb_typeof(new.payload) = 'object' and new.payload ? 'label_url' then
    new.payload := jsonb_set(
      new.payload,
      '{label_url}',
      to_jsonb(public.rewrite_internal_label_url(new.payload->>'label_url')),
      true
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_messages_normalize_label_url on public.messages;
create trigger trg_messages_normalize_label_url
before insert or update of payload on public.messages
for each row
execute function public.normalize_internal_label_url_message_payload();

