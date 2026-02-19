-- Product negotiability guardrails for offers.
-- - New products are negotiable by default.
-- - Existing products are backfilled to negotiable=true.
-- - New offers are blocked when product is marked non-negotiable.
-- - Existing pending offers remain untouched.

alter table public.products
  add column if not exists is_negotiable boolean;

update public.products
set is_negotiable = true
where is_negotiable is null;

alter table public.products
  alter column is_negotiable set default true;

alter table public.products
  alter column is_negotiable set not null;

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

  select p.id, p.owner_id, p.status, p.is_archived, p.stock_quantity, p.price, p.is_negotiable
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

  if coalesce(v_product.is_negotiable, true) = false then
    raise exception 'offer_not_negotiable' using errcode = '22023';
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
