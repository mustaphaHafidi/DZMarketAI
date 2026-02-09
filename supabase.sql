-- DZMarket Supabase schema (normalized & indexed)
-- Run in Supabase SQL editor. Idempotent where possible.

-- Helpers --------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger as $$
begin
  -- Safely set updated_at only when the column exists on the row type.
  new := jsonb_populate_record(new, jsonb_build_object('updated_at', now()));
  return new;
end;
$$ language plpgsql;

-- Profiles -------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  avatar_url text,
  role text not null default 'buyer', -- buyer | seller | admin
  is_seller boolean not null default false,
  preferences jsonb not null default '{}'::jsonb,
  phone text,
  wilaya text,
  daira text,
  location_lat double precision,
  location_lng double precision,
  bio text,
  lang text default 'fr',
  is_public boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  constraint profiles_email_unique unique (email)
);
alter table public.profiles enable row level security;
drop policy if exists "public profiles read" on public.profiles;
drop policy if exists "own profile update" on public.profiles;
drop policy if exists "insert self" on public.profiles;
create policy "public profiles read" on public.profiles for select using (true);
create policy "own profile update" on public.profiles for update using (auth.uid() = id);
create policy "insert self" on public.profiles for insert with check (auth.uid() = id);
drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch
  before update on public.profiles
  for each row execute procedure public.touch_updated_at();

-- Trigger to auto-create profile on new auth user
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name, role, is_public, is_seller)
  values (new.id, new.email, new.raw_user_meta_data->>'full_name', 'buyer', true, false)
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Translations ---------------------------------------------------------------
create table if not exists public.translations (
  key text not null,
  locale text not null,
  text text not null,
  created_at timestamptz default now(),
  primary key (key, locale)
);
alter table public.translations enable row level security;
drop policy if exists "translations read all" on public.translations;
drop policy if exists "translations write service" on public.translations;
create policy "translations read all" on public.translations for select using (true);
create policy "translations write service" on public.translations for insert
  with check (auth.role() = 'service_role');

insert into public.translations (key, locale, text) values
  ('browse', 'fr', 'Parcourir'),
  ('browse', 'ar', 'ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂµÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­'),
  ('orders', 'fr', 'Commandes'),
  ('orders', 'ar', 'ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â·ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª'),
  ('chat', 'fr', 'Chat'),
  ('chat', 'ar', 'ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â´ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©')
on conflict (key, locale) do nothing;

-- Categories -----------------------------------------------------------------
create table if not exists public.categories (
  id bigserial primary key,
  slug text unique,
  name_fr text not null,
  name_ar text,
  icon text,
  parent_id bigint references public.categories(id),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Backfill/extend legacy schema if present.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'categories' and column_name = 'id'
  ) then
    execute 'alter table public.categories add column id bigserial';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'categories' and column_name = 'name_fr'
  ) then
    execute 'alter table public.categories add column name_fr text';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'categories' and column_name = 'slug'
  ) then
    execute 'alter table public.categories add column slug text';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'categories' and column_name = 'name_ar'
  ) then
    execute 'alter table public.categories add column name_ar text';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'categories' and column_name = 'icon'
  ) then
    execute 'alter table public.categories add column icon text';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'categories' and column_name = 'parent_id'
  ) then
    execute 'alter table public.categories add column parent_id bigint';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'categories' and column_name = 'sort_order'
  ) then
    execute 'alter table public.categories add column sort_order integer default 0';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'categories' and column_name = 'is_active'
  ) then
    execute 'alter table public.categories add column is_active boolean default true';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'categories' and column_name = 'name'
  ) then
    execute 'update public.categories set name_fr = coalesce(name_fr, name) where name_fr is null';
  end if;
end;
$$;

create unique index if not exists categories_id_key on public.categories(id);
create index if not exists categories_parent_id_idx on public.categories(parent_id);
create index if not exists categories_active_sort_idx on public.categories(is_active, sort_order);

alter table public.categories enable row level security;
drop policy if exists "categories read" on public.categories;
drop policy if exists "categories write service" on public.categories;
create policy "categories read" on public.categories for select using (true);
create policy "categories write service" on public.categories
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
drop trigger if exists categories_touch on public.categories;
create trigger categories_touch
  before update on public.categories
  for each row execute procedure public.touch_updated_at();

-- Locations ------------------------------------------------------------------
create table if not exists public.wilayas (
  code text primary key,
  name_fr text not null,
  name_ar text
);
create table if not exists public.communes (
  id bigserial primary key,
  wilaya_code text not null references public.wilayas(code) on delete cascade,
  name_fr text not null,
  name_ar text
);
create index if not exists communes_wilaya_code_idx on public.communes (wilaya_code);
create unique index if not exists communes_unique_idx
  on public.communes (wilaya_code, name_fr);

alter table public.wilayas enable row level security;
alter table public.communes enable row level security;
drop policy if exists "wilayas read" on public.wilayas;
drop policy if exists "wilayas write service" on public.wilayas;
drop policy if exists "communes read" on public.communes;
drop policy if exists "communes write service" on public.communes;
create policy "wilayas read" on public.wilayas for select using (true);
create policy "communes read" on public.communes for select using (true);
create policy "wilayas write service" on public.wilayas
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
create policy "communes write service" on public.communes
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

-- Seed Vinted-style categories (FR/AR) into public.categories (idempotent via slug)
-- Run in Supabase SQL Editor
create extension if not exists pgcrypto;

alter table public.categories add column if not exists name text;
alter table public.categories add column if not exists slug text;
alter table public.categories add column if not exists name_fr text;
alter table public.categories add column if not exists name_ar text;
alter table public.categories add column if not exists parent_id bigint;
alter table public.categories add column if not exists sort_order int default 0;
alter table public.categories add column if not exists is_active boolean default true;
alter table public.categories add column if not exists icon text;

create unique index if not exists categories_slug_key on public.categories(slug);

-- Ensure legacy NOT NULL name column is populated
update public.categories set name = coalesce(name, name_fr) where name is null;

-- TOP LEVEL
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('women','Femmes','Femmes','Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¡',null,10,true,'woman'),
('men','Hommes','Hommes','ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾',null,20,true,'man'),
('kids','Enfants','Enfants','ÃƒËœÃ‚Â£ÃƒËœÃ‚Â·Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾',null,30,true,'child_care'),
('home','Maison','Maison','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Å¾',null,40,true,'home'),
('beauty','BeautÃƒÆ’Ã‚Â© & SantÃƒÆ’Ã‚Â©','BeautÃƒÆ’Ã‚Â© & SantÃƒÆ’Ã‚Â©','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚ÂµÃƒËœÃ‚Â­ÃƒËœÃ‚Â©',null,50,true,'spa'),
('electronics','ÃƒÆ’Ã¢â‚¬Â°lectronique','ÃƒÆ’Ã¢â‚¬Â°lectronique','ÃƒËœÃ‚Â¥Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã†â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',null,60,true,'devices'),
('sports','Sport & Outdoor','Sport & Outdoor','ÃƒËœÃ‚Â±Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â© Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â®ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',null,70,true,'sports_soccer'),
('media','Livres & Divertissement','Livres & Divertissement','Ãƒâ„¢Ã†â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â¡',null,80,true,'menu_book'),
('toys','Jouets & Jeux','Jouets & Jeux','ÃƒËœÃ‚Â£Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨',null,90,true,'toys'),
('other','Autres','Autres','ÃƒËœÃ‚Â£ÃƒËœÃ‚Â®ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â°',null,100,true,'category')
on conflict (slug) do update set
  name=excluded.name,
  name_fr=excluded.name_fr,
  name_ar=excluded.name_ar,
  parent_id=excluded.parent_id,
  sort_order=excluded.sort_order,
  is_active=excluded.is_active,
  icon=excluded.icon;

-- WOMEN
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('women-clothing','VÃƒÆ’Ã‚Âªtements','VÃƒÆ’Ã‚Âªtements','Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â³',(select id from public.categories where slug='women'),1,true,'checkroom'),
('women-shoes','Chaussures','Chaussures','ÃƒËœÃ‚Â£ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',(select id from public.categories where slug='women'),2,true,'hiking'),
('women-bags','Sacs','Sacs','ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¦ÃƒËœÃ‚Â¨',(select id from public.categories where slug='women'),3,true,'work'),
('women-accessories','Accessoires','Accessoires','ÃƒËœÃ‚Â¥Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â³ÃƒËœÃ‚Â³Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='women'),4,true,'watch'),
('women-jewelry','Bijoux','Bijoux','Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¬Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='women'),5,true,'diamond'),
('women-lingerie','Lingerie','Lingerie','Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â®Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',(select id from public.categories where slug='women'),6,true,'local_mall')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- MEN
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('men-clothing','VÃƒÆ’Ã‚Âªtements','VÃƒÆ’Ã‚Âªtements','Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â³',(select id from public.categories where slug='men'),1,true,'checkroom'),
('men-shoes','Chaussures','Chaussures','ÃƒËœÃ‚Â£ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',(select id from public.categories where slug='men'),2,true,'hiking'),
('men-accessories','Accessoires','Accessoires','ÃƒËœÃ‚Â¥Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â³ÃƒËœÃ‚Â³Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='men'),3,true,'watch'),
('men-bags','Sacs','Sacs','ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¦ÃƒËœÃ‚Â¨',(select id from public.categories where slug='men'),4,true,'work'),
('men-watches','Montres','Montres','ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='men'),5,true,'watch')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- KIDS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('kids-baby','BÃƒÆ’Ã‚Â©bÃƒÆ’Ã‚Â© (0-24 mois)','BÃƒÆ’Ã‚Â©bÃƒÆ’Ã‚Â© (0-24 mois)','ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â¹',(select id from public.categories where slug='kids'),1,true,'child_friendly'),
('kids-clothing','VÃƒÆ’Ã‚Âªtements','VÃƒÆ’Ã‚Âªtements','Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â³',(select id from public.categories where slug='kids'),2,true,'checkroom'),
('kids-shoes','Chaussures','Chaussures','ÃƒËœÃ‚Â£ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',(select id from public.categories where slug='kids'),3,true,'hiking'),
('kids-accessories','Accessoires','Accessoires','ÃƒËœÃ‚Â¥Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â³ÃƒËœÃ‚Â³Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='kids'),4,true,'backpack'),
('kids-school','ÃƒÆ’Ã¢â‚¬Â°cole','ÃƒÆ’Ã¢â‚¬Â°cole','Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',(select id from public.categories where slug='kids'),5,true,'school')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- HOME
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('home-furniture','Meubles','Meubles','ÃƒËœÃ‚Â£ÃƒËœÃ‚Â«ÃƒËœÃ‚Â§ÃƒËœÃ‚Â«',(select id from public.categories where slug='home'),1,true,'weekend'),
('home-decor','DÃƒÆ’Ã‚Â©coration','DÃƒÆ’Ã‚Â©coration','ÃƒËœÃ‚Â¯Ãƒâ„¢Ã…Â Ãƒâ„¢Ã†â€™Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±',(select id from public.categories where slug='home'),2,true,'auto_awesome'),
('home-kitchen','Cuisine','Cuisine','Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â·ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â®',(select id from public.categories where slug='home'),3,true,'kitchen'),
('home-textiles','Textiles','Textiles','Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='home'),4,true,'curtains'),
('home-appliances','ÃƒÆ’Ã¢â‚¬Â°lectromÃƒÆ’Ã‚Â©nager','ÃƒÆ’Ã¢â‚¬Â°lectromÃƒÆ’Ã‚Â©nager','ÃƒËœÃ‚Â£ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â²ÃƒËœÃ‚Â© Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',(select id from public.categories where slug='home'),5,true,'microwave')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- BEAUTY
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('beauty-makeup','Maquillage','Maquillage','Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã†â€™Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¬',(select id from public.categories where slug='beauty'),1,true,'brush'),
('beauty-skincare','Soins de la peau','Soins de la peau','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â§Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â© ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â´ÃƒËœÃ‚Â±ÃƒËœÃ‚Â©',(select id from public.categories where slug='beauty'),2,true,'face'),
('beauty-hair','Cheveux','Cheveux','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â±',(select id from public.categories where slug='beauty'),3,true,'content_cut'),
('beauty-fragrance','Parfums','Parfums','ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â·Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±',(select id from public.categories where slug='beauty'),4,true,'local_florist'),
('beauty-wellness','BienÃƒÆ’Ã‚Âªtre','BienÃƒÆ’Ã‚Âªtre','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â§Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â© Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚ÂµÃƒËœÃ‚Â­ÃƒËœÃ‚Â©',(select id from public.categories where slug='beauty'),5,true,'favorite')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- ELECTRONICS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('electronics-phones','TÃƒÆ’Ã‚Â©lÃƒÆ’Ã‚Â©phones','TÃƒÆ’Ã‚Â©lÃƒÆ’Ã‚Â©phones','Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚Â',(select id from public.categories where slug='electronics'),1,true,'smartphone'),
('electronics-computers','Ordinateurs','Ordinateurs','ÃƒËœÃ‚Â­Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¨',(select id from public.categories where slug='electronics'),2,true,'laptop'),
('electronics-tablets','Tablettes','Tablettes','ÃƒËœÃ‚Â£ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â²ÃƒËœÃ‚Â© Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â­Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',(select id from public.categories where slug='electronics'),3,true,'tablet'),
('electronics-audio','Audio','Audio','ÃƒËœÃ‚ÂµÃƒâ„¢Ã‹â€ ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='electronics'),4,true,'headphones'),
('electronics-gaming','Gaming','Gaming','ÃƒËœÃ‚Â£Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨',(select id from public.categories where slug='electronics'),5,true,'sports_esports'),
('electronics-accessories','Accessoires','Accessoires','ÃƒËœÃ‚Â¥Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â³ÃƒËœÃ‚Â³Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='electronics'),6,true,'cable')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- SPORTS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('sports-clothing','VÃƒÆ’Ã‚Âªtements de sport','VÃƒÆ’Ã‚Âªtements de sport','Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â±Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',(select id from public.categories where slug='sports'),1,true,'sports'),
('sports-shoes','Chaussures de sport','Chaussures de sport','ÃƒËœÃ‚Â£ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â© ÃƒËœÃ‚Â±Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',(select id from public.categories where slug='sports'),2,true,'hiking'),
('sports-equipment','ÃƒÆ’Ã¢â‚¬Â°quipement','ÃƒÆ’Ã¢â‚¬Â°quipement','Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='sports'),3,true,'fitness_center'),
('sports-bikes','VÃƒÆ’Ã‚Â©los','VÃƒÆ’Ã‚Â©los','ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='sports'),4,true,'pedal_bike'),
('sports-outdoor','Camping & Outdoor','Camping & Outdoor','ÃƒËœÃ‚ÂªÃƒËœÃ‚Â®Ãƒâ„¢Ã…Â Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â®ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',(select id from public.categories where slug='sports'),5,true,'terrain')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- MEDIA
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('media-books','Livres','Livres','Ãƒâ„¢Ã†â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨',(select id from public.categories where slug='media'),1,true,'menu_book'),
('media-movies','Films & SÃƒÆ’Ã‚Â©ries','Films & SÃƒÆ’Ã‚Â©ries','ÃƒËœÃ‚Â£Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='media'),2,true,'movie'),
('media-music','Musique','Musique','Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Â°',(select id from public.categories where slug='media'),3,true,'music_note'),
('media-games','Jeux vidÃƒÆ’Ã‚Â©o','Jeux vidÃƒÆ’Ã‚Â©o','ÃƒËœÃ‚Â£Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã…Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã…Â Ãƒâ„¢Ã‹â€ ',(select id from public.categories where slug='media'),4,true,'sports_esports')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- TOYS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('toys-figures','Figurines','Figurines','Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='toys'),1,true,'smart_toy'),
('toys-boardgames','Jeux de sociÃƒÆ’Ã‚Â©tÃƒÆ’Ã‚Â©','Jeux de sociÃƒÆ’Ã‚Â©tÃƒÆ’Ã‚Â©','ÃƒËœÃ‚Â£Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©',(select id from public.categories where slug='toys'),2,true,'casino'),
('toys-construction','Construction','Construction','ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã†â€™Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¨ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¡',(select id from public.categories where slug='toys'),3,true,'construction'),
('toys-baby','Jouets bÃƒÆ’Ã‚Â©bÃƒÆ’Ã‚Â©','Jouets bÃƒÆ’Ã‚Â©bÃƒÆ’Ã‚Â©','ÃƒËœÃ‚Â£Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â¹',(select id from public.categories where slug='toys'),4,true,'child_friendly')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- OTHER
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('other-services','Services','Services','ÃƒËœÃ‚Â®ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='other'),1,true,'support_agent'),
('other-collectibles','Collections','Collections','Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª',(select id from public.categories where slug='other'),2,true,'collections'),
('other-misc','Divers','Divers','Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¹',(select id from public.categories where slug='other'),3,true,'more_horiz')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- Quick check
-- select slug, name_fr, parent_id from public.categories order by parent_id nulls first, sort_order;

-- Seed wilayas (FR/AR)
insert into public.wilayas (code, name_fr, name_ar) values
('01','Adrar','ÃƒËœÃ‚Â£ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±'),
('02','Chlef','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‚Â'),
('03','Laghouat','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â£ÃƒËœÃ‚ÂºÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â·'),
('04','Oum El Bouaghi','ÃƒËœÃ‚Â£Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã…Â '),
('05','Batna','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â©'),
('06','Bejaia','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©'),
('07','Biskra','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â³Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â±ÃƒËœÃ‚Â©'),
('08','Bechar','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â´ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±'),
('09','Blida','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â©'),
('10','Bouira','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â±ÃƒËœÃ‚Â©'),
('11','Tamanrasset','ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª'),
('12','Tebessa','ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â³ÃƒËœÃ‚Â©'),
('13','Tlemcen','ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â '),
('14','Tiaret','ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª'),
('15','Tizi Ouzou','ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â ÃƒËœÃ‚Â²Ãƒâ„¢Ã…Â  Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã‹â€ '),
('16','Alger','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¦ÃƒËœÃ‚Â±'),
('17','Djelfa','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â©'),
('18','Jijel','ÃƒËœÃ‚Â¬Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Å¾'),
('19','Setif','ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·Ãƒâ„¢Ã…Â Ãƒâ„¢Ã‚Â'),
('20','Saida','ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¹Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â©'),
('21','Skikda','ÃƒËœÃ‚Â³Ãƒâ„¢Ã†â€™Ãƒâ„¢Ã…Â Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â©'),
('22','Sidi Bel Abbes','ÃƒËœÃ‚Â³Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã…Â  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³'),
('23','Annaba','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â©'),
('24','Guelma','Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â©'),
('25','Constantine','Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â·Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â©'),
('26','Medea','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¯Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©'),
('27','Mostaganem','Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚ÂºÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¦'),
('28','M''Sila','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â³Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'),
('29','Mascara','Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â³Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â±'),
('30','Ouargla','Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'),
('31','Oran','Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â '),
('32','El Bayadh','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¶'),
('33','Illizi','ÃƒËœÃ‚Â¥Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â²Ãƒâ„¢Ã…Â '),
('34','Bordj Bou Arreridj','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â±Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â±Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¬'),
('35','Boumerdes','ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³'),
('36','El Tarf','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â·ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã‚Â'),
('37','Tindouf','ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã‚Â'),
('38','Tissemsilt','ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â³Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Âª'),
('39','El Oued','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã…Â '),
('40','Khenchela','ÃƒËœÃ‚Â®Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'),
('41','Souk Ahras','ÃƒËœÃ‚Â³Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¡ ÃƒËœÃ‚Â£Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³'),
('42','Tipaza','ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²ÃƒËœÃ‚Â©'),
('43','Mila','Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'),
('44','Ain Defla','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â°'),
('45','Naama','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â©'),
('46','Ain Temouchent','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Âª'),
('47','Ghardaia','ÃƒËœÃ‚ÂºÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©'),
('48','Relizane','ÃƒËœÃ‚ÂºÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â '),
('49','El M''Ghair','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂºÃƒâ„¢Ã…Â ÃƒËœÃ‚Â±'),
('50','El Meniaa','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â©'),
('51','Ouled Djellal','ÃƒËœÃ‚Â£Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾'),
('52','Bordj Baji Mokhtar','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¬Ãƒâ„¢Ã…Â  Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â®ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â±'),
('53','Beni Abbes','ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã…Â  ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³'),
('54','Timimoun','ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â '),
('55','Touggourt','ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª'),
('56','Djanet','ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Âª'),
('57','In Salah','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚ÂµÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â­'),
('58','In Guezzam','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦')
on conflict (code) do update set
  name_fr = excluded.name_fr,
  name_ar = excluded.name_ar;
-- Seed communes (minimal placeholder list; replace with full dataset when available)
insert into public.communes (wilaya_code, name_fr, name_ar) values
('01','Adrar','ÃƒËœÃ‚Â£ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±'),
('02','Chlef','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‚Â'),
('03','Laghouat','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â£ÃƒËœÃ‚ÂºÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â·'),
('04','Oum El Bouaghi','ÃƒËœÃ‚Â£Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã…Â '),
('05','Batna','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â©'),
('06','Bejaia','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©'),
('07','Biskra','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â³Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â±ÃƒËœÃ‚Â©'),
('08','Bechar','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â´ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±'),
('09','Blida','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â©'),
('10','Bouira','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â±ÃƒËœÃ‚Â©'),
('11','Tamanrasset','ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª'),
('12','Tebessa','ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â³ÃƒËœÃ‚Â©'),
('13','Tlemcen','ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â '),
('14','Tiaret','ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª'),
('15','Tizi Ouzou','ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â ÃƒËœÃ‚Â²Ãƒâ„¢Ã…Â  Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã‹â€ '),
('16','Alger Centre','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¦ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Â°'),
('17','Djelfa','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â©'),
('18','Jijel','ÃƒËœÃ‚Â¬Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Å¾'),
('19','Setif','ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·Ãƒâ„¢Ã…Â Ãƒâ„¢Ã‚Â'),
('20','Saida','ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¹Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â©'),
('21','Skikda','ÃƒËœÃ‚Â³Ãƒâ„¢Ã†â€™Ãƒâ„¢Ã…Â Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â©'),
('22','Sidi Bel Abbes','ÃƒËœÃ‚Â³Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã…Â  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³'),
('23','Annaba','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â©'),
('24','Guelma','Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â©'),
('25','Constantine','Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â·Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â©'),
('26','Medea','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¯Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©'),
('27','Mostaganem','Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚ÂºÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¦'),
('28','M''Sila','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â³Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'),
('29','Mascara','Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â³Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â±'),
('30','Ouargla','Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'),
('31','Oran','Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â '),
('32','El Bayadh','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¶'),
('33','Illizi','ÃƒËœÃ‚Â¥Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â²Ãƒâ„¢Ã…Â '),
('34','Bordj Bou Arreridj','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â±Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â±Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¬'),
('35','Boumerdes','ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³'),
('36','El Tarf','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â·ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã‚Â'),
('37','Tindouf','ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã‚Â'),
('38','Tissemsilt','ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â³Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Âª'),
('39','El Oued','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã…Â '),
('40','Khenchela','ÃƒËœÃ‚Â®Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'),
('41','Souk Ahras','ÃƒËœÃ‚Â³Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¡ ÃƒËœÃ‚Â£Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³'),
('42','Tipaza','ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²ÃƒËœÃ‚Â©'),
('43','Mila','Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'),
('44','Ain Defla','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â°'),
('45','Naama','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â©'),
('46','Ain Temouchent','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Âª'),
('47','Ghardaia','ÃƒËœÃ‚ÂºÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â©'),
('48','Relizane','ÃƒËœÃ‚ÂºÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â '),
('49','El M''Ghair','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂºÃƒâ„¢Ã…Â ÃƒËœÃ‚Â±'),
('50','El Meniaa','ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â©'),
('51','Ouled Djellal','ÃƒËœÃ‚Â£Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾'),
('52','Bordj Baji Mokhtar','ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¬Ãƒâ„¢Ã…Â  Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â®ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â±'),
('53','Beni Abbes','ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã…Â  ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³'),
('54','Timimoun','ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â '),
('55','Touggourt','ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª'),
('56','Djanet','ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Âª'),
('57','In Salah','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚ÂµÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â­'),
('58','In Guezzam','ÃƒËœÃ‚Â¹Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦')
on conflict (wilaya_code, name_fr) do update set
  name_ar = excluded.name_ar;
-- Products -------------------------------------------------------------------
create table if not exists public.products (
    id bigserial primary key,
    title text not null,
    description text,
    price numeric(12,2) not null check (price >= 0),
    cost_price numeric(12,2) check (cost_price >= 0),
    image_url text,
    image_urls text[] not null default '{}',
    location_wilaya text,
    location_daira text,
    delivery_options text[] not null default '{}',
    category_id bigint references public.categories(id),
    category_slug text references public.categories(slug),
    condition text,
    brand text,
    size text,
    color text,
    status text not null default 'active' check (status in ('active','paused','sold')),
    stock_quantity int not null default 1 check (stock_quantity >= 0),
    sold_count int not null default 0 check (sold_count >= 0),
    is_archived boolean not null default false,
    owner_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
  );
  alter table public.products
    add column if not exists status text default 'active';
  alter table public.products
    add column if not exists cost_price numeric(12,2);
  alter table public.products
    add column if not exists stock_quantity int default 1;
  alter table public.products
    add column if not exists sold_count int default 0;
  alter table public.products
    add column if not exists is_archived boolean default false;
alter table public.products
  add column if not exists category_id bigint references public.categories(id);
alter table public.products
  add column if not exists location_wilaya text;
alter table public.products
  add column if not exists location_daira text;
alter table public.products
  add column if not exists delivery_options text[] default '{}';
alter table public.products enable row level security;
drop policy if exists "products readable by all" on public.products;
drop policy if exists "products insert by seller" on public.products;
drop policy if exists "products update by owner" on public.products;
create policy "products readable by all" on public.products for select using (true);
create policy "products insert by seller" on public.products
  for insert with check (auth.uid() = owner_id);
create policy "products update by owner" on public.products
  for update using (auth.uid() = owner_id);
drop trigger if exists products_touch on public.products;
create trigger products_touch
  before update on public.products
  for each row execute procedure public.touch_updated_at();

create index if not exists products_owner_idx on public.products (owner_id);
create index if not exists products_category_slug_idx on public.products (category_slug);
create index if not exists products_category_id_idx on public.products (category_id);
create index if not exists products_status_created_idx on public.products (status, created_at desc);

-- Favorites ------------------------------------------------------------------
create table if not exists public.favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  product_id bigint not null references public.products(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, product_id)
);
alter table public.favorites enable row level security;
drop policy if exists "favorites select own" on public.favorites;
drop policy if exists "favorites upsert own" on public.favorites;
drop policy if exists "favorites delete own" on public.favorites;
create policy "favorites select own" on public.favorites for select using (auth.uid() = user_id);
create policy "favorites upsert own" on public.favorites
  for insert with check (auth.uid() = user_id);
create policy "favorites delete own" on public.favorites
  for delete using (auth.uid() = user_id);
create index if not exists favorites_user_created_idx on public.favorites (user_id, created_at desc);

-- Addresses ------------------------------------------------------------------
create table if not exists public.addresses (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  label text,
  full_name text,
  phone text,
  line1 text not null,
  line2 text,
  city text,
  state text,
  postal_code text,
  country text default 'DZ',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.addresses enable row level security;
drop policy if exists "addresses select own" on public.addresses;
drop policy if exists "addresses insert own" on public.addresses;
drop policy if exists "addresses update own" on public.addresses;
drop policy if exists "addresses delete own" on public.addresses;
create policy "addresses select own" on public.addresses
  for select using (auth.uid() = user_id);
create policy "addresses insert own" on public.addresses
  for insert with check (auth.uid() = user_id);
create policy "addresses update own" on public.addresses
  for update using (auth.uid() = user_id);
create policy "addresses delete own" on public.addresses
  for delete using (auth.uid() = user_id);
drop trigger if exists addresses_touch on public.addresses;
create trigger addresses_touch
  before update on public.addresses
  for each row execute procedure public.touch_updated_at();

-- Courier credentials + seller delivery settings -----------------------------
create table if not exists public.courier_credentials (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.profiles(id) on delete cascade,
  courier_id text not null references public.couriers(code) on delete cascade,
  api_key text,
  api_secret text,
  sender_id text,
  settings jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (owner_id, courier_id)
);
alter table public.courier_credentials enable row level security;
drop policy if exists "courier creds select own" on public.courier_credentials;
drop policy if exists "courier creds upsert own" on public.courier_credentials;
drop policy if exists "courier creds delete own" on public.courier_credentials;
create policy "courier creds select own" on public.courier_credentials
  for select using (auth.uid() = owner_id);
create policy "courier creds upsert own" on public.courier_credentials
  for insert with check (auth.uid() = owner_id);
create policy "courier creds delete own" on public.courier_credentials
  for delete using (auth.uid() = owner_id);
drop trigger if exists courier_credentials_touch on public.courier_credentials;
create trigger courier_credentials_touch
  before update on public.courier_credentials
  for each row execute procedure public.touch_updated_at();

do $$
declare
  r record;
begin
  -- Drop any existing FKs on courier_id before type changes
  for r in (
    select conname from pg_constraint
    where conrelid = 'public.courier_credentials'::regclass
      and contype = 'f'
  ) loop
    execute format('alter table public.courier_credentials drop constraint %I', r.conname);
  end loop;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'courier_credentials'
      and column_name = 'courier'
  )
  and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'courier_credentials'
      and column_name = 'courier_id'
  ) then
    execute 'alter table public.courier_credentials rename column courier to courier_id';
  end if;
  -- force courier_id to text for FK to couriers.code
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'courier_credentials'
      and column_name = 'courier_id'
      and data_type <> 'text'
  ) then
    execute 'alter table public.courier_credentials alter column courier_id type text using courier_id::text';
  end if;
  -- If old data used UUIDs, null them to avoid FK failures (manual backfill later)
  execute 'update public.courier_credentials set courier_id = null where courier_id !~ ''^[a-z0-9\\-]+$''';
end;
$$;
alter table public.courier_credentials drop constraint if exists courier_credentials_courier_id_fkey;
alter table public.courier_credentials
  add constraint courier_credentials_courier_id_fkey
  foreign key (courier_id) references public.couriers(code) on delete cascade;

create table if not exists public.seller_delivery_settings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  courier_id text not null references public.couriers(code) on delete cascade,
  api_key text,
  api_secret text,
  sender_id text,
  extra jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (owner_id, courier_id)
);
alter table public.seller_delivery_settings enable row level security;
drop policy if exists "seller delivery select own" on public.seller_delivery_settings;
drop policy if exists "seller delivery upsert own" on public.seller_delivery_settings;
drop policy if exists "seller delivery update own" on public.seller_delivery_settings;
drop policy if exists "seller delivery delete own" on public.seller_delivery_settings;
create policy "seller delivery select own" on public.seller_delivery_settings
  for select using (auth.uid() = owner_id);
create policy "seller delivery upsert own" on public.seller_delivery_settings
  for insert with check (auth.uid() = owner_id);
create policy "seller delivery update own" on public.seller_delivery_settings
  for update using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "seller delivery delete own" on public.seller_delivery_settings
  for delete using (auth.uid() = owner_id);
drop trigger if exists seller_delivery_touch on public.seller_delivery_settings;
create trigger seller_delivery_touch
  before update on public.seller_delivery_settings
  for each row execute procedure public.touch_updated_at();

alter table public.seller_delivery_settings
  alter column courier_id type text using courier_id::text;
alter table public.seller_delivery_settings drop constraint if exists seller_delivery_settings_courier_id_fkey;
alter table public.seller_delivery_settings
  add constraint seller_delivery_settings_courier_id_fkey
  foreign key (courier_id) references public.couriers(code) on delete cascade;

-- Helper to expose enabled couriers for a seller (security definer to bypass RLS for buyers)
create or replace function public.get_enabled_couriers_for_seller(seller_id uuid)
returns table (courier_id text, courier_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select s.courier_id, coalesce(c.name, s.courier_id) as courier_name
  from public.seller_delivery_settings s
  left join public.couriers c on c.code = s.courier_id
  where s.owner_id = seller_id
    and s.api_key is not null
    and (
      s.courier_id = 'ecotrack'
      or s.api_secret is not null
    );
end;
$$;
revoke all on function public.get_enabled_couriers_for_seller(uuid) from public;
grant execute on function public.get_enabled_couriers_for_seller(uuid) to authenticated, anon;

-- Fetch seller delivery settings (security definer to bypass RLS for buyers)
create or replace function public.get_seller_delivery_settings(p_owner uuid, p_courier_id text)
returns table (courier_id text, owner_id uuid, api_key text, api_secret text, sender_id text, extra jsonb)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is distinct from p_owner then
    return;
  end if;
  return query
  select courier_id, owner_id, api_key, api_secret, sender_id, extra
  from public.seller_delivery_settings
  where owner_id = p_owner
    and courier_id = p_courier_id
    and api_key is not null
    and (
      p_courier_id = 'ecotrack'
      or api_secret is not null
    );
end;
$$;
revoke all on function public.get_seller_delivery_settings(uuid, text) from public;
grant execute on function public.get_seller_delivery_settings(uuid, text) to authenticated;

-- Orders ---------------------------------------------------------------------
create table if not exists public.orders (
    id bigserial primary key,
    product_id bigint not null references public.products(id) on delete cascade,
    buyer_id uuid not null references public.profiles(id) on delete cascade,
    seller_id uuid not null references public.profiles(id) on delete cascade,
    driver_id uuid references public.profiles(id) on delete set null,
    status text not null default 'pending' check (status in ('pending','paid','shipped','delivered','cancelled')),
    shipping_address_id bigint references public.addresses(id) on delete set null,
    shipping_option text,
    shipping_cost numeric(12,2),
    payment_method text not null default 'cod' check (payment_method in ('cod','online')),
    payment_status text not null default 'pending' check (payment_status in ('pending','paid','failed')),
    delivery_method text,
    tracking_number text,
    label_url text,
    courier_id text references public.couriers(code) on delete set null,
    courier_name text,
    agreed_price numeric(12,2),
    sale_price numeric(12,2),
    cost_price numeric(12,2),
    fee_amount numeric(12,2) default 0,
    delivery_cost numeric(12,2) default 0,
    stock_applied boolean not null default false,
    shipping_selection jsonb,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
  );

-- Compatibility with existing databases
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'orders'
      and column_name = 'user_id'
  ) then
    execute 'alter table public.orders rename column user_id to buyer_id';
  end if;
end;
$$;
  alter table public.orders
    add column if not exists buyer_id uuid references public.profiles(id) on delete cascade,
    add column if not exists seller_id uuid references public.profiles(id) on delete cascade,
    add column if not exists shipping_cost numeric(12,2),
    add column if not exists status text default 'pending',
    add column if not exists label_url text,
    add column if not exists sale_price numeric(12,2),
    add column if not exists cost_price numeric(12,2),
    add column if not exists fee_amount numeric(12,2) default 0,
    add column if not exists delivery_cost numeric(12,2) default 0,
    add column if not exists stock_applied boolean default false;
alter table public.orders
  add column if not exists shipping_selection jsonb;
-- ensure status constraint if missing
do $$
begin
  if not exists (
    select 1 from information_schema.constraint_column_usage
    where table_schema = 'public' and table_name = 'orders' and column_name = 'status'
  ) then
    alter table public.orders
      add constraint orders_status_check check (status in ('pending','paid','shipped','delivered','cancelled'));
  end if;
end;
$$;
drop policy if exists "orders update buyer driver limited" on public.orders;
drop policy if exists "orders update seller service" on public.orders;
drop policy if exists "orders update buyer driver seller" on public.orders;
alter table public.orders
  alter column courier_id type text using courier_id::text;
alter table public.orders drop constraint if exists orders_courier_id_fkey;
alter table public.orders
  add constraint orders_courier_id_fkey foreign key (courier_id) references public.couriers(code) on delete set null;
alter table public.orders
  add column if not exists shipping_address_id bigint references public.addresses(id) on delete set null;
alter table public.orders
  add column if not exists shipping_option text;
alter table public.orders
  add column if not exists payment_method text;
alter table public.orders
  add column if not exists payment_status text;
update public.orders
  set seller_id = (
    select owner_id from public.products p where p.id = public.orders.product_id
  )
  where seller_id is null;

create or replace function public.set_order_seller()
returns trigger as $$
declare
  owner uuid;
begin
  if new.seller_id is null then
    select owner_id into owner from public.products where id = new.product_id;
    if owner is not null then
      new.seller_id = owner;
    end if;
  end if;
  return new;
end;
$$ language plpgsql;

-- Atomic order creation with stock reservation (RPC used by client app)
-- Stub for post_order_event (overwritten later after chat schema is defined)
create or replace function public.post_order_event(
  p_order_id bigint,
  p_event text,
  p_payload jsonb,
  p_dedupe_key text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- no-op placeholder to satisfy create_order dependencies during first run
  return;
end;
$$;

drop function if exists public.create_order(bigint, bigint, text, text, text, numeric, text, text, numeric, numeric);
create or replace function public.create_order(
  p_product_id bigint,
  p_shipping_address_id bigint,
  p_payment_method text,
  p_shipping_option text,
  p_delivery_method text,
  p_agreed_price numeric,
  p_courier_id text,
  p_courier_name text,
  p_shipping_cost numeric,
  p_fee_amount numeric,
  p_shipping_selection jsonb default null
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer uuid := auth.uid();
  v_seller uuid;
  v_price numeric;
  v_cost numeric;
  v_stock int;
  v_order_id bigint;
begin
  if v_buyer is null then
    raise exception 'auth required';
  end if;

  select owner_id, price, cost_price, stock_quantity
  into v_seller, v_price, v_cost, v_stock
  from public.products
  where id = p_product_id
  for update;

  if v_seller is null then
    raise exception 'product not found';
  end if;
  if v_seller = v_buyer then
    raise exception 'cannot buy own product';
  end if;
  if v_stock is null or v_stock <= 0 then
    raise exception 'out of stock';
  end if;

  insert into public.orders (
    product_id,
    buyer_id,
    seller_id,
    shipping_address_id,
    shipping_option,
    shipping_cost,
    payment_method,
    payment_status,
    delivery_method,
    agreed_price,
    courier_id,
    courier_name,
    sale_price,
    cost_price,
    fee_amount,
    delivery_cost,
    shipping_selection,
    status
  ) values (
    p_product_id,
    v_buyer,
    v_seller,
    p_shipping_address_id,
    p_shipping_option,
    p_shipping_cost,
    coalesce(p_payment_method, 'cod'),
    case when coalesce(p_payment_method, 'cod') = 'cod' then 'pending' else 'paid' end,
    p_delivery_method,
    p_agreed_price,
    p_courier_id,
    p_courier_name,
    coalesce(p_agreed_price, v_price),
    v_cost,
    coalesce(p_fee_amount, 0),
    coalesce(p_shipping_cost, 0),
    p_shipping_selection,
    'pending'
  ) returning id into v_order_id;

  update public.products
  set stock_quantity = stock_quantity - 1
  where id = p_product_id;

    begin
      perform public.post_order_event(
        v_order_id,
        'order_created',
        jsonb_build_object(
          'i18n_key', 'order.system.created',
          'status', 'pending',
          'status_i18n', 'order.status.pending'
        ),
        'order:' || v_order_id || ':created'
      );
    exception when others then
      -- Do not block order creation if chat/event pipeline fails.
      null;
    end;

  return v_order_id;
end;
$$;
revoke all on function public.create_order(bigint, bigint, text, text, text, numeric, text, text, numeric, numeric, jsonb) from public;
grant execute on function public.create_order(bigint, bigint, text, text, text, numeric, text, text, numeric, numeric, jsonb) to authenticated;

alter table public.orders enable row level security;
drop policy if exists "orders select buyer driver seller" on public.orders;
drop policy if exists "orders insert buyer" on public.orders;
drop policy if exists "orders update buyer driver seller" on public.orders;
create policy "orders select buyer driver seller" on public.orders
  for select using (
    auth.uid() = buyer_id
    or auth.uid() = driver_id
    or auth.uid() = seller_id
  );
create policy "orders insert buyer" on public.orders
  for insert with check (auth.uid() = buyer_id);
create policy "orders update seller service" on public.orders
  for update using (
    auth.uid() = seller_id
    or auth.role() = 'service_role'
  )
  with check (
    auth.uid() = seller_id
    or auth.role() = 'service_role'
  );
create policy "orders update buyer driver limited" on public.orders
  for update using (
    auth.uid() = buyer_id
    or auth.uid() = driver_id
  )
  with check (
    tracking_number is not distinct from (
      select o.tracking_number from public.orders o where o.id = orders.id
    )
    and label_url is not distinct from (
      select o.label_url from public.orders o where o.id = orders.id
    )
    and courier_id is not distinct from (
      select o.courier_id from public.orders o where o.id = orders.id
    )
    and courier_name is not distinct from (
      select o.courier_name from public.orders o where o.id = orders.id
    )
    and delivery_method is not distinct from (
      select o.delivery_method from public.orders o where o.id = orders.id
    )
    and shipping_cost is not distinct from (
      select o.shipping_cost from public.orders o where o.id = orders.id
    )
    and delivery_cost is not distinct from (
      select o.delivery_cost from public.orders o where o.id = orders.id
    )
  );

drop trigger if exists orders_touch on public.orders;
drop trigger if exists orders_set_seller on public.orders;
create trigger orders_touch
  before update on public.orders
  for each row execute procedure public.touch_updated_at();
create trigger orders_set_seller
  before insert on public.orders
  for each row execute procedure public.set_order_seller();

create or replace function public.apply_order_delivery()
  returns trigger as $$
  begin
    if new.status = 'delivered'
      and old.status is distinct from 'delivered'
      and coalesce(new.stock_applied, false) = false then
      update public.products
      set stock_quantity = greatest(stock_quantity - 1, 0),
          sold_count = sold_count + 1
      where id = new.product_id;
      new.stock_applied = true;
    end if;
    return new;
  end;
$$ language plpgsql;

drop trigger if exists orders_apply_delivery on public.orders;
create trigger orders_apply_delivery
  before update on public.orders
  for each row execute procedure public.apply_order_delivery();

create index if not exists orders_buyer_idx on public.orders (buyer_id, created_at desc);
create index if not exists orders_seller_idx on public.orders (seller_id, created_at desc);
create index if not exists orders_driver_idx on public.orders (driver_id, created_at desc);
create index if not exists orders_status_idx on public.orders (status, created_at desc);

-- Shipments ------------------------------------------------------------------
create table if not exists public.shipments (
  order_id bigint primary key references public.orders(id) on delete cascade,
  tracking_number text,
  label_url text,
  status text default 'pending',
  carrier text,
  option text,
  delivery_mode text,
  shipping_cost numeric(12,2),
  courier_id text references public.couriers(code) on delete set null,
  courier_account_id uuid references public.courier_credentials(id) on delete set null,
  events jsonb default '[]',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.shipments enable row level security;
drop policy if exists "shipments select buyer seller" on public.shipments;
drop policy if exists "shipments insert" on public.shipments;
drop policy if exists "shipments update" on public.shipments;
drop policy if exists "shipments insert seller service" on public.shipments;
drop policy if exists "shipments update seller service" on public.shipments;
create policy "shipments select buyer seller" on public.shipments
  for select using (
    auth.uid() = (select buyer_id from public.orders where id = order_id)
    or auth.uid() = (select seller_id from public.orders where id = order_id)
    or auth.uid() = (select driver_id from public.orders where id = order_id)
  );
create policy "shipments insert seller service" on public.shipments
  for insert with check (
    auth.uid() = (select seller_id from public.orders where id = order_id)
    or auth.role() = 'service_role'
  );
create policy "shipments update seller service" on public.shipments
  for update using (
    auth.uid() = (select seller_id from public.orders where id = order_id)
    or auth.role() = 'service_role'
  );
drop trigger if exists shipments_touch on public.shipments;
create trigger shipments_touch
  before update on public.shipments
  for each row execute procedure public.touch_updated_at();
create index if not exists shipments_status_idx on public.shipments (status, created_at desc);
alter table public.shipments
  alter column courier_id type text using courier_id::text;
alter table public.shipments drop constraint if exists shipments_courier_id_fkey;
alter table public.shipments
  add constraint shipments_courier_id_fkey foreign key (courier_id) references public.couriers(code) on delete set null;
alter table public.shipments
  add column if not exists courier_account_id uuid;
alter table public.shipments drop constraint if exists shipments_courier_account_id_fkey;
alter table public.shipments
  add constraint shipments_courier_account_id_fkey
  foreign key (courier_account_id) references public.courier_credentials(id) on delete set null;
alter table public.shipments
  add column if not exists status text default 'pending';

-- Chat v2 (conversations/messages/reads) -------------------------------------
-- Cleanup legacy chat artifacts
DROP FUNCTION IF EXISTS public.update_chat_room_last_message() CASCADE;
DROP FUNCTION IF EXISTS public.mark_chat_room_read(text) CASCADE;
DROP FUNCTION IF EXISTS public.hide_chat_room(text) CASCADE;
DROP TRIGGER IF EXISTS messages_chat_rooms_touch ON public.messages;
DROP VIEW IF EXISTS public.chat_rooms_visible;
DROP TABLE IF EXISTS public.chat_room_users CASCADE;
DROP TABLE IF EXISTS public.chat_rooms CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.conversations CASCADE;
DROP TABLE IF EXISTS public.reads CASCADE;

-- Conversations table (per buyer/seller, optional product)
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  seller_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  product_id bigint REFERENCES public.products(id) ON DELETE SET NULL,
  order_id bigint REFERENCES public.orders(id) ON DELETE SET NULL,
  last_message_at timestamptz DEFAULT now(),
  last_message_text text,
  buyer_hidden_at timestamptz,
  seller_hidden_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS order_id bigint REFERENCES public.orders(id) ON DELETE SET NULL;
  DROP INDEX IF EXISTS conv_product_buyer_seller_uniq;
  CREATE UNIQUE INDEX IF NOT EXISTS conv_product_buyer_seller_uniq
    ON public.conversations(product_id, buyer_id, seller_id)
    WHERE product_id IS NOT NULL AND order_id IS NULL;
  DROP INDEX IF EXISTS conv_order_uniq;
  CREATE UNIQUE INDEX IF NOT EXISTS conv_order_uniq
    ON public.conversations(order_id);
CREATE INDEX IF NOT EXISTS conv_participants_last_msg_idx
  ON public.conversations(buyer_id, seller_id, last_message_at DESC);

-- Messages table (one-to-many)
CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  text text NOT NULL,
  type text default 'text',
  payload jsonb,
  dedupe_key text,
  created_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS type text default 'text',
  ADD COLUMN IF NOT EXISTS payload jsonb,
  ADD COLUMN IF NOT EXISTS dedupe_key text;
DROP INDEX IF EXISTS public.messages_dedupe_uniq;
CREATE UNIQUE INDEX IF NOT EXISTS messages_dedupe_uniq
  ON public.messages(conversation_id, dedupe_key);

-- Keep conversation ordering stable on any message insert (fallback safety).
CREATE OR REPLACE FUNCTION public.update_conversation_last_message()
RETURNS trigger AS $$
BEGIN
  UPDATE public.conversations
  SET last_message_at = NEW.created_at,
      last_message_text = NEW.text,
      updated_at = now()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS messages_update_conversation ON public.messages;
CREATE TRIGGER messages_update_conversation
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE PROCEDURE public.update_conversation_last_message();

-- Read states
CREATE TABLE IF NOT EXISTS public.reads (
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_read_at timestamptz,
  last_read_message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  PRIMARY KEY (conversation_id, user_id)
);

-- Helpers
CREATE OR REPLACE FUNCTION public.is_participant(p_conv uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = p_conv AND auth.uid() IN (c.buyer_id, c.seller_id)
  );
$$;

  -- RPC: ensure_conversation (idempotent create by product/buyer/seller)
  CREATE OR REPLACE FUNCTION public.ensure_conversation(p_product_id bigint,
                                                       p_buyer_id uuid,
                                                       p_seller_id uuid)
  RETURNS public.conversations
  LANGUAGE plpgsql SECURITY DEFINER AS $$
  DECLARE
    conv public.conversations;
  BEGIN
    IF auth.uid() NOT IN (p_buyer_id, p_seller_id) THEN
      RAISE EXCEPTION 'Forbidden' USING errcode = '42501';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('conv:' || p_product_id::text || ':' || p_buyer_id::text || ':' || p_seller_id::text));

    SELECT *
      INTO conv
    FROM public.conversations c
    WHERE c.product_id = p_product_id
      AND c.buyer_id = p_buyer_id
      AND c.seller_id = p_seller_id
    LIMIT 1;

    IF conv.id IS NOT NULL THEN
      RETURN conv;
    END IF;

    INSERT INTO public.conversations (product_id, buyer_id, seller_id, last_message_at, last_message_text)
    VALUES (p_product_id, p_buyer_id, p_seller_id, now(), NULL)
    RETURNING * INTO conv;

    RETURN conv;
  END;
  $$;

-- RPC: ensure_order_conversation (idempotent create by order)
  CREATE OR REPLACE FUNCTION public.ensure_order_conversation(p_order_id bigint)
  RETURNS public.conversations
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
  AS $$
  DECLARE
    conv public.conversations;
    ord record;
  BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('order_conv:' || p_order_id::text));

    SELECT *
      INTO conv
    FROM public.conversations c
    WHERE c.order_id = p_order_id
    LIMIT 1;

  IF conv.id IS NOT NULL THEN
    RETURN conv;
  END IF;

  SELECT id, buyer_id, seller_id, product_id
    INTO ord
  FROM public.orders
  WHERE id = p_order_id;

  IF ord.id IS NULL THEN
    RAISE EXCEPTION 'Order not found' USING errcode = 'P0002';
  END IF;

  IF auth.uid() IS NOT NULL
     AND auth.uid() NOT IN (ord.buyer_id, ord.seller_id)
     AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = '42501';
  END IF;

  -- Always keep a dedicated conversation per order.
  SELECT * INTO conv
  FROM public.conversations c
  WHERE c.order_id = p_order_id
  LIMIT 1;

  IF conv.id IS NOT NULL THEN
    RETURN conv;
  END IF;

    INSERT INTO public.conversations (
      order_id,
      product_id,
      buyer_id,
      seller_id,
      last_message_at,
      last_message_text
    ) VALUES (
      p_order_id,
      ord.product_id,
      ord.buyer_id,
      ord.seller_id,
      now(),
      NULL
    )
    RETURNING * INTO conv;

    RETURN conv;
  END;
  $$;

-- RPC: post_order_event (system message with dedupe)
CREATE OR REPLACE FUNCTION public.post_order_event(
  p_order_id bigint,
  p_event text,
  p_payload jsonb,
  p_dedupe_key text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  conv public.conversations;
  msg public.messages;
  v_text text;
  v_sender uuid;
BEGIN
  conv := public.ensure_order_conversation(p_order_id);

  IF auth.uid() IS NOT NULL
     AND auth.uid() NOT IN (conv.buyer_id, conv.seller_id)
     AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = '42501';
  END IF;

    v_text := coalesce(p_payload->>'text', p_payload->>'i18n_key', p_event);
  v_sender := coalesce(auth.uid(), conv.seller_id, conv.buyer_id);

  IF p_dedupe_key IS NULL OR p_dedupe_key = '' THEN
    INSERT INTO public.messages (conversation_id, sender_id, text, type, payload)
    VALUES (conv.id, v_sender, v_text, 'system', p_payload)
    RETURNING * INTO msg;
  ELSE
    INSERT INTO public.messages (conversation_id, sender_id, text, type, payload, dedupe_key)
    VALUES (conv.id, v_sender, v_text, 'system', p_payload, p_dedupe_key)
    ON CONFLICT (conversation_id, dedupe_key) DO NOTHING
    RETURNING * INTO msg;

    IF msg.id IS NULL THEN
      SELECT * INTO msg
      FROM public.messages
      WHERE conversation_id = conv.id AND dedupe_key = p_dedupe_key;
    END IF;
  END IF;

  IF msg.id IS NOT NULL THEN
    UPDATE public.conversations
    SET last_message_at   = msg.created_at,
        last_message_text = msg.text,
        updated_at        = now()
    WHERE id = conv.id;
  END IF;
END;
$$;

-- RPC: send_message
DROP FUNCTION IF EXISTS public.send_message(uuid, text) CASCADE;
CREATE OR REPLACE FUNCTION public.send_message(
  p_conversation_id uuid,
  p_text text,
  p_type text DEFAULT 'text',
  p_payload jsonb DEFAULT NULL,
  p_dedupe_key text DEFAULT NULL
)
RETURNS public.messages
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  msg public.messages;
  other uuid;
BEGIN
  IF NOT public.is_participant(p_conversation_id) THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.conversations WHERE id = p_conversation_id) THEN
    RAISE EXCEPTION 'Conversation missing' USING errcode = 'P0002';
  END IF;
  SELECT CASE WHEN buyer_id = auth.uid() THEN seller_id ELSE buyer_id END
    INTO other FROM public.conversations WHERE id = p_conversation_id;
  IF EXISTS (
    SELECT 1 FROM public.user_blocks b
    WHERE (b.user_id = auth.uid() AND b.blocked_user_id = other)
       OR (b.user_id = other AND b.blocked_user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'blocked' USING errcode = '42501';
  END IF;

  IF p_dedupe_key IS NULL OR p_dedupe_key = '' THEN
    INSERT INTO public.messages (conversation_id, sender_id, text, type, payload)
    VALUES (p_conversation_id, auth.uid(), p_text, coalesce(p_type, 'text'), p_payload)
    RETURNING * INTO msg;
  ELSE
    INSERT INTO public.messages (conversation_id, sender_id, text, type, payload, dedupe_key)
    VALUES (p_conversation_id, auth.uid(), p_text, coalesce(p_type, 'text'), p_payload, p_dedupe_key)
    ON CONFLICT (conversation_id, dedupe_key) DO NOTHING
    RETURNING * INTO msg;
    IF msg.id IS NULL THEN
      SELECT * INTO msg
      FROM public.messages
      WHERE conversation_id = p_conversation_id
        AND dedupe_key = p_dedupe_key;
    END IF;
  END IF;

  UPDATE public.conversations
  SET last_message_at   = msg.created_at,
      last_message_text = msg.text,
      updated_at        = now()
  WHERE id = p_conversation_id;

  RETURN msg;
END;
$$;

revoke all on function public.ensure_order_conversation(bigint) from public;
grant execute on function public.ensure_order_conversation(bigint) to authenticated;
revoke all on function public.post_order_event(bigint, text, jsonb, text) from public;
grant execute on function public.post_order_event(bigint, text, jsonb, text) to authenticated, service_role;
revoke all on function public.send_message(uuid, text, text, jsonb, text) from public;
grant execute on function public.send_message(uuid, text, text, jsonb, text) to authenticated;

-- RPC: delete_conversation (soft delete per user)
CREATE OR REPLACE FUNCTION public.delete_conversation(p_conversation_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT public.is_participant(p_conversation_id) THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = '42501';
  END IF;

  UPDATE public.conversations
  SET buyer_hidden_at  = CASE WHEN buyer_id  = auth.uid() THEN now() ELSE buyer_hidden_at END,
      seller_hidden_at = CASE WHEN seller_id = auth.uid() THEN now() ELSE seller_hidden_at END,
      updated_at        = now()
  WHERE id = p_conversation_id;
END;
$$;

-- RPC: restore_conversation (unhide)
DROP FUNCTION IF EXISTS public.restore_conversation(uuid);
CREATE OR REPLACE FUNCTION public.restore_conversation(p_conversation_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT public.is_participant(p_conversation_id) THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = '42501';
  END IF;
  UPDATE public.conversations
  SET buyer_hidden_at  = CASE WHEN buyer_id  = auth.uid() THEN NULL ELSE buyer_hidden_at END,
      seller_hidden_at = CASE WHEN seller_id = auth.uid() THEN NULL ELSE seller_hidden_at END,
      updated_at        = now()
  WHERE id = p_conversation_id;
END;
$$;

-- RPC: mark_read
CREATE OR REPLACE FUNCTION public.mark_read(p_conversation_id uuid, p_last_message_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT public.is_participant(p_conversation_id) THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = '42501';
  END IF;

  INSERT INTO public.reads (conversation_id, user_id, last_read_at, last_read_message_id)
  VALUES (p_conversation_id, auth.uid(), now(), p_last_message_id)
  ON CONFLICT (conversation_id, user_id) DO UPDATE
    SET last_read_at = excluded.last_read_at,
        last_read_message_id = excluded.last_read_message_id;
END;
$$;

-- RPC: get_conversations (pagination stable)
DROP FUNCTION IF EXISTS public.get_conversations(integer, timestamptz, uuid) CASCADE;
CREATE OR REPLACE FUNCTION public.get_conversations(p_limit int DEFAULT 20,
                                                    p_cursor_last timestamptz DEFAULT NULL,
                                                    p_cursor_id uuid DEFAULT NULL)
RETURNS TABLE (
  id uuid,
  buyer_id uuid,
  seller_id uuid,
  product_id bigint,
  order_id bigint,
  last_message_at timestamptz,
  last_message_text text,
  buyer_hidden_at timestamptz,
  seller_hidden_at timestamptz
) LANGUAGE sql STABLE AS $$
  WITH base AS (
    SELECT *
    FROM public.conversations c
    WHERE (
      (auth.uid() = c.buyer_id AND c.buyer_hidden_at IS NULL)
      OR (auth.uid() = c.seller_id AND c.seller_hidden_at IS NULL)
    )
  ), filtered AS (
    SELECT * FROM base b
    WHERE (
      p_cursor_last IS NULL
      OR (b.last_message_at, b.id) < (p_cursor_last, p_cursor_id)
    )
  )
  SELECT b.id, b.buyer_id, b.seller_id, b.product_id, b.order_id, b.last_message_at, b.last_message_text, b.buyer_hidden_at, b.seller_hidden_at
  FROM filtered b
  ORDER BY b.last_message_at DESC, b.id DESC
  LIMIT p_limit;
$$;

-- User blocks ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_blocks (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, blocked_user_id)
);
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS blocks_select ON public.user_blocks;
DROP POLICY IF EXISTS blocks_insert ON public.user_blocks;
DROP POLICY IF EXISTS blocks_delete ON public.user_blocks;
CREATE POLICY blocks_select ON public.user_blocks
  FOR SELECT USING (auth.uid() = user_id OR auth.uid() = blocked_user_id);
CREATE POLICY blocks_insert ON public.user_blocks
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY blocks_delete ON public.user_blocks
  FOR DELETE USING (auth.uid() = user_id);
-- RLS enable
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reads        ENABLE ROW LEVEL SECURITY;

-- Conversations policies
DROP POLICY IF EXISTS conv_select ON public.conversations;
CREATE POLICY conv_select ON public.conversations
  FOR SELECT USING (
    auth.uid() IN (buyer_id, seller_id)
  );

DROP POLICY IF EXISTS conv_insert ON public.conversations;
CREATE POLICY conv_insert ON public.conversations
  FOR INSERT WITH CHECK (auth.uid() IN (buyer_id, seller_id));

DROP POLICY IF EXISTS conv_update ON public.conversations;
CREATE POLICY conv_update ON public.conversations
  FOR UPDATE USING (auth.uid() IN (buyer_id, seller_id));

-- Messages policies
DROP POLICY IF EXISTS msg_select ON public.messages;
CREATE POLICY msg_select ON public.messages
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.conversations c
            WHERE c.id = conversation_id
              AND auth.uid() IN (c.buyer_id, c.seller_id))
  );

DROP POLICY IF EXISTS msg_insert ON public.messages;
CREATE POLICY msg_insert ON public.messages
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.conversations c
            WHERE c.id = conversation_id
              AND auth.uid() IN (c.buyer_id, c.seller_id))
    AND sender_id = auth.uid()
  );

-- Reads policies
DROP POLICY IF EXISTS reads_select ON public.reads;
CREATE POLICY reads_select ON public.reads
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS reads_upsert ON public.reads;
CREATE POLICY reads_upsert ON public.reads
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS messages_sender_created_idx ON public.messages (sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS messages_conv_created_idx ON public.messages (conversation_id, created_at DESC);

-- Driver positions -----------------------------------------------------------
create table if not exists public.driver_positions (
  id bigserial primary key,
  order_id bigint not null references public.orders(id) on delete cascade,
  driver_id uuid not null references public.profiles(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  heading double precision,
  updated_at timestamptz default now()
);
alter table public.driver_positions enable row level security;
drop policy if exists "positions visible to buyer seller driver" on public.driver_positions;
drop policy if exists "positions insert by driver" on public.driver_positions;
create policy "positions visible to buyer seller driver" on public.driver_positions
  for select using (
    auth.uid() = driver_id
    or auth.uid() = (select buyer_id from public.orders where id = order_id)
    or auth.uid() = (select seller_id from public.orders where id = order_id)
  );
create policy "positions insert by driver" on public.driver_positions
  for insert with check (
    auth.uid() = driver_id
    and auth.uid() = (select driver_id from public.orders where id = order_id)
  );
create index if not exists driver_positions_order_time_idx on public.driver_positions (order_id, updated_at desc);

-- Saved searches -------------------------------------------------------------
create table if not exists public.saved_searches (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  query text,
  filters jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.saved_searches enable row level security;
drop policy if exists "saved searches select own" on public.saved_searches;
drop policy if exists "saved searches insert own" on public.saved_searches;
drop policy if exists "saved searches update own" on public.saved_searches;
drop policy if exists "saved searches delete own" on public.saved_searches;
create policy "saved searches select own" on public.saved_searches
  for select using (auth.uid() = user_id);
create policy "saved searches insert own" on public.saved_searches
  for insert with check (auth.uid() = user_id);
create policy "saved searches update own" on public.saved_searches
  for update using (auth.uid() = user_id);
create policy "saved searches delete own" on public.saved_searches
  for delete using (auth.uid() = user_id);
drop trigger if exists saved_searches_touch on public.saved_searches;
create trigger saved_searches_touch
  before update on public.saved_searches
  for each row execute procedure public.touch_updated_at();

-- Offers ---------------------------------------------------------------------
create table if not exists public.offers (
  id bigserial primary key,
  product_id bigint not null references public.products(id) on delete cascade,
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected','expired','cancelled')),
  amount numeric(12,2) not null,
  counter_amount numeric(12,2),
  agreed_amount numeric(12,2),
  counter_by uuid references public.profiles(id) on delete set null,
  message text,
  created_at timestamptz default now(),
  responded_at timestamptz,
  updated_at timestamptz default now()
);
alter table public.offers enable row level security;
drop policy if exists "offers select buyer seller" on public.offers;
drop policy if exists "offers insert buyer" on public.offers;
drop policy if exists "offers update buyer seller" on public.offers;
create policy "offers select buyer seller" on public.offers
  for select using (auth.uid() = buyer_id or auth.uid() = seller_id);
create policy "offers insert buyer" on public.offers
  for insert with check (auth.uid() = buyer_id);
create policy "offers update buyer seller" on public.offers
  for update using (auth.uid() = buyer_id or auth.uid() = seller_id);
drop trigger if exists offers_touch on public.offers;
create trigger offers_touch
  before update on public.offers
  for each row execute procedure public.touch_updated_at();
create index if not exists offers_product_idx on public.offers (product_id, status, created_at desc);
create index if not exists offers_seller_idx on public.offers (seller_id, status, created_at desc);

-- Payment intents + events ---------------------------------------------------
create table if not exists public.payment_intents (
  id bigserial primary key,
  order_id bigint not null references public.orders(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'requires_payment_method',
  provider text default 'mock',
  client_secret text,
  amount numeric(12,2),
  currency text default 'DZD',
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  status_reason text,
  captured_at timestamptz,
  constraint payment_status_check check (
    status in ('requires_payment_method','requires_capture','succeeded','failed','canceled')
  )
);
alter table public.payment_intents enable row level security;
drop policy if exists "payment intents select own" on public.payment_intents;
drop policy if exists "payment intents insert own" on public.payment_intents;
drop policy if exists "payment intents update own" on public.payment_intents;
create policy "payment intents select own" on public.payment_intents
  for select using (auth.uid() = user_id);
create policy "payment intents insert own" on public.payment_intents
  for insert with check (auth.uid() = user_id);
create policy "payment intents update own" on public.payment_intents
  for update using (auth.uid() = user_id);
drop trigger if exists payment_intents_touch on public.payment_intents;
create trigger payment_intents_touch
  before update on public.payment_intents
  for each row execute procedure public.touch_updated_at();
create index if not exists payment_intents_order_idx on public.payment_intents (order_id);

create table if not exists public.payment_events (
  id bigserial primary key,
  intent_id bigint not null references public.payment_intents(id) on delete cascade,
  status text not null,
  note text,
  created_at timestamptz default now()
);
alter table public.payment_events enable row level security;
drop policy if exists "payment_events select own" on public.payment_events;
create policy "payment_events select own" on public.payment_events
  for select using (auth.uid() = (select user_id from public.payment_intents where id = intent_id));

-- Device tokens --------------------------------------------------------------
create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text,
  created_at timestamptz default now()
);
alter table public.device_tokens enable row level security;
drop policy if exists "device tokens select own" on public.device_tokens;
drop policy if exists "device tokens write own" on public.device_tokens;
drop policy if exists "device tokens delete own" on public.device_tokens;
create policy "device tokens select own" on public.device_tokens
  for select using (auth.uid() = user_id);
create policy "device tokens write own" on public.device_tokens
  for insert with check (auth.uid() = user_id);
create policy "device tokens delete own" on public.device_tokens
  for delete using (auth.uid() = user_id);
create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

-- Reviews --------------------------------------------------------------------
create table if not exists public.reviews (
  id bigserial primary key,
  order_id bigint references public.orders(id) on delete cascade,
  reviewer_id uuid references public.profiles(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz default now(),
  constraint reviews_order_reviewer_unique unique (order_id, reviewer_id)
);
alter table public.reviews enable row level security;
drop policy if exists "reviews select all" on public.reviews;
drop policy if exists "reviews insert own" on public.reviews;
drop policy if exists "reviews update own" on public.reviews;
drop policy if exists "reviews delete own" on public.reviews;
create policy "reviews select all" on public.reviews for select using (true);
create policy "reviews insert own" on public.reviews
  for insert with check (auth.uid() = reviewer_id);
create policy "reviews update own" on public.reviews
  for update using (auth.uid() = reviewer_id);
create policy "reviews delete own" on public.reviews
  for delete using (auth.uid() = reviewer_id);

-- Reports --------------------------------------------------------------------
create table if not exists public.reports (
  id bigserial primary key,
  product_id bigint references public.products(id) on delete cascade,
  reporter_id uuid references public.profiles(id) on delete cascade,
  reason text,
  created_at timestamptz default now()
);
alter table public.reports enable row level security;
drop policy if exists "reports select all" on public.reports;
drop policy if exists "reports insert own" on public.reports;
drop policy if exists "reports delete own" on public.reports;
create policy "reports select all" on public.reports
  for select using (true);
create policy "reports insert own" on public.reports
  for insert with check (auth.uid() = reporter_id);
create policy "reports delete own" on public.reports
  for delete using (auth.uid() = reporter_id);

-- Storage buckets + policies -------------------------------------------------
insert into storage.buckets (id, name, public)
values ('products', 'products', true)
on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
values ('messages', 'messages', true)
on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
values ('labels', 'labels', false)
on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "product images public read" on storage.objects;
drop policy if exists "product images upload" on storage.objects;
drop policy if exists "product images delete own" on storage.objects;
create policy "product images public read" on storage.objects
  for select using (bucket_id = 'products');
create policy "product images upload" on storage.objects
  for insert with check (
    bucket_id = 'products' and auth.role() in ('authenticated','service_role')
  );
create policy "product images delete own" on storage.objects
  for delete using (bucket_id = 'products' and auth.uid() = owner);

drop policy if exists "message images public read" on storage.objects;
drop policy if exists "message images upload" on storage.objects;
drop policy if exists "message images delete own" on storage.objects;
create policy "message images public read" on storage.objects
  for select using (bucket_id = 'messages');
create policy "message images upload" on storage.objects
  for insert with check (
    bucket_id = 'messages' and auth.role() in ('authenticated','service_role')
  );
create policy "message images delete own" on storage.objects
  for delete using (bucket_id = 'messages' and auth.uid() = owner);

drop policy if exists "avatars read" on storage.objects;
drop policy if exists "avatars upload own" on storage.objects;
drop policy if exists "avatars update own" on storage.objects;
drop policy if exists "avatars delete own" on storage.objects;
create policy "avatars read" on storage.objects
  for select using (bucket_id = 'avatars');
create policy "avatars upload own" on storage.objects
  for insert with check (
    bucket_id = 'avatars'
    and auth.uid()::text = split_part(name, '/', 1)
  );
create policy "avatars update own" on storage.objects
  for update using (
    bucket_id = 'avatars'
    and auth.uid()::text = split_part(name, '/', 1)
  );
create policy "avatars delete own" on storage.objects
  for delete using (
    bucket_id = 'avatars'
    and auth.uid()::text = split_part(name, '/', 1)
  );

-- Scalability + security hardening ------------------------------------------
create extension if not exists pgcrypto;

-- Rate limits ----------------------------------------------------------------
create table if not exists public.rate_limits (
  key text primary key,
  window_start timestamptz not null,
  count integer not null,
  updated_at timestamptz default now()
);
alter table public.rate_limits enable row level security;
drop policy if exists "rate limits service" on public.rate_limits;
create policy "rate limits service" on public.rate_limits
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

create or replace function public.consume_rate_limit(
  p_key text,
  p_limit integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_count integer;
begin
  insert into public.rate_limits (key, window_start, count, updated_at)
  values (p_key, v_now, 1, v_now)
  on conflict (key) do update
    set window_start = case
        when public.rate_limits.window_start < v_now - (p_window_seconds || ' seconds')::interval
          then v_now
        else public.rate_limits.window_start
      end,
      count = case
        when public.rate_limits.window_start < v_now - (p_window_seconds || ' seconds')::interval
          then 1
        else public.rate_limits.count + 1
      end,
      updated_at = v_now
  returning count into v_count;

  return v_count <= p_limit;
end;
$$;
revoke all on function public.consume_rate_limit(text, integer, integer) from public;
grant execute on function public.consume_rate_limit(text, integer, integer) to authenticated, anon;

create index if not exists rate_limits_updated_idx on public.rate_limits (updated_at desc);

-- Abuse events + audit logs --------------------------------------------------
create table if not exists public.abuse_events (
  id bigserial primary key,
  user_id uuid references public.profiles(id) on delete set null,
  ip text,
  type text not null,
  details jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);
alter table public.abuse_events enable row level security;
drop policy if exists "abuse events service" on public.abuse_events;
create policy "abuse events service" on public.abuse_events
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
create index if not exists abuse_events_user_idx on public.abuse_events (user_id, created_at desc);

create table if not exists public.audit_logs (
  id bigserial primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity text not null,
  entity_id text,
  details jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);
alter table public.audit_logs enable row level security;
drop policy if exists "audit logs service" on public.audit_logs;
create policy "audit logs service" on public.audit_logs
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
create index if not exists audit_logs_entity_idx on public.audit_logs (entity, entity_id);

create or replace function public.log_abuse(
  p_user_id uuid,
  p_ip text,
  p_type text,
  p_details jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.abuse_events (user_id, ip, type, details)
  values (p_user_id, p_ip, p_type, coalesce(p_details, '{}'::jsonb));
end;
$$;
revoke all on function public.log_abuse(uuid, text, text, jsonb) from public;
grant execute on function public.log_abuse(uuid, text, text, jsonb) to authenticated, anon;

create or replace function public.log_audit(
  p_actor_id uuid,
  p_action text,
  p_entity text,
  p_entity_id text,
  p_details jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_logs (actor_id, action, entity, entity_id, details)
  values (p_actor_id, p_action, p_entity, p_entity_id, coalesce(p_details, '{}'::jsonb));
end;
$$;
revoke all on function public.log_audit(uuid, text, text, text, jsonb) from public;
grant execute on function public.log_audit(uuid, text, text, text, jsonb) to authenticated, anon;

-- Queue for async jobs -------------------------------------------------------
create table if not exists public.job_queue (
  id bigserial primary key,
  type text not null,
  status text not null default 'queued',
  payload jsonb not null default '{}'::jsonb,
  run_at timestamptz default now(),
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.job_queue enable row level security;
drop policy if exists "job queue service" on public.job_queue;
create policy "job queue service" on public.job_queue
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
create index if not exists job_queue_status_idx on public.job_queue (status, run_at);

create or replace function public.enqueue_job(
  p_type text,
  p_payload jsonb,
  p_run_at timestamptz
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  insert into public.job_queue (type, payload, run_at)
  values (p_type, coalesce(p_payload, '{}'::jsonb), coalesce(p_run_at, now()))
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.enqueue_job(text, jsonb, timestamptz) from public;
grant execute on function public.enqueue_job(text, jsonb, timestamptz) to service_role;

-- Anti-spam/fraud ------------------------------------------------------------
create or replace function public.enforce_message_limits()
returns trigger as $$
begin
  if length(new.text) > 2000 then
    raise exception 'message too long';
  end if;
  if not public.consume_rate_limit('msg:' || new.sender_id::text, 30, 60) then
    raise exception 'rate limit exceeded';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists messages_rate_limit on public.messages;
create trigger messages_rate_limit
  before insert on public.messages
  for each row execute procedure public.enforce_message_limits();

create or replace function public.enforce_order_limits()
returns trigger as $$
begin
  if not public.consume_rate_limit('order:' || new.buyer_id::text, 10, 3600) then
    raise exception 'order rate limit exceeded';
  end if;
  if exists (
    select 1 from public.orders o
    where o.buyer_id = new.buyer_id
      and o.product_id = new.product_id
      and o.created_at > now() - interval '5 minutes'
  ) then
    raise exception 'duplicate order';
  end if;
  if new.shipping_address_id is not null
    and not exists (
      select 1 from public.addresses a
      where a.id = new.shipping_address_id
        and a.user_id = new.buyer_id
    ) then
    raise exception 'invalid shipping address';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists orders_rate_limit on public.orders;
create trigger orders_rate_limit
  before insert on public.orders
  for each row execute procedure public.enforce_order_limits();

-- Secret encryption support (optional) --------------------------------------
alter table public.seller_delivery_settings
  add column if not exists api_key_enc bytea,
  add column if not exists api_secret_enc bytea;

create or replace function public.encrypt_seller_secrets()
returns trigger as $$
declare
  v_key text := current_setting('app.settings.enc_key', true);
begin
  if v_key is null or v_key = '' then
    return new;
  end if;
  if new.api_key is not null then
    new.api_key_enc = pgp_sym_encrypt(new.api_key, v_key);
    new.api_key = null;
  end if;
  if new.api_secret is not null then
    new.api_secret_enc = pgp_sym_encrypt(new.api_secret, v_key);
    new.api_secret = null;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists seller_delivery_encrypt on public.seller_delivery_settings;
create trigger seller_delivery_encrypt
  before insert or update on public.seller_delivery_settings
  for each row execute procedure public.encrypt_seller_secrets();

create or replace function public.get_seller_delivery_settings_secure(p_owner uuid, p_courier_id text)
returns table (courier_id text, owner_id uuid, api_key text, api_secret text, sender_id text, extra jsonb)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := current_setting('app.settings.enc_key', true);
begin
  if auth.role() <> 'service_role' then
    return;
  end if;
  return query
  select
    courier_id,
    owner_id,
    coalesce(api_key, case when v_key is not null and v_key <> '' then pgp_sym_decrypt(api_key_enc, v_key)::text end),
    coalesce(api_secret, case when v_key is not null and v_key <> '' then pgp_sym_decrypt(api_secret_enc, v_key)::text end),
    sender_id,
    extra
  from public.seller_delivery_settings
  where owner_id = p_owner
    and courier_id = p_courier_id;
end;
$$;
revoke all on function public.get_seller_delivery_settings_secure(uuid, text) from public;
grant execute on function public.get_seller_delivery_settings_secure(uuid, text) to service_role;

-- Extra indexes --------------------------------------------------------------
create index if not exists messages_sender_created_idx on public.messages (sender_id, created_at desc);
create index if not exists orders_buyer_status_created_idx on public.orders (buyer_id, status, created_at desc);
create index if not exists orders_seller_status_created_idx on public.orders (seller_id, status, created_at desc);

-- Job runner + secret rotation helpers --------------------------------------
create or replace function public.claim_jobs(
  p_type text,
  p_limit integer
) returns setof public.job_queue
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with picked as (
    select id
    from public.job_queue
    where type = p_type
      and status = 'queued'
      and run_at <= now()
    order by run_at, id
    limit p_limit
    for update skip locked
  )
  update public.job_queue jq
  set status = 'running',
      attempts = jq.attempts + 1,
      updated_at = now()
  from picked
  where jq.id = picked.id
  returning jq.*;
end;
$$;
revoke all on function public.claim_jobs(text, integer) from public;
grant execute on function public.claim_jobs(text, integer) to service_role;

create or replace function public.complete_job(
  p_id bigint,
  p_success boolean,
  p_error text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.job_queue
  set status = case when p_success then 'done' else 'failed' end,
      last_error = p_error,
      updated_at = now()
  where id = p_id;
end;
$$;
revoke all on function public.complete_job(bigint, boolean, text) from public;
grant execute on function public.complete_job(bigint, boolean, text) to service_role;

create or replace function public.reencrypt_seller_secrets(
  p_old_key text,
  p_new_key text
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated integer := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'forbidden';
  end if;
  if p_new_key is null or p_new_key = '' then
    raise exception 'new key required';
  end if;

  update public.seller_delivery_settings
  set api_key_enc = pgp_sym_encrypt(
        coalesce(api_key, pgp_sym_decrypt(api_key_enc, p_old_key)::text),
        p_new_key
      ),
      api_secret_enc = pgp_sym_encrypt(
        coalesce(api_secret, pgp_sym_decrypt(api_secret_enc, p_old_key)::text),
        p_new_key
      ),
      api_key = null,
      api_secret = null
  where api_key is not null
     or api_secret is not null
     or api_key_enc is not null
     or api_secret_enc is not null;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;
revoke all on function public.reencrypt_seller_secrets(text, text) from public;
grant execute on function public.reencrypt_seller_secrets(text, text) to service_role;

-- Seed courier ZR Express if couriers table exists --------------------------
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'couriers'
  ) then
    begin
      insert into public.couriers (code, name, contact, coverage)
      values ('zrexpress', 'ZR Express', 'support@zrexpress.app', 'National')
      on conflict (code) do update set name = excluded.name;
    exception when undefined_column then
      insert into public.couriers (code, name)
      values ('zrexpress', 'ZR Express')
      on conflict (code) do update set name = excluded.name;
    end;
  end if;
end;
$$;



