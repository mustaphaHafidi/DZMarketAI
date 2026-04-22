alter table public.seller_delivery_settings
  add column if not exists last_validated_at timestamptz,
  add column if not exists last_validation_status text not null default 'unknown',
  add column if not exists last_validation_error text,
  add column if not exists consecutive_failures integer not null default 0;

alter table public.seller_delivery_settings
  drop constraint if exists seller_delivery_settings_last_validation_status_check;

alter table public.seller_delivery_settings
  add constraint seller_delivery_settings_last_validation_status_check
  check (last_validation_status in ('unknown', 'valid', 'invalid'));

update public.seller_delivery_settings
set last_validation_status = coalesce(nullif(trim(last_validation_status), ''), 'unknown'),
    consecutive_failures = coalesce(consecutive_failures, 0)
where last_validation_status is null
   or trim(last_validation_status) = ''
   or consecutive_failures is null;

create index if not exists seller_delivery_settings_validation_status_idx
  on public.seller_delivery_settings (owner_id, last_validation_status);

create or replace function public.get_enabled_couriers_for_seller(seller_id uuid)
returns table (courier_id text, courier_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select s.courier_id, coalesce(c.name, s.courier_id) as courier_name
  from public.seller_delivery_settings s
  left join public.couriers c on c.code = s.courier_id
  where s.owner_id = seller_id
    and s.api_key is not null
    and (
      s.courier_id = 'ecotrack'
      or s.api_secret is not null
    )
    and coalesce(nullif(trim(s.last_validation_status), ''), 'unknown') <> 'invalid';
end;
$$;

revoke all on function public.get_enabled_couriers_for_seller(uuid) from public;
grant execute on function public.get_enabled_couriers_for_seller(uuid) to authenticated, anon;
