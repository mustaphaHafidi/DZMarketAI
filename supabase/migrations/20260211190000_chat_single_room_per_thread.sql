-- Keep one canonical conversation per buyer/seller/product.
-- Prevent duplicates when orders are created with different delivery methods/couriers.

create or replace function public.ensure_conversation(
  p_product_id bigint,
  p_buyer_id uuid,
  p_seller_id uuid
)
returns public.conversations
language plpgsql
security definer
as $$
declare
  conv public.conversations;
begin
  if auth.uid() not in (p_buyer_id, p_seller_id) then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('conv:' || p_product_id::text || ':' || p_buyer_id::text || ':' || p_seller_id::text)
  );

  select *
    into conv
  from public.conversations c
  where c.product_id = p_product_id
    and c.buyer_id = p_buyer_id
    and c.seller_id = p_seller_id
  order by
    (c.order_id is null) desc,
    c.last_message_at desc nulls last,
    c.created_at desc
  limit 1;

  if conv.id is not null then
    update public.conversations
    set buyer_hidden_at = null,
        seller_hidden_at = null,
        updated_at = now()
    where id = conv.id;
    select * into conv from public.conversations c where c.id = conv.id;
    return conv;
  end if;

  insert into public.conversations (
    product_id,
    buyer_id,
    seller_id,
    last_message_at,
    last_message_text
  )
  values (
    p_product_id,
    p_buyer_id,
    p_seller_id,
    now(),
    null
  )
  returning * into conv;

  return conv;
end;
$$;

create or replace function public.ensure_order_conversation(p_order_id bigint)
returns public.conversations
language plpgsql
security definer
set search_path = public
as $$
declare
  conv public.conversations;
  ord record;
begin
  perform pg_advisory_xact_lock(hashtext('order_conv:' || p_order_id::text));

  select id, buyer_id, seller_id, product_id
    into ord
  from public.orders
  where id = p_order_id;

  if ord.id is null then
    raise exception 'Order not found' using errcode = 'P0002';
  end if;

  if auth.uid() is not null
     and auth.uid() not in (ord.buyer_id, ord.seller_id)
     and auth.role() <> 'service_role' then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'conv_thread:'
      || coalesce(ord.product_id::text, '')
      || ':'
      || coalesce(ord.buyer_id::text, '')
      || ':'
      || coalesce(ord.seller_id::text, '')
    )
  );

  select *
    into conv
  from public.conversations c
  where c.product_id = ord.product_id
    and c.buyer_id = ord.buyer_id
    and c.seller_id = ord.seller_id
  order by
    (c.order_id is null) desc,
    c.last_message_at desc nulls last,
    c.created_at desc
  limit 1;

  if conv.id is not null then
    update public.conversations
    set buyer_hidden_at = null,
        seller_hidden_at = null,
        updated_at = now()
    where id = conv.id;

    if conv.order_id is not null then
      begin
        update public.conversations
        set order_id = null,
            updated_at = now()
        where id = conv.id;
      exception
        when unique_violation then
          null;
      end;
      select * into conv
      from public.conversations c
      where c.id = conv.id;
    end if;

    return conv;
  end if;

  begin
    insert into public.conversations (
      product_id,
      buyer_id,
      seller_id,
      last_message_at,
      last_message_text
    )
    values (
      ord.product_id,
      ord.buyer_id,
      ord.seller_id,
      now(),
      null
    )
    returning * into conv;
  exception
    when unique_violation then
      select *
        into conv
      from public.conversations c
      where c.product_id = ord.product_id
        and c.buyer_id = ord.buyer_id
        and c.seller_id = ord.seller_id
      order by
        (c.order_id is null) desc,
        c.last_message_at desc nulls last,
        c.created_at desc
      limit 1;
  end;

  return conv;
end;
$$;
