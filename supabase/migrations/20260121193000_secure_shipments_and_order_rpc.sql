-- Secure shipments + orders updates and add atomic order RPC

-- Limit seller delivery settings to owner only
create or replace function public.get_seller_delivery_settings(p_owner uuid, p_courier_id text)
returns table (courier_id text, owner_id uuid, api_key text, api_secret text, sender_id text, extra jsonb)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is distinct from p_owner then
    return;
  end if;
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
revoke all on function public.get_seller_delivery_settings(uuid, text) from public;
grant execute on function public.get_seller_delivery_settings(uuid, text) to authenticated;

-- Orders: add label_url for compatibility
alter table public.orders add column if not exists label_url text;
alter table public.orders add column if not exists tracking_number text;
alter table public.orders add column if not exists courier_id text;
alter table public.orders add column if not exists courier_name text;
alter table public.orders add column if not exists delivery_method text;
alter table public.orders add column if not exists shipping_cost numeric(12,2);
alter table public.orders add column if not exists delivery_cost numeric(12,2);

-- Atomic order creation with stock reservation (RPC used by client app)
create or replace function public.create_order(
  p_product_id bigint,
  p_shipping_address_id bigint,
  p_payment_method text,
  p_shipping_option text,
  p_delivery_method text,
  p_agreed_price numeric,
  p_courier_id text,
  p_courier_name text,
  p_shipping_cost numeric,
  p_fee_amount numeric
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer uuid := auth.uid();
  v_seller uuid;
  v_price numeric;
  v_cost numeric;
  v_stock int;
  v_order_id bigint;
begin
  if v_buyer is null then
    raise exception 'auth required';
  end if;

  select owner_id, price, cost_price, stock_quantity
  into v_seller, v_price, v_cost, v_stock
  from public.products
  where id = p_product_id
  for update;

  if v_seller is null then
    raise exception 'product not found';
  end if;
  if v_seller = v_buyer then
    raise exception 'cannot buy own product';
  end if;
  if v_stock is null or v_stock <= 0 then
    raise exception 'out of stock';
  end if;

  insert into public.orders (
    product_id,
    buyer_id,
    seller_id,
    shipping_address_id,
    shipping_option,
    shipping_cost,
    payment_method,
    payment_status,
    delivery_method,
    agreed_price,
    courier_id,
    courier_name,
    sale_price,
    cost_price,
    fee_amount,
    delivery_cost,
    status
  ) values (
    p_product_id,
    v_buyer,
    v_seller,
    p_shipping_address_id,
    p_shipping_option,
    p_shipping_cost,
    coalesce(p_payment_method, 'cod'),
    case when coalesce(p_payment_method, 'cod') = 'cod' then 'pending' else 'paid' end,
    p_delivery_method,
    p_agreed_price,
    p_courier_id,
    p_courier_name,
    coalesce(p_agreed_price, v_price),
    v_cost,
    coalesce(p_fee_amount, 0),
    coalesce(p_shipping_cost, 0),
    'pending'
  ) returning id into v_order_id;

  update public.products
  set stock_quantity = stock_quantity - 1
  where id = p_product_id;

  return v_order_id;
end;
$$;
revoke all on function public.create_order(
  bigint, bigint, text, text, text, numeric, text, text, numeric, numeric
) from public;
grant execute on function public.create_order(
  bigint, bigint, text, text, text, numeric, text, text, numeric, numeric
) to authenticated;

-- Orders: limit updates to seller/service for tracking/labels
drop policy if exists "orders update buyer driver seller" on public.orders;
drop policy if exists "orders update seller service" on public.orders;
drop policy if exists "orders update buyer driver limited" on public.orders;
create policy "orders update seller service" on public.orders
  for update using (
    auth.uid() = seller_id
    or auth.role() = 'service_role'
  )
  with check (
    auth.uid() = seller_id
    or auth.role() = 'service_role'
  );
create policy "orders update buyer driver limited" on public.orders
  for update using (
    auth.uid() = buyer_id
    or auth.uid() = driver_id
  )
  with check (
    tracking_number is not distinct from (
      select o.tracking_number from public.orders o where o.id = orders.id
    )
    and label_url is not distinct from (
      select o.label_url from public.orders o where o.id = orders.id
    )
    and courier_id is not distinct from (
      select o.courier_id from public.orders o where o.id = orders.id
    )
    and courier_name is not distinct from (
      select o.courier_name from public.orders o where o.id = orders.id
    )
    and delivery_method is not distinct from (
      select o.delivery_method from public.orders o where o.id = orders.id
    )
    and shipping_cost is not distinct from (
      select o.shipping_cost from public.orders o where o.id = orders.id
    )
    and delivery_cost is not distinct from (
      select o.delivery_cost from public.orders o where o.id = orders.id
    )
  );

-- Shipments: limit insert/update to seller/service
drop policy if exists "shipments insert" on public.shipments;
drop policy if exists "shipments update" on public.shipments;
drop policy if exists "shipments insert seller service" on public.shipments;
drop policy if exists "shipments update seller service" on public.shipments;
create policy "shipments insert seller service" on public.shipments
  for insert with check (
    auth.uid() = (select seller_id from public.orders where id = order_id)
    or auth.role() = 'service_role'
  );
create policy "shipments update seller service" on public.shipments
  for update using (
    auth.uid() = (select seller_id from public.orders where id = order_id)
    or auth.role() = 'service_role'
  );
