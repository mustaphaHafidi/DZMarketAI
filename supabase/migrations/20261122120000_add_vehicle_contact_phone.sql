-- An optional public contact number belonging to one vehicle listing only.
-- Additive and nullable: existing listings remain unchanged.
alter table public.products
  add column if not exists contact_phone text;

comment on column public.products.contact_phone is
  'Optional E.164 Algerian mobile contact number shown only on a vehicle listing.';
