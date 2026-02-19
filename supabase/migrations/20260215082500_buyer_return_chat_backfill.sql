-- Ensure every buyer return event also posts a system chat message.
-- Includes a backfill for existing buyer_return_events rows.

create or replace function public.sync_buyer_return_event_to_chat()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform public.post_order_event(
      new.order_id,
      'order_returned',
      jsonb_build_object(
        'i18n_key', 'order.system.returned',
        'status', new.status,
        'status_i18n', 'order.status.' || new.status,
        'courier_id', new.courier_id
      ),
      'order:' || new.order_id || ':returned:' || new.status
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;

drop trigger if exists trg_buyer_return_events_chat on public.buyer_return_events;
create trigger trg_buyer_return_events_chat
after insert on public.buyer_return_events
for each row
execute function public.sync_buyer_return_event_to_chat();

do $$
declare
  rec record;
begin
  for rec in
    select order_id, status, courier_id
    from public.buyer_return_events
  loop
    begin
      perform public.post_order_event(
        rec.order_id,
        'order_returned',
        jsonb_build_object(
          'i18n_key', 'order.system.returned',
          'status', rec.status,
          'status_i18n', 'order.status.' || rec.status,
          'courier_id', rec.courier_id
        ),
        'order:' || rec.order_id || ':returned:' || rec.status
      );
    exception when others then
      null;
    end;
  end loop;
end
$$;

revoke all on function public.sync_buyer_return_event_to_chat() from public;
grant execute on function public.sync_buyer_return_event_to_chat() to service_role;
