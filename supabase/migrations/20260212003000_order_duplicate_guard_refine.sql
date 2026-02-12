-- Refine duplicate-order protection:
-- allow repeated orders when buyer changes courier/method,
-- block only near-identical accidental double submit.

create or replace function public.enforce_order_limits()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.consume_rate_limit('order:' || new.buyer_id::text, 10, 3600) then
    raise exception 'order rate limit exceeded';
  end if;

  if exists (
    select 1
    from public.orders o
    where o.buyer_id = new.buyer_id
      and o.product_id = new.product_id
      and o.status in ('pending', 'paid', 'shipped')
      and o.created_at > now() - interval '20 seconds'
      and coalesce(o.courier_id, '') = coalesce(new.courier_id, '')
      and coalesce(o.delivery_method, '') = coalesce(new.delivery_method, '')
      and coalesce(o.shipping_option, '') = coalesce(new.shipping_option, '')
      and coalesce(o.shipping_address_id, -1) = coalesce(new.shipping_address_id, -1)
  ) then
    raise exception 'duplicate order';
  end if;

  if new.shipping_address_id is not null
    and not exists (
      select 1
      from public.addresses a
      where a.id = new.shipping_address_id
        and a.user_id = new.buyer_id
    ) then
    raise exception 'invalid shipping address';
  end if;

  return new;
end;
$$;
