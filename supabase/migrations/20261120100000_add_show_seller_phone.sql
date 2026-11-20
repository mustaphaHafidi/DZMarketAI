-- Opt-in per-listing display of the seller's own (already-validated) phone
-- number. Additive only: one new nullable-default boolean column on
-- public.products. No existing row, column type, or RLS policy is changed.
-- Reuses public.profiles.phone (already collected and format-validated at
-- signup) instead of adding a free-text phone field per listing.

alter table public.products
  add column if not exists show_seller_phone boolean not null default false;
