-- Offer workflow hardening: atomic offer actions + chat thread consistency.

-- Keep only one pending offer per buyer/product before adding unique partial index.
with ranked as (
  select
    id,
    row_number() over (
      partition by product_id, buyer_id
      order by created_at desc, id desc
    ) as rn
  from public.offers
  where status = 'pending'
)
update public.offers o
set status = 'cancelled',
    responded_at = coalesce(o.responded_at, now()),
    updated_at = now()
from ranked r
where o.id = r.id
  and r.rn > 1;

create unique index if not exists offers_pending_buyer_product_uniq
  on public.offers (product_id, buyer_id)
  where status = 'pending';

create or replace function public.emit_offer_system_message(
  p_product_id bigint,
  p_buyer_id uuid,
  p_seller_id uuid,
  p_offer_id bigint,
  p_event text,
  p_amount numeric default null,
  p_dedupe_key text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  conv public.conversations;
  msg public.messages;
  v_event text := lower(trim(coalesce(p_event, '')));
  v_text text;
  v_i18n text;
begin
  conv := public.ensure_conversation(p_product_id, p_buyer_id, p_seller_id);

  if v_event = 'created' then
    v_i18n := 'offer.system.created';
    v_text := 'Nouvelle offre: DA ' || coalesce(round(p_amount)::text, '0');
  elsif v_event = 'counter' then
    v_i18n := 'offer.system.counter';
    v_text := 'Contre-offre: DA ' || coalesce(round(p_amount)::text, '0');
  elsif v_event = 'accepted' then
    v_i18n := 'offer.system.accepted';
    v_text := 'Offre acceptee: DA ' || coalesce(round(p_amount)::text, '0');
  elsif v_event = 'rejected' then
    v_i18n := 'offer.system.rejected';
    v_text := 'Offre refusee';
  else
    v_i18n := 'offer.system.updated';
    v_text := 'Mise a jour offre';
  end if;

  if p_dedupe_key is null or p_dedupe_key = '' then
    insert into public.messages (
      conversation_id,
      sender_id,
      text,
      type,
      payload
    )
    values (
      conv.id,
      coalesce(auth.uid(), p_buyer_id),
      v_text,
      'system',
      jsonb_strip_nulls(
        jsonb_build_object(
          'i18n_key', v_i18n,
          'offer_id', p_offer_id,
          'event', v_event,
          'amount', p_amount,
          'actor_id', auth.uid()
        )
      )
    )
    returning * into msg;
  else
    insert into public.messages (
      conversation_id,
      sender_id,
      text,
      type,
      payload,
      dedupe_key
    )
    values (
      conv.id,
      coalesce(auth.uid(), p_buyer_id),
      v_text,
      'system',
      jsonb_strip_nulls(
        jsonb_build_object(
          'i18n_key', v_i18n,
          'offer_id', p_offer_id,
          'event', v_event,
          'amount', p_amount,
          'actor_id', auth.uid()
        )
      ),
      p_dedupe_key
    )
    on conflict (conversation_id, dedupe_key) do nothing
    returning * into msg;

    if msg.id is null then
      select * into msg
      from public.messages m
      where m.conversation_id = conv.id
        and m.dedupe_key = p_dedupe_key;
    end if;
  end if;

  if msg.id is not null then
    update public.conversations
    set last_message_at = msg.created_at,
        last_message_text = msg.text,
        updated_at = now()
    where id = conv.id;
  end if;
end;
$$;
revoke all on function public.emit_offer_system_message(bigint, uuid, uuid, bigint, text, numeric, text) from public;
grant execute on function public.emit_offer_system_message(bigint, uuid, uuid, bigint, text, numeric, text) to authenticated;

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

  select p.id, p.owner_id, p.status, p.is_archived, p.stock_quantity
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
    v_agreed := coalesce(p_amount, v_offer.counter_amount, v_offer.amount);
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
