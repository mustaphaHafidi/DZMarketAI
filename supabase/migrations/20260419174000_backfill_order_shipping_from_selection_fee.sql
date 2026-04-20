-- Backfill orders that still have zero shipping costs even though checkout
-- stored an estimated fee in shipping_selection.

with shipping_fee_candidates as (
  select
    id,
    coalesce(
      case
        when coalesce(shipping_selection->>'estimatedFee', '') ~ '^[0-9]+(\.[0-9]+)?$'
          then (shipping_selection->>'estimatedFee')::numeric
        else null
      end,
      case
        when coalesce(shipping_selection->>'estimated_fee', '') ~ '^[0-9]+(\.[0-9]+)?$'
          then (shipping_selection->>'estimated_fee')::numeric
        else null
      end
    ) as estimated_fee
  from public.orders
)
update public.orders o
set shipping_cost = case
      when coalesce(o.shipping_cost, 0) > 0 then o.shipping_cost
      else s.estimated_fee
    end,
    delivery_cost = case
      when coalesce(o.delivery_cost, 0) > 0 then o.delivery_cost
      else s.estimated_fee
    end
from shipping_fee_candidates s
where o.id = s.id
  and coalesce(s.estimated_fee, 0) > 0
  and (coalesce(o.shipping_cost, 0) = 0 or coalesce(o.delivery_cost, 0) = 0);
