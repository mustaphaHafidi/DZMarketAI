-- Add the "Vehicules" category tree and the vehicle-specific product
-- columns (year, mileage, fuel, transmission, body type). Additive only:
-- new nullable columns on public.products, new rows in public.categories.
-- No existing row, column type, or RLS policy is changed.
-- No plate/VIN/papers field is added on purpose (privacy/security).
-- 6 sub-categories (decision 2026-11-18, revised from an earlier 4-way
-- split): Voitures / Motos & Scooters / Utilitaires / Camions / Engins /
-- Bateaux. "Utilitaires", "Camions" and "Engins" match the Algerian
-- market leader's own vehicle taxonomy (Ouedkniss: Voitures, Utilitaire,
-- Motos & Scooters, Camion, Engin, among others); "Bateaux" has no direct
-- competitor precedent found but is kept per founder decision.

alter table public.products
  add column if not exists vehicle_model text,
  add column if not exists vehicle_year integer,
  add column if not exists vehicle_mileage_km integer,
  add column if not exists vehicle_fuel text,
  add column if not exists vehicle_transmission text,
  add column if not exists vehicle_body_type text;

insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active)
values ('vehicles', 'Vehicules', 'Vehicules', 'مركبات', null, 100, true)
on conflict (slug) do nothing;

with parent as (
  select id from public.categories where slug = 'vehicles'
)
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active)
select v.slug, v.name_fr, v.name_fr, v.name_ar, parent.id, v.sort_order, true
from parent,
  (values
    ('vehicles-cars', 'Voitures', 'سيارات', 1),
    ('vehicles-motorcycles', 'Motos & Scooters', 'دراجات نارية وسكوتر', 2),
    ('vehicles-utility', 'Utilitaires', 'مركبات نفعية', 3),
    ('vehicles-trucks', 'Camions', 'شاحنات', 4),
    ('vehicles-equipment', 'Engins', 'آليات ثقيلة', 5),
    ('vehicles-boats', 'Bateaux', 'قوارب', 6)
  ) as v(slug, name_fr, name_ar, sort_order)
on conflict (slug) do nothing;
