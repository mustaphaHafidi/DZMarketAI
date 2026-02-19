-- Notification center (chat/offers/orders) end-to-end.
-- Phase 1: centralized event table + user preferences.
-- Phase 2: emit helpers + DB triggers for key business events.
-- Phase 3: mark-read RPCs for app UX.

create table if not exists public.notification_events (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null check (category in ('chat', 'offer', 'order', 'system')),
  title_i18n text not null,
  body_i18n text not null,
  payload jsonb not null default '{}'::jsonb,
  dedupe_key text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notification_events_user_created_idx
  on public.notification_events (user_id, created_at desc);

create index if not exists notification_events_user_unread_idx
  on public.notification_events (user_id, read_at, created_at desc);

create unique index if not exists notification_events_user_dedupe_uniq
  on public.notification_events (user_id, dedupe_key);

alter table public.notification_events enable row level security;

drop policy if exists notification_events_select_own on public.notification_events;
create policy notification_events_select_own
  on public.notification_events
  for select
  using (auth.uid() = user_id);

drop policy if exists notification_events_update_own on public.notification_events;
create policy notification_events_update_own
  on public.notification_events
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, update on public.notification_events to authenticated;

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  enable_chat boolean not null default true,
  enable_offer boolean not null default true,
  enable_order boolean not null default true,
  enable_system boolean not null default true,
  mute_until timestamptz,
  updated_at timestamptz not null default now()
);

drop trigger if exists notification_preferences_touch on public.notification_preferences;
create trigger notification_preferences_touch
  before update on public.notification_preferences
  for each row execute procedure public.touch_updated_at();

alter table public.notification_preferences enable row level security;

drop policy if exists notification_preferences_select_own on public.notification_preferences;
create policy notification_preferences_select_own
  on public.notification_preferences
  for select
  using (auth.uid() = user_id);

drop policy if exists notification_preferences_insert_own on public.notification_preferences;
create policy notification_preferences_insert_own
  on public.notification_preferences
  for insert
  with check (auth.uid() = user_id);

drop policy if exists notification_preferences_update_own on public.notification_preferences;
create policy notification_preferences_update_own
  on public.notification_preferences
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update on public.notification_preferences to authenticated;

create or replace function public.notifications_enabled_for_user(
  p_user_id uuid,
  p_category text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  prefs public.notification_preferences;
  v_category text := lower(trim(coalesce(p_category, 'system')));
begin
  if p_user_id is null then
    return false;
  end if;

  select * into prefs
  from public.notification_preferences
  where user_id = p_user_id;

  if prefs.user_id is null then
    return true;
  end if;

  if prefs.mute_until is not null and prefs.mute_until > now() then
    return false;
  end if;

  if v_category = 'chat' then
    return prefs.enable_chat;
  elsif v_category = 'offer' then
    return prefs.enable_offer;
  elsif v_category = 'order' then
    return prefs.enable_order;
  elsif v_category = 'system' then
    return prefs.enable_system;
  end if;

  return true;
end;
$$;

revoke all on function public.notifications_enabled_for_user(uuid, text) from public;
grant execute on function public.notifications_enabled_for_user(uuid, text) to authenticated, service_role;

create or replace function public.emit_notification(
  p_user_id uuid,
  p_category text,
  p_title_i18n text,
  p_body_i18n text,
  p_payload jsonb default '{}'::jsonb,
  p_dedupe_key text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean;
begin
  if p_user_id is null then
    return;
  end if;

  v_enabled := public.notifications_enabled_for_user(p_user_id, p_category);
  if not v_enabled then
    return;
  end if;

  insert into public.notification_events (
    user_id,
    category,
    title_i18n,
    body_i18n,
    payload,
    dedupe_key
  )
  values (
    p_user_id,
    lower(trim(coalesce(p_category, 'system'))),
    coalesce(nullif(trim(p_title_i18n), ''), 'notifications.system.title'),
    coalesce(nullif(trim(p_body_i18n), ''), 'notifications.system.body'),
    coalesce(p_payload, '{}'::jsonb),
    nullif(trim(coalesce(p_dedupe_key, '')), '')
  )
  on conflict (user_id, dedupe_key) do nothing;
end;
$$;

revoke all on function public.emit_notification(uuid, text, text, text, jsonb, text) from public;
grant execute on function public.emit_notification(uuid, text, text, text, jsonb, text) to authenticated, service_role;

create or replace function public.notify_on_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  conv public.conversations;
  recipient uuid;
  body_key text;
  snippet text;
begin
  select *
    into conv
  from public.conversations
  where id = new.conversation_id;

  if conv.id is null then
    return new;
  end if;

  if new.sender_id = conv.buyer_id then
    recipient := conv.seller_id;
  elsif new.sender_id = conv.seller_id then
    recipient := conv.buyer_id;
  else
    recipient := conv.seller_id;
  end if;

  if recipient is null then
    return new;
  end if;

  body_key := case
    when coalesce(new.type, 'text') = 'system' then 'notifications.chat.system'
    else 'notifications.chat.new_message'
  end;
  snippet := left(coalesce(new.text, ''), 120);

  perform public.emit_notification(
    recipient,
    'chat',
    'notifications.chat.title',
    body_key,
    jsonb_build_object(
      'conversation_id', new.conversation_id,
      'message_id', new.id,
      'product_id', conv.product_id,
      'order_id', conv.order_id,
      'sender_id', new.sender_id,
      'type', coalesce(new.type, 'text'),
      'snippet', snippet
    ),
    'msg:' || new.id::text || ':u:' || recipient::text
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_message_insert on public.messages;
create trigger trg_notify_message_insert
  after insert on public.messages
  for each row execute procedure public.notify_on_message_insert();

create or replace function public.notify_on_offer_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recipient uuid;
  body_key text;
  amount_value numeric;
begin
  if tg_op = 'INSERT' then
    perform public.emit_notification(
      new.seller_id,
      'offer',
      'notifications.offer.title',
      'notifications.offer.new',
      jsonb_build_object(
        'offer_id', new.id,
        'product_id', new.product_id,
        'amount', new.amount,
        'status', new.status
      ),
      'offer:' || new.id::text || ':new:seller'
    );
    return new;
  end if;

  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.status is distinct from new.status then
    if new.status = 'accepted' then
      recipient := new.buyer_id;
      body_key := 'notifications.offer.accepted';
      amount_value := coalesce(new.agreed_amount, new.counter_amount, new.amount);
    elsif new.status = 'rejected' then
      recipient := new.buyer_id;
      body_key := 'notifications.offer.rejected';
      amount_value := coalesce(new.counter_amount, new.amount);
    else
      return new;
    end if;

    perform public.emit_notification(
      recipient,
      'offer',
      'notifications.offer.title',
      body_key,
      jsonb_build_object(
        'offer_id', new.id,
        'product_id', new.product_id,
        'amount', amount_value,
        'status', new.status
      ),
      'offer:' || new.id::text || ':status:' || new.status || ':u:' || recipient::text
    );

    return new;
  end if;

  if old.counter_amount is distinct from new.counter_amount
     and new.status = 'pending' then
    if new.counter_by = new.seller_id then
      recipient := new.buyer_id;
    elsif new.counter_by = new.buyer_id then
      recipient := new.seller_id;
    else
      recipient := null;
    end if;

    if recipient is not null then
      perform public.emit_notification(
        recipient,
        'offer',
        'notifications.offer.title',
        'notifications.offer.counter',
        jsonb_build_object(
          'offer_id', new.id,
          'product_id', new.product_id,
          'amount', coalesce(new.counter_amount, new.amount),
          'status', new.status
        ),
        'offer:' || new.id::text || ':counter:' || coalesce(new.counter_amount::text, '0') || ':u:' || recipient::text
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_offer_change on public.offers;
create trigger trg_notify_offer_change
  after insert or update on public.offers
  for each row execute procedure public.notify_on_offer_change();

create or replace function public.notify_on_order_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.emit_notification(
      new.buyer_id,
      'order',
      'notifications.order.title',
      'notifications.order.created_buyer',
      jsonb_build_object(
        'order_id', new.id,
        'status', new.status,
        'status_i18n', 'order.status.' || coalesce(new.status, 'pending')
      ),
      'order:' || new.id::text || ':created:buyer:' || new.buyer_id::text
    );

    perform public.emit_notification(
      new.seller_id,
      'order',
      'notifications.order.title',
      'notifications.order.created_seller',
      jsonb_build_object(
        'order_id', new.id,
        'status', new.status,
        'status_i18n', 'order.status.' || coalesce(new.status, 'pending')
      ),
      'order:' || new.id::text || ':created:seller:' || new.seller_id::text
    );
    return new;
  end if;

  if tg_op = 'UPDATE' and old.status is distinct from new.status then
    perform public.emit_notification(
      new.buyer_id,
      'order',
      'notifications.order.title',
      'notifications.order.status',
      jsonb_build_object(
        'order_id', new.id,
        'status', new.status,
        'status_i18n', 'order.status.' || coalesce(new.status, 'pending')
      ),
      'order:' || new.id::text || ':status:' || coalesce(new.status, 'pending') || ':buyer'
    );

    perform public.emit_notification(
      new.seller_id,
      'order',
      'notifications.order.title',
      'notifications.order.status',
      jsonb_build_object(
        'order_id', new.id,
        'status', new.status,
        'status_i18n', 'order.status.' || coalesce(new.status, 'pending')
      ),
      'order:' || new.id::text || ':status:' || coalesce(new.status, 'pending') || ':seller'
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_order_change on public.orders;
create trigger trg_notify_order_change
  after insert or update on public.orders
  for each row execute procedure public.notify_on_order_change();

create or replace function public.mark_notification_read(p_notification_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  update public.notification_events
  set read_at = coalesce(read_at, now())
  where id = p_notification_id
    and user_id = auth.uid();
end;
$$;

revoke all on function public.mark_notification_read(bigint) from public;
grant execute on function public.mark_notification_read(bigint) to authenticated;

create or replace function public.mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  update public.notification_events
  set read_at = now()
  where user_id = auth.uid()
    and read_at is null;

  get diagnostics affected = row_count;
  return affected;
end;
$$;

revoke all on function public.mark_all_notifications_read() from public;
grant execute on function public.mark_all_notifications_read() to authenticated;
