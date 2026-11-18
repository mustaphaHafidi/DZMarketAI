-- Additional optional technical fields for road vehicles.
-- Separate migration: the initial vehicle migration may already be applied.
alter table public.products
  add column if not exists vehicle_engine text,
  add column if not exists vehicle_power_hp integer;
