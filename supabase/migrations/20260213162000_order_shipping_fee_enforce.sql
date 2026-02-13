-- Enforce shipping fee consistency at order creation.
-- If product has free shipping => fee forced to 0.
-- If product is not free shipping => shipping fee is required.

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
    p_agreed_price,
    p_courier_id,
    p_courier_name,
    coalesce(p_agreed_price, v_price),
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
