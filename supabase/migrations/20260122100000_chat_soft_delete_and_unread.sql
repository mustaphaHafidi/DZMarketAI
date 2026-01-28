-- Chat soft delete + unread consistency

alter table public.chat_rooms
  add column if not exists deleted_by_buyer boolean default false,
  add column if not exists deleted_by_seller boolean default false;

create index if not exists chat_rooms_last_message_at_idx
  on public.chat_rooms (last_message_at desc);

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

  return new;
end;
$$ language plpgsql;

create or replace function public.hide_chat_room(p_room_id text)
returns void as $$
begin
  update public.chat_rooms
  set deleted_by_buyer = case when auth.uid() = buyer_id then true else deleted_by_buyer end,
      deleted_by_seller = case when auth.uid() = seller_id then true else deleted_by_seller end
  where room_id = p_room_id;
end;
$$ language plpgsql security definer;
