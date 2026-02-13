-- Protect "arranged delivery" orders from shipment label jobs and stale-order auto-cancel.

create or replace function public.is_arranged_delivery_mode(p_value text)
returns boolean
language sql
immutable
as $$
  select regexp_replace(lower(coalesce(p_value, '')), '[^a-z0-9]+', '', 'g') in (
    'pickup',
    'livraisonaconvenir',
    'deliveryarranged',
    'arrangeddelivery',
    'remiseenmainpropre',
    'mainpropre'
  );
$$;

create or replace function public.cancel_stale_orders(p_cutoff interval default interval '3 days')
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
  v_count integer := 0;
begin
  for rec in
    select o.id
    from public.orders o
    left join public.shipments s on s.order_id = o.id
    where o.status in ('pending', 'paid')
      and o.created_at < now() - p_cutoff
      and not public.is_arranged_delivery_mode(o.delivery_method)
      and not public.is_arranged_delivery_mode(o.shipping_option)
      and (s.order_id is null or s.label_url is null)
  loop
    update public.orders
    set status = 'cancelled',
        payment_status = case when payment_status = 'paid' then 'failed' else payment_status end,
        updated_at = now()
    where id = rec.id;

    begin
      perform public.post_order_event(
        rec.id,
        'order_cancelled',
        jsonb_build_object(
          'i18n_key', 'order.system.cancelled',
          'status', 'cancelled',
          'status_i18n', 'order.status.cancelled'
        ),
        'order:' || rec.id || ':cancelled'
      );
    exception when others then
      null;
    end;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.cancel_stale_orders(interval) from public;
grant execute on function public.cancel_stale_orders(interval) to service_role;
