-- Chat per-user visibility (deleted_at) + view for filtered list

create table if not exists public.chat_room_users (
  room_id text not null references public.chat_rooms(room_id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  deleted_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  primary key (room_id, user_id)
);

alter table public.chat_room_users enable row level security;
drop policy if exists "chat_room_users select own" on public.chat_room_users;
drop policy if exists "chat_room_users insert own" on public.chat_room_users;
drop policy if exists "chat_room_users update own" on public.chat_room_users;
create policy "chat_room_users select own" on public.chat_room_users
  for select using (
    auth.uid() = user_id
    and exists (
      select 1 from public.chat_rooms r
      where r.room_id = chat_room_users.room_id
        and (r.buyer_id = auth.uid() or r.seller_id = auth.uid())
    )
  );
create policy "chat_room_users insert own" on public.chat_room_users
  for insert with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.chat_rooms r
      where r.room_id = chat_room_users.room_id
        and (r.buyer_id = auth.uid() or r.seller_id = auth.uid())
    )
  );
create policy "chat_room_users update own" on public.chat_room_users
  for update using (
    auth.uid() = user_id
    and exists (
      select 1 from public.chat_rooms r
      where r.room_id = chat_room_users.room_id
        and (r.buyer_id = auth.uid() or r.seller_id = auth.uid())
    )
  );

drop view if exists public.chat_rooms_visible;
create view public.chat_rooms_visible as
select
  cru.user_id,
  cru.deleted_at,
  r.room_id,
  r.product_id,
  r.buyer_id,
  r.seller_id,
  r.order_id,
  r.last_message,
  r.last_message_type,
  r.last_message_at,
  r.last_sender_id,
  r.unread_by_buyer,
  r.unread_by_seller,
  r.hidden_by,
  r.deleted_by_buyer,
  r.deleted_by_seller,
  r.created_at,
  r.updated_at
from public.chat_room_users cru
join public.chat_rooms r on r.room_id = cru.room_id;

alter view public.chat_rooms_visible enable row level security;
drop policy if exists "chat rooms visible select" on public.chat_rooms_visible;
create policy "chat rooms visible select" on public.chat_rooms_visible
  for select using (auth.uid() = user_id and deleted_at is null);

create index if not exists chat_room_users_deleted_idx
  on public.chat_room_users (user_id, deleted_at);

create or replace function public.update_chat_room_last_message()
returns trigger as $$
declare
  v_buyer uuid;
  v_seller uuid;
  v_product bigint;
  v_order bigint;
begin
  if new.room_id like 'product:%' then
    if split_part(new.room_id, ':', 3) !~* '^[0-9a-f-]{36}$'
      or split_part(new.room_id, ':', 4) !~* '^[0-9a-f-]{36}$' then
      return new;
    end if;
    v_product := split_part(new.room_id, ':', 2)::bigint;
    v_buyer := split_part(new.room_id, ':', 3)::uuid;
    v_seller := split_part(new.room_id, ':', 4)::uuid;
  elsif new.room_id like 'order:%' then
    v_order := split_part(new.room_id, ':', 2)::bigint;
    select buyer_id, seller_id into v_buyer, v_seller
    from public.orders where id = v_order;
    if v_buyer is null or v_seller is null then
      return new;
    end if;
  else
    return new;
  end if;

  insert into public.chat_rooms (
    room_id,
    product_id,
    order_id,
    buyer_id,
    seller_id,
    last_message,
    last_message_type,
    last_message_at,
    last_sender_id
  )
  values (
    new.room_id,
    v_product,
    v_order,
    v_buyer,
    v_seller,
    new.content,
    new.type,
    new.created_at,
    new.sender_id
  )
  on conflict (room_id) do update set
    last_message = excluded.last_message,
    last_message_type = excluded.last_message_type,
    last_message_at = excluded.last_message_at,
    last_sender_id = excluded.last_sender_id,
    unread_by_buyer = case
      when new.sender_id = v_buyer then public.chat_rooms.unread_by_buyer
      else public.chat_rooms.unread_by_buyer + 1 end,
    unread_by_seller = case
      when new.sender_id = v_seller then public.chat_rooms.unread_by_seller
      else public.chat_rooms.unread_by_seller + 1 end,
    deleted_by_buyer = false,
    deleted_by_seller = false,
    hidden_by = array_remove(public.chat_rooms.hidden_by, new.sender_id::text);

  insert into public.chat_room_users (room_id, user_id, deleted_at)
  values (new.room_id, v_buyer, null), (new.room_id, v_seller, null)
  on conflict (room_id, user_id) do update set
    deleted_at = null,
    updated_at = now();

  return new;
end;
$$ language plpgsql;

create or replace function public.hide_chat_room(p_room_id text)
returns void as $$
begin
  update public.chat_rooms
  set deleted_by_buyer = case when auth.uid() = buyer_id then true else deleted_by_buyer end,
      deleted_by_seller = case when auth.uid() = seller_id then true else deleted_by_seller end,
      hidden_by = case
        when hidden_by @> array[auth.uid()::text] then hidden_by
        else array_append(hidden_by, auth.uid()::text)
      end
  where room_id = p_room_id;

  insert into public.chat_room_users (room_id, user_id, deleted_at)
  values (p_room_id, auth.uid(), now())
  on conflict (room_id, user_id) do update set
    deleted_at = now(),
    updated_at = now();
end;
$$ language plpgsql security definer;
