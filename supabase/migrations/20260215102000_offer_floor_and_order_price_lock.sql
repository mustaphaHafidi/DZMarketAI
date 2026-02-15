-- Offer floor + order pricing lock.
-- 1) Buyer cannot submit an offer below 50% of product price.
-- 2) Order price is always resolved server-side:
--    - accepted offer amount for this buyer/product (if any),
--    - otherwise product base price.
-- Client-provided p_agreed_price is kept for RPC compatibility but ignored.

create or replace function public.make_offer(
  p_product_id bigint,
  p_amount numeric,
  p_message text default null
)
returns public.offers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer public.offers;
  v_product record;
  v_message text := nullif(left(coalesce(p_message, ''), 240), '');
  v_min_amount numeric := 1;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('offer_make:' || p_product_id::text || ':' || auth.uid()::text)
  );

  select p.id, p.owner_id, p.status, p.is_archived, p.stock_quantity, p.price
    into v_product
  from public.products p
  where p.id = p_product_id
  for update;

  if v_product.id is null then
    raise exception 'product_missing' using errcode = 'P0002';
  end if;

  if v_product.owner_id = auth.uid() then
    raise exception 'cannot_offer_own_product' using errcode = '42501';
  end if;

  if coalesce(v_product.is_archived, false)
     or coalesce(v_product.stock_quantity, 0) <= 0
     or coalesce(v_product.status, 'active') <> 'active' then
    raise exception 'product_unavailable' using errcode = 'P0001';
  end if;

  v_min_amount := greatest(1::numeric, ceil(coalesce(v_product.price, 0::numeric) * 0.5));
  if p_amount < v_min_amount then
    raise exception 'offer_below_min_ratio'
      using errcode = '22023',
            detail = 'min_offer=' || v_min_amount::text,
            hint = 'offer must be at least 50% of product price';
  end if;

  update public.offers
  set status = 'cancelled',
      responded_at = coalesce(responded_at, now()),
      updated_at = now()
  where product_id = p_product_id
    and buyer_id = auth.uid()
    and status = 'pending';

  insert into public.offers (
    product_id,
    buyer_id,
    seller_id,
    status,
    amount,
    message,
    counter_amount,
    agreed_amount,
    counter_by,
    created_at,
    responded_at,
    updated_at
  )
  values (
    p_product_id,
    auth.uid(),
    v_product.owner_id,
    'pending',
    p_amount,
    v_message,
    null,
    null,
    null,
    now(),
    null,
    now()
  )
  returning * into v_offer;

  perform public.emit_offer_system_message(
    v_offer.product_id,
    v_offer.buyer_id,
    v_offer.seller_id,
    v_offer.id,
    'created',
    v_offer.amount,
    'offer:' || v_offer.id::text || ':created'
  );

  return v_offer;
end;
$$;
revoke all on function public.make_offer(bigint, numeric, text) from public;
grant execute on function public.make_offer(bigint, numeric, text) to authenticated;

create or replace function public.respond_offer(
  p_offer_id bigint,
  p_action text,
  p_amount numeric default null,
  p_message text default null
)
returns public.offers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer public.offers;
  v_action text := lower(trim(coalesce(p_action, '')));
  v_actor uuid := auth.uid();
  v_last_actor uuid;
  v_message text := nullif(left(coalesce(p_message, ''), 240), '');
  v_now timestamptz := now();
  v_agreed numeric;
  v_product_price numeric;
  v_min_amount numeric := 1;
begin
  if v_actor is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  select *
    into v_offer
  from public.offers
  where id = p_offer_id
  for update;

  if v_offer.id is null then
    raise exception 'offer_missing' using errcode = 'P0002';
  end if;

  if v_offer.status <> 'pending' then
    raise exception 'offer_not_pending' using errcode = 'P0001';
  end if;

  if v_actor not in (v_offer.buyer_id, v_offer.seller_id) then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  v_last_actor := coalesce(v_offer.counter_by, v_offer.buyer_id);
  if v_actor = v_last_actor then
    raise exception 'offer_waiting_other_party' using errcode = 'P0001';
  end if;

  if v_action in ('accept', 'accepted') then
    -- Keep accept deterministic from the latest pending state.
    -- Do not trust p_amount override from client.
    v_agreed := coalesce(v_offer.counter_amount, v_offer.amount);
    if v_agreed is null or v_agreed <= 0 then
      raise exception 'invalid_amount' using errcode = '22023';
    end if;

    update public.offers
    set status = 'accepted',
        agreed_amount = v_agreed,
        responded_at = v_now,
        message = coalesce(v_message, message),
        updated_at = v_now
    where id = v_offer.id
    returning * into v_offer;

    update public.offers
    set status = 'rejected',
        responded_at = coalesce(responded_at, v_now),
        updated_at = v_now
    where product_id = v_offer.product_id
      and id <> v_offer.id
      and status = 'pending';

    perform public.emit_offer_system_message(
      v_offer.product_id,
      v_offer.buyer_id,
      v_offer.seller_id,
      v_offer.id,
      'accepted',
      v_agreed,
      'offer:' || v_offer.id::text || ':accepted'
    );

  elsif v_action in ('reject', 'rejected') then
    update public.offers
    set status = 'rejected',
        responded_at = v_now,
        message = coalesce(v_message, message),
        updated_at = v_now
    where id = v_offer.id
    returning * into v_offer;

    perform public.emit_offer_system_message(
      v_offer.product_id,
      v_offer.buyer_id,
      v_offer.seller_id,
      v_offer.id,
      'rejected',
      null,
      'offer:' || v_offer.id::text || ':rejected'
    );

  elsif v_action = 'counter' then
    if p_amount is null or p_amount <= 0 then
      raise exception 'invalid_amount' using errcode = '22023';
    end if;

    -- Buyer cannot submit any (new) amount below 50% of initial product price.
    if v_actor = v_offer.buyer_id then
      select p.price into v_product_price
      from public.products p
      where p.id = v_offer.product_id;

      v_min_amount := greatest(1::numeric, ceil(coalesce(v_product_price, 0::numeric) * 0.5));
      if p_amount < v_min_amount then
        raise exception 'offer_below_min_ratio'
          using errcode = '22023',
                detail = 'min_offer=' || v_min_amount::text,
                hint = 'offer must be at least 50% of product price';
      end if;
    end if;

    update public.offers
    set status = 'pending',
        counter_amount = p_amount,
        counter_by = v_actor,
        responded_at = v_now,
        message = coalesce(v_message, message),
        updated_at = v_now
    where id = v_offer.id
    returning * into v_offer;

    perform public.emit_offer_system_message(
      v_offer.product_id,
      v_offer.buyer_id,
      v_offer.seller_id,
      v_offer.id,
      'counter',
      p_amount,
      null
    );

  else
    raise exception 'invalid_action' using errcode = '22023';
  end if;

  return v_offer;
end;
$$;
revoke all on function public.respond_offer(bigint, text, numeric, text) from public;
grant execute on function public.respond_offer(bigint, text, numeric, text) to authenticated;

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
  p_fee_amount numeric,
  p_shipping_selection jsonb default null
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
  v_shipping_free boolean := false;
  v_shipping_cost numeric;
  v_order_id bigint;
  v_offer_agreed numeric;
  v_effective_price numeric;
begin
  if v_buyer is null then
    raise exception 'auth required';
  end if;

  select owner_id, price, cost_price, stock_quantity, coalesce(shipping_free, false)
  into v_seller, v_price, v_cost, v_stock, v_shipping_free
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

  select coalesce(o.agreed_amount, o.counter_amount, o.amount)
    into v_offer_agreed
  from public.offers o
  where o.product_id = p_product_id
    and o.buyer_id = v_buyer
    and o.status = 'accepted'
  order by coalesce(o.responded_at, o.updated_at, o.created_at) desc, o.id desc
  limit 1;

  v_effective_price := coalesce(v_offer_agreed, v_price);

  v_shipping_cost := case
    when v_shipping_free then 0
    else p_shipping_cost
  end;
  if not v_shipping_free and v_shipping_cost is null then
    raise exception 'shipping fee required';
  end if;
  if v_shipping_cost is not null and v_shipping_cost < 0 then
    raise exception 'invalid shipping fee';
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
    shipping_selection,
    status
  ) values (
    p_product_id,
    v_buyer,
    v_seller,
    p_shipping_address_id,
    p_shipping_option,
    v_shipping_cost,
    coalesce(p_payment_method, 'cod'),
    case when coalesce(p_payment_method, 'cod') = 'cod' then 'pending' else 'paid' end,
    p_delivery_method,
    v_offer_agreed,
    p_courier_id,
    p_courier_name,
    v_effective_price,
    v_cost,
    coalesce(p_fee_amount, 0),
    coalesce(v_shipping_cost, 0),
    p_shipping_selection,
    'pending'
  ) returning id into v_order_id;

  update public.products
  set stock_quantity = stock_quantity - 1
  where id = p_product_id;

  begin
    perform public.post_order_event(
      v_order_id,
      'order_created',
      jsonb_build_object(
        'i18n_key', 'order.system.created',
        'status', 'pending',
        'status_i18n', 'order.status.pending'
      ),
      'order:' || v_order_id || ':created'
    );
  exception when others then
    -- Do not block order creation if chat/event pipeline fails.
    null;
  end;

  return v_order_id;
end;
$$;

revoke all on function public.create_order(bigint, bigint, text, text, text, numeric, text, text, numeric, numeric, jsonb) from public;
grant execute on function public.create_order(bigint, bigint, text, text, text, numeric, text, text, numeric, numeric, jsonb) to authenticated;
