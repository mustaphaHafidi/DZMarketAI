-- Backfill legacy orders/shipments where delivery_cost was stored but
-- shipping_cost and courier metadata were left empty or stale.
-- Also normalize old signed label URLs to https on the public API domain.

update public.orders
set shipping_cost = delivery_cost
where coalesce(shipping_cost, 0) = 0
  and coalesce(delivery_cost, 0) > 0;

update public.orders
set label_url = regexp_replace(
      label_url,
      '^http://api\.dzmarket\.pro',
      'https://api.dzmarket.pro',
      'i'
    )
where coalesce(label_url, '') ~* '^http://api\.dzmarket\.pro';

do $$
declare
  has_shipping_cost boolean;
  has_courier_id boolean;
  has_carrier boolean;
  has_delivery_mode boolean;
  has_option boolean;
  set_clauses text[] := array[]::text[];
  update_sql text;
begin
  select exists (
           select 1
           from information_schema.columns
           where table_schema = 'public'
             and table_name = 'shipments'
             and column_name = 'shipping_cost'
         ),
         exists (
           select 1
           from information_schema.columns
           where table_schema = 'public'
             and table_name = 'shipments'
             and column_name = 'courier_id'
         ),
         exists (
           select 1
           from information_schema.columns
           where table_schema = 'public'
             and table_name = 'shipments'
             and column_name = 'carrier'
         ),
         exists (
           select 1
           from information_schema.columns
           where table_schema = 'public'
             and table_name = 'shipments'
             and column_name = 'delivery_mode'
         ),
         exists (
           select 1
           from information_schema.columns
           where table_schema = 'public'
             and table_name = 'shipments'
             and column_name = 'option'
         )
    into has_shipping_cost,
         has_courier_id,
         has_carrier,
         has_delivery_mode,
         has_option;

  if has_shipping_cost then
    set_clauses := array_append(
      set_clauses,
      'shipping_cost = case
         when coalesce(s.shipping_cost, 0) > 0 then s.shipping_cost
         when coalesce(o.shipping_cost, 0) > 0 then o.shipping_cost
         when coalesce(o.delivery_cost, 0) > 0 then o.delivery_cost
         else s.shipping_cost
       end'
    );
  end if;

  if has_courier_id then
    set_clauses := array_append(
      set_clauses,
      'courier_id = coalesce(s.courier_id, o.courier_id)'
    );
  end if;

  if has_carrier then
    set_clauses := array_append(
      set_clauses,
      'carrier = case
         when coalesce(s.carrier, '''') <> '''' then s.carrier
         when coalesce(o.courier_name, '''') <> '''' then o.courier_name
         else o.courier_id
       end'
    );
  end if;

  if has_delivery_mode then
    set_clauses := array_append(
      set_clauses,
      'delivery_mode = coalesce(nullif(s.delivery_mode, ''''), o.delivery_method)'
    );
  end if;

  if has_option then
    set_clauses := array_append(
      set_clauses,
      'option = coalesce(nullif(s.option, ''''), o.shipping_option)'
    );
  end if;

  if array_length(set_clauses, 1) is not null then
    update_sql := format(
      'update public.shipments s set %s
         from public.orders o
        where s.order_id = o.id',
      array_to_string(set_clauses, ', ')
    );
    execute update_sql;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'shipments'
      and column_name = 'label_url'
  ) then
    execute $sql$
      update public.shipments
      set label_url = regexp_replace(
            label_url,
            '^http://api\.dzmarket\.pro',
            'https://api.dzmarket.pro',
            'i'
          )
      where coalesce(label_url, '') ~* '^http://api\.dzmarket\.pro'
    $sql$;
  end if;
end
$$;

update public.messages
set payload = jsonb_set(
      payload,
      '{label_url}',
      to_jsonb(
        regexp_replace(
          payload->>'label_url',
          '^http://api\.dzmarket\.pro',
          'https://api.dzmarket.pro',
          'i'
        )
      ),
      true
    )
where payload ? 'label_url'
  and coalesce(payload->>'label_url', '') ~* '^http://api\.dzmarket\.pro';
