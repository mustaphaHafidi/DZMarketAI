-- Centralized courier parcel constraints for app + edge validation.

create table if not exists public.courier_parcel_rules (
  courier_code text primary key,
  min_weight_kg integer not null default 1 check (min_weight_kg >= 0),
  max_weight_kg integer not null default 60 check (max_weight_kg >= min_weight_kg),
  max_height_cm integer not null default 200 check (max_height_cm >= 0),
  max_width_cm integer not null default 200 check (max_width_cm >= 0),
  max_length_cm integer not null default 200 check (max_length_cm >= 0),
  max_volume_cm3 integer not null default 8000000 check (max_volume_cm3 >= 0),
  max_declared_value numeric(12,2) not null default 99999999 check (max_declared_value >= 0),
  overweight_threshold_kg integer not null default 5 check (overweight_threshold_kg >= 0),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists courier_parcel_rules_updated_idx
  on public.courier_parcel_rules (updated_at desc);

alter table public.courier_parcel_rules enable row level security;

drop policy if exists "courier parcel rules read" on public.courier_parcel_rules;
drop policy if exists "courier parcel rules write service" on public.courier_parcel_rules;

create policy "courier parcel rules read" on public.courier_parcel_rules
  for select using (true);

create policy "courier parcel rules write service" on public.courier_parcel_rules
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop trigger if exists courier_parcel_rules_touch on public.courier_parcel_rules;
create trigger courier_parcel_rules_touch
  before update on public.courier_parcel_rules
  for each row execute procedure public.touch_updated_at();

insert into public.courier_parcel_rules (
  courier_code,
  min_weight_kg,
  max_weight_kg,
  max_height_cm,
  max_width_cm,
  max_length_cm,
  max_volume_cm3,
  max_declared_value,
  overweight_threshold_kg
) values
  ('yalidine', 1, 60, 200, 200, 200, 8000000, 99999999, 5),
  ('ecotrack', 1, 60, 200, 200, 200, 8000000, 99999999, 5),
  ('zrexpress', 1, 60, 200, 200, 200, 8000000, 99999999, 5)
on conflict (courier_code) do update set
  min_weight_kg = excluded.min_weight_kg,
  max_weight_kg = excluded.max_weight_kg,
  max_height_cm = excluded.max_height_cm,
  max_width_cm = excluded.max_width_cm,
  max_length_cm = excluded.max_length_cm,
  max_volume_cm3 = excluded.max_volume_cm3,
  max_declared_value = excluded.max_declared_value,
  overweight_threshold_kg = excluded.overweight_threshold_kg,
  updated_at = now();
