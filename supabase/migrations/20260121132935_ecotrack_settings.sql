create or replace function public.get_enabled_couriers_for_seller(seller_id uuid)
returns table (courier_id text, courier_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select s.courier_id, c.name
  from public.seller_delivery_settings s
  join public.couriers c on c.code = s.courier_id
  where s.owner_id = seller_id
    and s.api_key is not null
    and (
      s.courier_id = 'ecotrack'
      or s.api_secret is not null
    );
end;
$$;

create or replace function public.get_seller_delivery_settings(p_owner uuid, p_courier_id text)
returns table (courier_id text, owner_id uuid, api_key text, api_secret text, sender_id text, extra jsonb)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select courier_id, owner_id, api_key, api_secret, sender_id, extra
  from public.seller_delivery_settings
  where owner_id = p_owner
    and courier_id = p_courier_id
    and api_key is not null
    and (
      p_courier_id = 'ecotrack'
      or api_secret is not null
    );
end;
$$;
