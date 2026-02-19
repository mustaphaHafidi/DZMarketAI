-- Chat unread counters + deterministic ordering support.
-- Goal:
-- 1) show clear unread counts per conversation in UI,
-- 2) keep conversation ordering stable on latest received message.

alter table public.conversations
  add column if not exists unread_by_buyer integer not null default 0,
  add column if not exists unread_by_seller integer not null default 0;

create or replace function public.update_conversation_last_message()
returns trigger
language plpgsql
as $$
begin
  update public.conversations c
  set
    last_message_at = new.created_at,
    last_message_text = new.text,
    unread_by_buyer = case
      when c.buyer_id is null then 0
      when new.sender_id = c.buyer_id then c.unread_by_buyer
      else c.unread_by_buyer + 1
    end,
    unread_by_seller = case
      when c.seller_id is null then 0
      when new.sender_id = c.seller_id then c.unread_by_seller
      else c.unread_by_seller + 1
    end,
    updated_at = now()
  where c.id = new.conversation_id;

  return new;
end;
$$;

drop trigger if exists messages_update_conversation on public.messages;
create trigger messages_update_conversation
  after insert on public.messages
  for each row execute procedure public.update_conversation_last_message();

-- mark_read now also refreshes unread counters for the current participant.
create or replace function public.mark_read(p_conversation_id uuid, p_last_message_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_read_at timestamptz;
begin
  if not public.is_participant(p_conversation_id) then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  select m.created_at
    into v_read_at
  from public.messages m
  where m.id = p_last_message_id
    and m.conversation_id = p_conversation_id;

  if v_read_at is null then
    v_read_at := now();
  end if;

  insert into public.reads (conversation_id, user_id, last_read_at, last_read_message_id)
  values (p_conversation_id, auth.uid(), v_read_at, p_last_message_id)
  on conflict (conversation_id, user_id) do update
    set last_read_at = excluded.last_read_at,
        last_read_message_id = excluded.last_read_message_id;

  update public.conversations c
  set
    unread_by_buyer = case
      when c.buyer_id = auth.uid() then (
        select count(*)::integer
        from public.messages m
        where m.conversation_id = c.id
          and m.deleted_at is null
          and coalesce(m.moderation_status, 'approved') <> 'blocked'
          and m.sender_id is distinct from c.buyer_id
          and m.created_at > v_read_at
      )
      else c.unread_by_buyer
    end,
    unread_by_seller = case
      when c.seller_id = auth.uid() then (
        select count(*)::integer
        from public.messages m
        where m.conversation_id = c.id
          and m.deleted_at is null
          and coalesce(m.moderation_status, 'approved') <> 'blocked'
          and m.sender_id is distinct from c.seller_id
          and m.created_at > v_read_at
      )
      else c.unread_by_seller
    end,
    updated_at = now()
  where c.id = p_conversation_id;
end;
$$;

revoke all on function public.mark_read(uuid, uuid) from public;
grant execute on function public.mark_read(uuid, uuid) to authenticated;

-- Backfill counters from current reads/messages state.
update public.conversations c
set
  unread_by_buyer = case
    when c.buyer_id is null then 0
    else (
      select count(*)::integer
      from public.messages m
      left join public.reads r
        on r.conversation_id = c.id
       and r.user_id = c.buyer_id
      where m.conversation_id = c.id
        and m.deleted_at is null
        and coalesce(m.moderation_status, 'approved') <> 'blocked'
        and m.sender_id is distinct from c.buyer_id
        and (r.last_read_at is null or m.created_at > r.last_read_at)
    )
  end,
  unread_by_seller = case
    when c.seller_id is null then 0
    else (
      select count(*)::integer
      from public.messages m
      left join public.reads r
        on r.conversation_id = c.id
       and r.user_id = c.seller_id
      where m.conversation_id = c.id
        and m.deleted_at is null
        and coalesce(m.moderation_status, 'approved') <> 'blocked'
        and m.sender_id is distinct from c.seller_id
        and (r.last_read_at is null or m.created_at > r.last_read_at)
    )
  end;
