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
  role text not null default 'buyer', -- buyer | seller | admin | superadmin
  status text not null default 'active', -- active | suspended | banned
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
alter table public.profiles
  add column if not exists status text default 'active';
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_role_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_role_check
      check (role in ('buyer', 'seller', 'admin', 'superadmin'));
  end if;
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_status_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_status_check
      check (status in ('active', 'suspended', 'banned'));
  end if;
end $$;
alter table public.profiles enable row level security;
drop policy if exists "public profiles read" on public.profiles;
drop policy if exists "own profile update" on public.profiles;
drop policy if exists "insert self" on public.profiles;
create policy "public profiles read" on public.profiles for select using (true);
create policy "own profile update" on public.profiles for update using (auth.uid() = id);
create policy "insert self" on public.profiles
  for insert with check (
    auth.uid() = id
    and coalesce(role, 'buyer') in ('buyer', 'seller')
    and coalesce(status, 'active') = 'active'
  );
create or replace function public.prevent_profile_privilege_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Users can switch only between buyer/seller on their own profile.
  if auth.role() <> 'service_role' and new.id = auth.uid() then
    if coalesce(new.status, 'active') is distinct from coalesce(old.status, 'active') then
      raise exception 'forbidden';
    end if;
    if coalesce(old.role, 'buyer') in ('admin', 'superadmin') then
      if coalesce(new.role, old.role) is distinct from old.role then
        raise exception 'forbidden';
      end if;
    elsif coalesce(new.role, 'buyer') not in ('buyer', 'seller') then
      raise exception 'forbidden';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before update on public.profiles
  for each row execute procedure public.prevent_profile_privilege_escalation();
drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch
  before update on public.profiles
  for each row execute procedure public.touch_updated_at();

create or replace function public.is_user_active(p_uid uuid default auth.uid())
returns boolean language sql stable as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_uid
      and coalesce(p.status, 'active') = 'active'
  );
$$;

create or replace function public.is_superadmin(p_uid uuid default auth.uid())
returns boolean language sql stable as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_uid
      and p.role = 'superadmin'
      and coalesce(p.status, 'active') = 'active'
  );
$$;

-- Trigger to auto-create profile on new auth user
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name, phone, role, is_public, is_seller)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'phone',
    'buyer',
    true,
    false
  )
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
  ('browse', 'ar', 'ÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂªÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂµÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â­'),
  ('orders', 'fr', 'Commandes'),
  ('orders', 'ar', 'ÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â·ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§ÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Âª'),
  ('chat', 'fr', 'Chat'),
  ('chat', 'ar', 'ÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â±ÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â´ÃƒÆ’Ã†â€™Ãƒâ€¹Ã…â€œÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â©')
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
('women','Femmes','Femmes','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¡',null,10,true,'woman'),
('men','Hommes','Hommes','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾',null,20,true,'man'),
('kids','Enfants','Enfants','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â·ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾',null,30,true,'child_care'),
('home','Maison','Maison','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾',null,40,true,'home'),
('beauty','BeautÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â© & SantÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©','BeautÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â© & SantÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂµÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',null,50,true,'spa'),
('electronics','ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°lectronique','ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°lectronique','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¥ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',null,60,true,'devices'),
('sports','Sport & Outdoor','Sport & Outdoor','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¶ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â© ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â®ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',null,70,true,'sports_soccer'),
('media','Livres & Divertissement','Livres & Divertissement','ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡',null,80,true,'menu_book'),
('toys','Jouets & Jeux','Jouets & Jeux','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨',null,90,true,'toys'),
('other','Autres','Autres','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â®ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°',null,100,true,'category')
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
('women-clothing','VÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âªtements','VÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âªtements','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³',(select id from public.categories where slug='women'),1,true,'checkroom'),
('women-shoes','Chaussures','Chaussures','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â°ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='women'),2,true,'hiking'),
('women-bags','Sacs','Sacs','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨',(select id from public.categories where slug='women'),3,true,'work'),
('women-accessories','Accessoires','Accessoires','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¥ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='women'),4,true,'watch'),
('women-jewelry','Bijoux','Bijoux','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='women'),5,true,'diamond'),
('women-lingerie','Lingerie','Lingerie','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â®ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='women'),6,true,'local_mall')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- MEN
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('men-clothing','VÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âªtements','VÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âªtements','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³',(select id from public.categories where slug='men'),1,true,'checkroom'),
('men-shoes','Chaussures','Chaussures','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â°ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='men'),2,true,'hiking'),
('men-accessories','Accessoires','Accessoires','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¥ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='men'),3,true,'watch'),
('men-bags','Sacs','Sacs','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨',(select id from public.categories where slug='men'),4,true,'work'),
('men-watches','Montres','Montres','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='men'),5,true,'watch')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- KIDS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('kids-baby','BÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©bÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â© (0-24 mois)','BÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©bÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â© (0-24 mois)','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¶ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹',(select id from public.categories where slug='kids'),1,true,'child_friendly'),
('kids-clothing','VÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âªtements','VÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âªtements','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³',(select id from public.categories where slug='kids'),2,true,'checkroom'),
('kids-shoes','Chaussures','Chaussures','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â°ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='kids'),3,true,'hiking'),
('kids-accessories','Accessoires','Accessoires','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¥ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='kids'),4,true,'backpack'),
('kids-school','ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°cole','ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°cole','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='kids'),5,true,'school')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- HOME
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('home-furniture','Meubles','Meubles','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â«ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â«',(select id from public.categories where slug='home'),1,true,'weekend'),
('home-decor','DÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©coration','DÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©coration','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±',(select id from public.categories where slug='home'),2,true,'auto_awesome'),
('home-kitchen','Cuisine','Cuisine','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â·ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â®',(select id from public.categories where slug='home'),3,true,'kitchen'),
('home-textiles','Textiles','Textiles','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='home'),4,true,'curtains'),
('home-appliances','ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°lectromÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©nager','ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°lectromÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©nager','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â© ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='home'),5,true,'microwave')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- BEAUTY
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('beauty-makeup','Maquillage','Maquillage','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬',(select id from public.categories where slug='beauty'),1,true,'brush'),
('beauty-skincare','Soins de la peau','Soins de la peau','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â© ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â´ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='beauty'),2,true,'face'),
('beauty-hair','Cheveux','Cheveux','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â´ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±',(select id from public.categories where slug='beauty'),3,true,'content_cut'),
('beauty-fragrance','Parfums','Parfums','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â·ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±',(select id from public.categories where slug='beauty'),4,true,'local_florist'),
('beauty-wellness','BienÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âªtre','BienÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âªtre','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â© ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂµÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='beauty'),5,true,'favorite')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- ELECTRONICS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('electronics-phones','TÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©lÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©phones','TÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©lÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©phones','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚Â',(select id from public.categories where slug='electronics'),1,true,'smartphone'),
('electronics-computers','Ordinateurs','Ordinateurs','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨',(select id from public.categories where slug='electronics'),2,true,'laptop'),
('electronics-tablets','Tablettes','Tablettes','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â© ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='electronics'),3,true,'tablet'),
('electronics-audio','Audio','Audio','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂµÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='electronics'),4,true,'headphones'),
('electronics-gaming','Gaming','Gaming','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨',(select id from public.categories where slug='electronics'),5,true,'sports_esports'),
('electronics-accessories','Accessoires','Accessoires','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¥ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='electronics'),6,true,'cable')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- SPORTS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('sports-clothing','VÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âªtements de sport','VÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âªtements de sport','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¶ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='sports'),1,true,'sports'),
('sports-shoes','Chaussures de sport','Chaussures de sport','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â°ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â© ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¶ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='sports'),2,true,'hiking'),
('sports-equipment','ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°quipement','ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°quipement','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='sports'),3,true,'fitness_center'),
('sports-bikes','VÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©los','VÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©los','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='sports'),4,true,'pedal_bike'),
('sports-outdoor','Camping & Outdoor','Camping & Outdoor','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â®ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â®ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='sports'),5,true,'terrain')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- MEDIA
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('media-books','Livres','Livres','ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨',(select id from public.categories where slug='media'),1,true,'menu_book'),
('media-movies','Films & SÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©ries','Films & SÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©ries','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='media'),2,true,'movie'),
('media-music','Musique','Musique','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°',(select id from public.categories where slug='media'),3,true,'music_note'),
('media-games','Jeux vidÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©o','Jeux vidÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©o','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ',(select id from public.categories where slug='media'),4,true,'sports_esports')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- TOYS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('toys-figures','Figurines','Figurines','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='toys'),1,true,'smart_toy'),
('toys-boardgames','Jeux de sociÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©tÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©','Jeux de sociÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©tÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©',(select id from public.categories where slug='toys'),2,true,'casino'),
('toys-construction','Construction','Construction','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¡',(select id from public.categories where slug='toys'),3,true,'construction'),
('toys-baby','Jouets bÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©bÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©','Jouets bÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©bÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¶ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹',(select id from public.categories where slug='toys'),4,true,'child_friendly')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- OTHER
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('other-services','Services','Services','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â®ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='other'),1,true,'support_agent'),
('other-collectibles','Collections','Collections','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª',(select id from public.categories where slug='other'),2,true,'collections'),
('other-misc','Divers','Divers','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹',(select id from public.categories where slug='other'),3,true,'more_horiz')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- Quick check
-- select slug, name_fr, parent_id from public.categories order by parent_id nulls first, sort_order;

-- Seed wilayas (FR/AR)
insert into public.wilayas (code, name_fr, name_ar) values
('01','Adrar','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±'),
('02','Chlef','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â´ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚Â'),
('03','Laghouat','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂºÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â·'),
('04','Oum El Bouaghi','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â '),
('05','Batna','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('06','Bejaia','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('07','Biskra','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('08','Bechar','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â´ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±'),
('09','Blida','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('10','Bouira','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('11','Tamanrasset','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª'),
('12','Tebessa','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('13','Tlemcen','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â '),
('14','Tiaret','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª'),
('15','Tizi Ouzou','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â  ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â '),
('16','Alger','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±'),
('17','Djelfa','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('18','Jijel','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾'),
('19','Setif','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â·ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚Â'),
('20','Saida','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('21','Skikda','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('22','Sidi Bel Abbes','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â  ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³'),
('23','Annaba','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('24','Guelma','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('25','Constantine','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â·ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('26','Medea','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('27','Mostaganem','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂºÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦'),
('28','M''Sila','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('29','Mascara','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±'),
('30','Ouargla','ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('31','Oran','ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â '),
('32','El Bayadh','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¶'),
('33','Illizi','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¥ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â '),
('34','Bordj Bou Arreridj','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬'),
('35','Boumerdes','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³'),
('36','El Tarf','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â·ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚Â'),
('37','Tindouf','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚Â'),
('38','Tissemsilt','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª'),
('39','El Oued','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â '),
('40','Khenchela','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â®ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â´ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('41','Souk Ahras','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³'),
('42','Tipaza','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('43','Mila','ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('44','Ain Defla','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°'),
('45','Naama','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('46','Ain Temouchent','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â´ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª'),
('47','Ghardaia','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂºÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('48','Relizane','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂºÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â '),
('49','El M''Ghair','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂºÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±'),
('50','El Meniaa','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©'),
('51','Ouled Djellal','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾'),
('52','Bordj Baji Mokhtar','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â  ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â®ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±'),
('53','Beni Abbes','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â  ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³'),
('54','Timimoun','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â '),
('55','Touggourt','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª'),
('56','Djanet','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Âª'),
('57','In Salah','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂµÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­'),
('58','In Guezzam','ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â²ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦')
on conflict (code) do update set
  name_fr = excluded.name_fr,
  name_ar = excluded.name_ar;
-- Seed communes (full dataset)
insert into public.communes (wilaya_code, name_fr, name_ar) values
('01','Adrar',null),
('01','Tamest',null),
('01','Reggane',null),
('01','In Zghmir',null),
('01','Tit',null),
('01','Tsabit',null),
('01','Zaouiet Kounta',null),
('01','Aoulef',null),
('01','Tamekten',null),
('01','Tamantit',null),
('01','Fenoughil',null),
('01','Sali',null),
('01','Akabli',null),
('01','Ouled Ahmed Tammi',null),
('01','Bouda',null),
('01','Sebaa',null),
('02','Abou El Hassan',null),
('02','AÃ¯n Merane',null),
('02','BÃ©nairia',null),
('02','Beni Bouateb',null),
('02','Beni Haoua',null),
('02','Beni Rached',null),
('02','Boukadir',null),
('02','Bouzeghaia',null),
('02','Breira',null),
('02','Chettia',null),
('02','Chlef',null),
('02','Dahra',null),
('02','El Hadjadj',null),
('02','El Karimia',null),
('02','El Marsa',null),
('02','Harchoun',null),
('02','Harenfa',null),
('02','Labiod Medjadja',null),
('02','Moussadek',null),
('02','Oued Fodda',null),
('02','Oued Goussine',null),
('02','Oued Sly',null),
('02','Ouled Abbes',null),
('02','Ouled Ben Abdelkader',null),
('02','Ouled Fares',null),
('02','Oum Drou',null),
('02','Sendjas',null),
('02','Sidi Abderrahmane',null),
('02','Sidi Akkacha',null),
('02','Sobha',null),
('02','Tadjena',null),
('02','Talassa',null),
('02','Taougrite',null),
('02','TÃ©nÃ¨s',null),
('02','Zeboudja',null),
('03','Laghouat',null),
('03','Ksar El Hirane',null),
('03','Bennasser Benchohra',null),
('03','Sidi Makhlouf',null),
('03','Hassi Delaa',null),
('03','Hassi R''Mel',null),
('03','AÃ¯n Madhi',null),
('03','Tadjemout',null),
('03','Kheneg',null),
('03','Gueltat Sidi Saad',null),
('03','AÃ¯n Sidi Ali',null),
('03','Beidha',null),
('03','Brida',null),
('03','El Ghicha',null),
('03','Hadj Mechri',null),
('03','Sebgag',null),
('03','Taouiala',null),
('03','Tadjrouna',null),
('03','Aflou',null),
('03','El Assafia',null),
('03','Oued Morra',null),
('03','Oued M''Zi',null),
('03','El Houaita',null),
('03','Sidi Bouzid',null),
('04','Oum el Bouaghi',null),
('04','AÃ¯n BeÃ¯da',null),
('04','AÃ¯n M''lila',null),
('04','Behir Chergui',null),
('04','El Amiria',null),
('04','Sigus',null),
('04','El Belala',null),
('04','AÃ¯n Babouche',null),
('04','Berriche',null),
('04','Ouled Hamla',null),
('04','Dhalaa',null),
('04','AÃ¯n Kercha',null),
('04','Hanchir Toumghani',null),
('04','El Djazia',null),
('04','AÃ¯n Diss',null),
('04','Fkirina',null),
('04','Souk Naamane',null),
('04','Zorg',null),
('04','El Fedjoudj Boughrara Saoudi',null),
('04','Ouled ZouaÃ¯',null),
('04','Bir Chouhada',null),
('04','Ksar Sbahi',null),
('04','Oued Nini',null),
('04','Meskiana',null),
('04','AÃ¯n Fakroun',null),
('04','Rahia',null),
('04','AÃ¯n Zitoun',null),
('04','Ouled Gacem',null),
('04','El Harmilia',null),
('05','Batna',null),
('05','Ghassira',null),
('05','Maafa',null),
('05','Merouana',null),
('05','Seriana',null),
('05','Menaa',null),
('05','El Madher',null),
('05','Tazoult',null),
('05','N''Gaous',null),
('05','Guigba',null),
('05','Inoughissen',null),
('05','Ouyoun El Assafir',null),
('05','Djerma',null),
('05','Bitam',null),
('05','Abdelkader Azil',null),
('05','Arris',null),
('05','Kimmel',null),
('05','Tilatou',null),
('05','AÃ¯n Djasser',null),
('05','Ouled Sellam',null),
('05','Tigherghar',null),
('05','AÃ¯n Yagout',null),
('05','Fesdis',null),
('05','Sefiane',null),
('05','Rahbat',null),
('05','Tighanimine',null),
('05','Lemsane',null),
('05','Ksar Bellezma',null),
('05','Seggana',null),
('05','Ichmoul',null),
('05','Foum Toub',null),
('05','Ben Foudhala El Hakania',null),
('05','Oued El Ma',null),
('05','Talkhamt',null),
('05','Bouzina',null),
('05','Chemora',null),
('05','Oued Chaaba',null),
('05','Taxlent',null),
('05','Gosbat',null),
('05','Ouled Aouf',null),
('05','Boumagueur',null),
('05','Barika',null),
('05','Djezar',null),
('05','T''Kout',null),
('05','AÃ¯n Touta',null),
('05','Hidoussa',null),
('05','Teniet El Abed',null),
('05','Oued Taga',null),
('05','Ouled Fadel',null),
('05','Timgad',null),
('05','Ras El Aioun',null),
('05','Chir',null),
('05','Ouled Si Slimane',null),
('05','Zanat El Beida',null),
('05','M''doukel',null),
('05','Ouled Ammar',null),
('05','El Hassi',null),
('05','Lazrou',null),
('05','Boumia (Batna)',null),
('05','Boulhilat',null),
('05','LarbaÃ¢',null),
('06','BÃ©jaÃ¯a',null),
('06','Amizour',null),
('06','Ferraoun',null),
('06','Taourirt Ighil',null),
('06','Chellata',null),
('06','Tamokra',null),
('06','Timezrit',null),
('06','Souk El TÃ©nine',null),
('06','M''cisna',null),
('06','Tinabdher',null),
('06','Tichy',null),
('06','Semaoun',null),
('06','Kendira',null),
('06','Tifra',null),
('06','Ighram',null),
('06','Amalou',null),
('06','Ighil Ali',null),
('06','FenaÃ¯a Ilmaten',null),
('06','Toudja',null),
('06','Darguina',null),
('06','Sidi Ayad',null),
('06','Aokas',null),
('06','Ait Djellil',null),
('06','Adekar',null),
('06','Akbou',null),
('06','Seddouk',null),
('06','Tazmalt',null),
('06','AÃ¯t R''zine',null),
('06','Chemini',null),
('06','Souk Oufella',null),
('06','Tibane',null),
('06','Tala Hamza',null),
('06','Barbacha',null),
('06','AÃ¯t Ksila',null),
('06','Ouzellaguen',null),
('06','Bouhamza',null),
('06','Taskriout',null),
('06','AÃ¯t Mellikeche',null),
('06','Sidi AÃ¯ch',null),
('06','El Kseur',null),
('06','Melbou',null),
('06','Akfadou',null),
('06','Leflaye',null),
('06','Kherrata',null),
('06','DraÃ¢ El KaÃ¯d',null),
('06','Tamridjet',null),
('06','AÃ¯t Smail',null),
('06','Boukhelifa',null),
('06','Tizi N''Berber',null),
('06','AÃ¯t Maouche',null),
('06','Oued Ghir',null),
('06','Boudjellil',null),
('07','AÃ¯n Naga',null),
('07','AÃ¯n Zaatout',null),
('07','Biskra',null),
('07','Bordj Ben Azzouz',null),
('07','Bouchagroune',null),
('07','Branis',null),
('07','Chetma',null),
('07','Djemorah',null),
('07','El Feidh',null),
('07','El Ghrous',null),
('07','El Hadjeb',null),
('07','El Haouch',null),
('07','El Kantara',null),
('07','El Mizaraa',null),
('07','El Outaya',null),
('07','Foughala',null),
('07','Khenguet Sidi Nadji',null),
('07','Lichana',null),
('07','Lioua',null),
('07','M''Chouneche',null),
('07','Mekhadma',null),
('07','M''Lili',null),
('07','Oumache',null),
('07','Ourlal',null),
('07','Sidi Okba',null),
('07','Tolga',null),
('07','Zeribet El Oued',null),
('08','BÃ©char',null),
('08','Erg Ferradj',null),
('08','Meridja',null),
('08','Lahmar',null),
('08','Mechraa Houari Boumedienne',null),
('08','Kenadsa',null),
('08','Taghit',null),
('08','Boukais',null),
('08','Mougheul',null),
('08','Abadla',null),
('08','Beni Ounif',null),
('09','Blida',null),
('09','Chebli',null),
('09','Bouinan',null),
('09','Oued Alleug',null),
('09','Ouled YaÃ¯ch',null),
('09','ChrÃ©a',null),
('09','El Affroun',null),
('09','Chiffa',null),
('09','Hammam Melouane',null),
('09','Benkhelil',null),
('09','Soumaa',null),
('09','Mouzaia',null),
('09','Souhane',null),
('09','Meftah',null),
('09','Ouled Slama',null),
('09','Boufarik',null),
('09','Larbaa',null),
('09','Oued Djer',null),
('09','Beni Tamou',null),
('09','Bouarfa',null),
('09','Beni Mered',null),
('09','Bougara',null),
('09','Guerouaou',null),
('09','AÃ¯n Romana',null),
('09','Djebabra',null),
('10','AÃ¯n Bessem',null),
('10','Hanif',null),
('10','Aghbalou',null),
('10','AÃ¯n El Hadjar',null),
('10','Ahl El Ksar',null),
('10','AÃ¯n Laloui',null),
('10','Ath Mansour',null),
('10','Aomar',null),
('10','AÃ¯n El Turc',null),
('10','AÃ¯t Laziz',null),
('10','Bouderbala',null),
('10','Bechloul',null),
('10','Bir Ghbalou',null),
('10','Boukram',null),
('10','Bordj Okhriss',null),
('10','Bouira',null),
('10','Chorfa',null),
('10','Dechmia',null),
('10','Dirrah',null),
('10','Djebahia',null),
('10','El Hakimia',null),
('10','El Hachimia',null),
('10','El Adjiba',null),
('10','El Khabouzia',null),
('10','El Mokrani',null),
('10','El Asnam',null),
('10','Guerrouma',null),
('10','Haizer',null),
('10','Hadjera Zerga',null),
('10','Kadiria',null),
('10','Lakhdaria',null),
('10','M''Chedallah',null),
('10','Mezdour',null),
('10','Maala',null),
('10','Maamora',null),
('10','Oued El Berdi',null),
('10','Ouled Rached',null),
('10','Raouraoua',null),
('10','Ridane',null),
('10','Saharidj',null),
('10','Sour El Ghouzlane',null),
('10','Souk El Khemis',null),
('10','Taguedit',null),
('10','Taghzout',null),
('10','Zbarbar',null),
('11','Tamanrasset',null),
('11','Abalessa',null),
('11','Idles',null),
('11','Tazrouk',null),
('11','In Amguel',null),
('12','TÃ©bessa',null),
('12','Bir el Ater',null),
('12','Cheria',null),
('12','Stah Guentis',null),
('12','El Aouinet',null),
('12','El Houidjbet',null),
('12','Safsaf El Ouesra',null),
('12','Hammamet',null),
('12','Negrine',null),
('12','Bir Mokkadem',null),
('12','El Kouif',null),
('12','Morsott',null),
('12','El Ogla',null),
('12','Bir Dheb',null),
('12','Ogla Melha',null),
('12','Guorriguer',null),
('12','Bekkaria',null),
('12','Boukhadra',null),
('12','Ouenza',null),
('12','El Ma Labiodh',null),
('12','Oum Ali',null),
('12','Tlidjene',null),
('12','AÃ¯n Zerga',null),
('12','El Meridj',null),
('12','Boulhaf Dir',null),
('12','Bedjene',null),
('12','El Mezeraa',null),
('12','Ferkane',null),
('13','Tlemcen',null),
('13','Beni Mester',null),
('13','AÃ¯n Tallout',null),
('13','Remchi',null),
('13','El Fehoul',null),
('13','Sabra',null),
('13','Ghazaouet',null),
('13','Souani',null),
('13','Djebala',null),
('13','El Gor',null),
('13','Oued Lakhdar',null),
('13','AÃ¯n Fezza',null),
('13','Ouled Mimoun',null),
('13','Amieur',null),
('13','AÃ¯n Youcef',null),
('13','Zenata',null),
('13','Beni Snous',null),
('13','Bab El Assa',null),
('13','Dar Yaghmouracene',null),
('13','Fellaoucene',null),
('13','Azails',null),
('13','Sebaa Chioukh',null),
('13','Terny Beni Hdiel',null),
('13','Bensekrane',null),
('13','AÃ¯n Nehala',null),
('13','Hennaya',null),
('13','Maghnia',null),
('13','Hammam Boughrara',null),
('13','Souahlia',null),
('13','MSirda Fouaga',null),
('13','AÃ¯n Fetah',null),
('13','El Aricha',null),
('13','Souk Tlata',null),
('13','Sidi Abdelli',null),
('13','Sebdou',null),
('13','Beni Ouarsous',null),
('13','Sidi Medjahed',null),
('13','Beni Boussaid',null),
('13','Marsa Ben M''Hidi',null),
('13','Nedroma',null),
('13','Sidi Djillali',null),
('13','Beni Bahdel',null),
('13','El Bouihi',null),
('13','HonaÃ¯ne',null),
('13','Tienet',null),
('13','Ouled Riyah',null),
('13','Bouhlou',null),
('13','Beni Khellad',null),
('13','AÃ¯n Ghoraba',null),
('13','Chetouane',null),
('13','Mansourah',null),
('13','Beni Semiel',null),
('13','AÃ¯n Kebira',null),
('14','AÃ¯n Bouchekif',null),
('14','AÃ¯n Deheb',null),
('14','AÃ¯n El Hadid',null),
('14','AÃ¯n Kermes',null),
('14','AÃ¯n Dzarit',null),
('14','Bougara',null),
('14','Chehaima',null),
('14','Dahmouni',null),
('14','Djebilet Rosfa',null),
('14','Djillali Ben Amar',null),
('14','Faidja',null),
('14','Frenda',null),
('14','Guertoufa',null),
('14','Hamadia',null),
('14','Ksar Chellala',null),
('14','Madna',null),
('14','Mahdia',null),
('14','Mechraa Safa',null),
('14','Medrissa',null),
('14','Medroussa',null),
('14','Meghila',null),
('14','Mellakou',null),
('14','Nadorah',null),
('14','Naima',null),
('14','Oued Lilli',null),
('14','Rahouia',null),
('14','Rechaiga',null),
('14','Sebaine',null),
('14','Sebt',null),
('14','Serghine',null),
('14','Si Abdelghani',null),
('14','Sidi Abderahmane',null),
('14','Sidi Ali Mellal',null),
('14','Sidi Bakhti',null),
('14','Sidi Hosni',null),
('14','Sougueur',null),
('14','Tagdemt',null),
('14','Takhemaret',null),
('14','Tiaret',null),
('14','Tidda',null),
('14','Tousnina',null),
('14','Zmalet El Emir Abdelkader',null),
('15','Tizi Ouzou',null),
('15','Ain El Hammam',null),
('15','Akbil',null),
('15','Freha',null),
('15','SouamaÃ¢',null),
('15','Mechtras',null),
('15','Irdjen',null),
('15','Timizart',null),
('15','Makouda',null),
('15','DraÃ¢ El Mizan',null),
('15','Tizi Gheniff',null),
('15','Bounouh',null),
('15','AÃ¯t ChafÃ¢a',null),
('15','Frikat',null),
('15','Beni AÃ¯ssi',null),
('15','Beni Zmenzer',null),
('15','IferhounÃ¨ne',null),
('15','Azazga',null),
('15','Illoula Oumalou',null),
('15','Yakouren',null),
('15','LarbaÃ¢ Nath Irathen',null),
('15','Tizi Rached',null),
('15','Zekri',null),
('15','Ouaguenoun',null),
('15','AÃ¯n Zaouia',null),
('15','M''Kira',null),
('15','AÃ¯t Yahia',null),
('15','AÃ¯t Mahmoud',null),
('15','MÃ¢atkas',null),
('15','AÃ¯t Boumahdi',null),
('15','Abi Youcef',null),
('15','Beni Douala',null),
('15','Illilten',null),
('15','Bouzguen',null),
('15','AÃ¯t Aggouacha',null),
('15','Ouadhia',null),
('15','Azeffoun',null),
('15','Tigzirt',null),
('15','AÃ¯t AÃ¯ssa Mimoun',null),
('15','Boghni',null),
('15','Ifigha',null),
('15','AÃ¯t Oumalou',null),
('15','Tirmitine',null),
('15','Akerrou',null),
('15','Yatafen',null),
('15','Ath Zikki',null),
('15','DraÃ¢ Ben Khedda',null)
on conflict (wilaya_code, name_fr) do update set
  name_ar = excluded.name_ar;

insert into public.communes (wilaya_code, name_fr, name_ar) values
('15','Ouacif',null),
('15','Idjeur',null),
('15','Mekla',null),
('15','Tizi N''Tleta',null),
('15','AÃ¯t Yenni',null),
('15','Aghribs',null),
('15','Iflissen',null),
('15','Boudjima',null),
('15','AÃ¯t Yahia Moussa',null),
('15','Souk El Thenine',null),
('15','AÃ¯t Khellili',null),
('15','Sidi Namane',null),
('15','Iboudraren',null),
('15','Agouni Gueghrane',null),
('15','Mizrana',null),
('15','Imsouhel',null),
('15','TadmaÃ¯t',null),
('15','AÃ¯t Bouadou',null),
('15','Assi Youcef',null),
('15','AÃ¯t Toudert',null),
('16','Alger Centre',null),
('16','Sidi M''Hamed',null),
('16','El Madania',null),
('16','Belouizdad',null),
('16','Bab El Oued',null),
('16','Bologhine',null),
('16','Casbah',null),
('16','Oued Koriche',null),
('16','Bir Mourad RaÃ¯s',null),
('16','El Biar',null),
('16','Bouzareah',null),
('16','Birkhadem',null),
('16','El Harrach',null),
('16','Baraki',null),
('16','Oued Smar',null),
('16','Bachdjerrah',null),
('16','Hussein Dey',null),
('16','Kouba',null),
('16','Bourouba',null),
('16','Dar El BeÃ¯da',null),
('16','Bab Ezzouar',null),
('16','Ben Aknoun',null),
('16','Dely Ibrahim',null),
('16','El Hammamet',null),
('16','RaÃ¯s Hamidou',null),
('16','Djasr Kasentina',null),
('16','El Mouradia',null),
('16','Hydra',null),
('16','Mohammadia',null),
('16','Bordj El Kiffan',null),
('16','El Magharia',null),
('16','Beni Messous',null),
('16','Les Eucalyptus',null),
('16','Birtouta',null),
('16','Tessala El Merdja',null),
('16','Ouled Chebel',null),
('16','Sidi Moussa',null),
('16','AÃ¯n Taya',null),
('16','Bordj El Bahri',null),
('16','El Marsa',null),
('16','H''raoua',null),
('16','RouÃ¯ba',null),
('16','ReghaÃ¯a',null),
('16','AÃ¯n Benian',null),
('16','Staoueli',null),
('16','Zeralda',null),
('16','Mahelma',null),
('16','Rahmania',null),
('16','Souidania',null),
('16','Cheraga',null),
('16','Ouled Fayet',null),
('16','El Achour',null),
('16','Draria',null),
('16','Douera',null),
('16','Baba Hassen',null),
('16','Khraicia',null),
('16','Saoula',null),
('17','AÃ¯n Chouhada',null),
('17','AÃ¯n El Ibel',null),
('17','AÃ¯n Feka',null),
('17','AÃ¯n Maabed',null),
('17','AÃ¯n Oussara',null),
('17','Amourah',null),
('17','Benhar',null),
('17','Beni Yagoub',null),
('17','Birine',null),
('17','Bouira Lahdab',null),
('17','Charef',null),
('17','Dar Chioukh',null),
('17','Deldoul',null),
('17','Djelfa',null),
('17','Douis',null),
('17','El Guedid',null),
('17','El Idrissia',null),
('17','El Khemis',null),
('17','Faidh El Botma',null),
('17','Guernini',null),
('17','Guettara',null),
('17','Had Sahary',null),
('17','Hassi Bahbah',null),
('17','Hassi El Euch',null),
('17','Hassi Fedoul',null),
('17','Messaad',null),
('17','M''Liliha',null),
('17','Moudjebara',null),
('17','Oum Laadham',null),
('17','Sed Rahal',null),
('17','Selmana',null),
('17','Sidi Baizid',null),
('17','Sidi Ladjel',null),
('17','Tadmit',null),
('17','Zaafrane',null),
('17','Zaccar',null),
('18','Jijel',null),
('18','Eraguene',null),
('18','El Aouana',null),
('18','Ziama Mansouriah',null),
('18','Taher',null),
('18','Emir Abdelkader',null),
('18','Chekfa',null),
('18','Chahna',null),
('18','El Milia',null),
('18','Sidi Maarouf',null),
('18','Settara',null),
('18','El Ancer',null),
('18','Sidi Abdelaziz',null),
('18','Kaous',null),
('18','Ghebala',null),
('18','Bouraoui Belhadef',null),
('18','Djimla',null),
('18','Selma Benziada',null),
('18','Boucif Ouled Askeur',null),
('18','El Kennar Nouchfi',null),
('18','Ouled Yahia Khedrouche',null),
('18','Boudriaa Ben Yadjis',null),
('18','KheÃ¯ri Oued Adjoul',null),
('18','Texenna',null),
('18','Djemaa Beni Habibi',null),
('18','Bordj Tahar',null),
('18','Ouled Rabah',null),
('18','Ouadjana',null),
('19','AÃ¯n Abessa',null),
('19','AÃ¯n Arnat',null),
('19','AÃ¯n Azel',null),
('19','AÃ¯n El Kebira',null),
('19','AÃ¯n Lahdjar',null),
('19','AÃ¯n Legradj',null),
('19','AÃ¯n Oulmene',null),
('19','AÃ¯n Roua',null),
('19','AÃ¯n Sebt',null),
('19','AÃ¯t Naoual Mezada',null),
('19','AÃ¯t Tizi',null),
('19','AÃ¯t Wertilan',null),
('19','Amoucha',null),
('19','Babor',null),
('19','Bazer Sakhra',null),
('19','Beidha Bordj',null),
('19','Belaa',null),
('19','Beni Aziz',null),
('19','Beni Chebana',null),
('19','Beni Fouda',null),
('19','Beni Hocine',null),
('19','Beni Mouhli',null),
('19','Bir El Arch',null),
('19','Bir Haddada',null),
('19','Bouandas',null),
('19','Bougaa',null),
('19','Bousselam',null),
('19','Boutaleb',null),
('19','Dehamcha',null),
('19','Djemila',null),
('19','Draa Kebila',null),
('19','El Eulma',null),
('19','El Ouldja',null),
('19','El Ouricia',null),
('19','Guellal',null),
('19','Guelta Zerka',null),
('19','Guenzet',null),
('19','Guidjel',null),
('19','Hamma',null),
('19','Hammam Guergour',null),
('19','Hammam Soukhna',null),
('19','Harbil',null),
('19','Ksar El Abtal',null),
('19','Maaouia',null),
('19','Maoklane',null),
('19','Mezloug',null),
('19','Oued El Barad',null),
('19','Ouled Addouane',null),
('19','Ouled Sabor',null),
('19','Ouled Si Ahmed',null),
('19','Ouled Tebben',null),
('19','Rasfa',null),
('19','Salah Bey',null),
('19','Serdj El Ghoul',null),
('19','SÃ©tif',null),
('19','Tachouda',null),
('19','Talaifacene',null),
('19','Taya',null),
('19','Tella',null),
('19','Tizi N''Bechar',null),
('20','AÃ¯n El Hadjar',null),
('20','AÃ¯n Sekhouna',null),
('20','AÃ¯n Soltane',null),
('20','Doui Thabet',null),
('20','El Hassasna',null),
('20','Hounet',null),
('20','Maamora',null),
('20','Moulay Larbi',null),
('20','Ouled Brahim',null),
('20','Ouled Khaled',null),
('20','SaÃ¯da',null),
('20','Sidi Ahmed',null),
('20','Sidi Amar',null),
('20','Sidi Boubekeur',null),
('20','Tircine',null),
('20','Youb',null),
('21','AÃ¯n Bouziane',null),
('21','AÃ¯n Charchar',null),
('21','AÃ¯n Kechra',null),
('21','AÃ¯n Zouit',null),
('21','Azzaba',null),
('21','Bekkouche Lakhdar',null),
('21','Bin El Ouiden',null),
('21','Ben Azzouz',null),
('21','Beni Bechir',null),
('21','Beni Oulbane',null),
('21','Beni Zid',null),
('21','Bouchtata',null),
('21','Cheraia',null),
('21','Collo',null),
('21','Djendel Saadi Mohamed',null),
('21','El Ghedir',null),
('21','El Hadaiek',null),
('21','El Harrouch',null),
('21','El Marsa',null),
('21','Emdjez Edchich',null),
('21','Es Sebt',null),
('21','Filfila',null),
('21','Hamadi Krouma',null),
('21','Kanoua',null),
('21','Kerkera',null),
('21','Kheneg Mayoum',null),
('21','Oued Zehour',null),
('21','Ouldja Boulballout',null),
('21','Ouled Attia',null),
('21','Ouled Hbaba',null),
('21','Oum Toub',null),
('21','Ramdane Djamel',null),
('21','Salah Bouchaour',null),
('21','Sidi Mezghiche',null),
('21','Skikda',null),
('21','Tamalous',null),
('21','Zerdaza',null),
('21','Zitouna',null),
('22','AÃ¯n Adden',null),
('22','AÃ¯n El Berd',null),
('22','AÃ¯n Kada',null),
('22','AÃ¯n Thrid',null),
('22','AÃ¯n Tindamine',null),
('22','Amarnas',null),
('22','Badredine El Mokrani',null),
('22','Belarbi',null),
('22','Ben Badis',null),
('22','Benachiba Chelia',null),
('22','Bir El Hammam',null),
('22','Boudjebaa El Bordj',null),
('22','Boukhanafis',null),
('22','Chettouane Belaila',null),
('22','Dhaya',null),
('22','El HaÃ§aiba',null),
('22','Hassi Dahou',null),
('22','Hassi Zehana',null),
('22','Lamtar',null),
('22','Makedra',null),
('22','Marhoum',null),
('22','M''Cid',null),
('22','Merine',null),
('22','Mezaourou',null),
('22','Mostefa Ben Brahim',null),
('22','Moulay Slissen',null),
('22','Oued Sebaa',null),
('22','Oued Sefioun',null),
('22','Oued Taourira',null),
('22','Ras El Ma',null),
('22','Redjem Demouche',null),
('22','Sehala Thaoura',null),
('22','Sfisef',null),
('22','Sidi Ali Benyoub',null),
('22','Sidi Ali Boussidi',null),
('22','Sidi Bel Abbes',null),
('22','Sidi Brahim',null),
('22','Sidi Chaib',null),
('22','Sidi Daho des Zairs',null),
('22','Sidi Hamadouche',null),
('22','Sidi Khaled',null),
('22','Sidi Lahcene',null),
('22','Sidi Yacoub',null),
('22','Tabia',null),
('22','Tafissour',null),
('22','Taoudmout',null),
('22','Teghalimet',null),
('22','Telagh',null),
('22','Tenira',null),
('22','Tessala',null),
('22','Tilmouni',null),
('22','Zerouala',null),
('23','Annaba',null),
('23','Berrahal',null),
('23','El Hadjar',null),
('23','Eulma',null),
('23','El Bouni',null),
('23','Oued El Aneb',null),
('23','Cheurfa',null),
('23','SeraÃ¯di',null),
('23','AÃ¯n Berda',null),
('23','ChetaÃ¯bi',null),
('23','Sidi Amar',null),
('23','Treat',null),
('24','AÃ¯n Ben Beida',null),
('24','AÃ¯n Larbi',null),
('24','AÃ¯n Makhlouf',null),
('24','AÃ¯n Reggada',null),
('24','AÃ¯n Sandel',null),
('24','Belkheir',null),
('24','Ben Djerrah',null),
('24','Beni Mezline',null),
('24','Bordj Sabath',null),
('24','Bouhachana',null),
('24','Bouhamdane',null),
('24','Bouati Mahmoud',null),
('24','Bouchegouf',null),
('24','Boumahra Ahmed',null),
('24','Dahouara',null),
('24','Djeballah Khemissi',null),
('24','El Fedjoudj',null),
('24','Guellat Bou Sbaa',null),
('24','Guelma',null),
('24','Hammam Debagh',null),
('24','Hammam N''Bail',null),
('24','HÃ©liopolis',null),
('24','Houari BoumÃ©diÃ¨ne',null),
('24','Khezarra',null),
('24','Medjez Amar',null),
('24','Medjez Sfa',null),
('24','Nechmaya',null),
('24','Oued Cheham',null),
('24','Oued Fragha',null),
('24','Oued Zenati',null),
('24','Ras El Agba',null),
('24','Roknia',null),
('24','Sellaoua Announa',null),
('24','Tamlouka',null),
('25','AÃ¯n Abid',null),
('25','AÃ¯n Smara',null),
('25','Beni Hamiden',null),
('25','Constantine',null),
('25','Didouche Mourad',null),
('25','El Khroub',null),
('25','Hamma Bouziane',null),
('25','Ibn Badis',null),
('25','Ibn Ziad',null),
('25','Messaoud Boudjriou',null),
('25','Ouled Rahmoune',null),
('25','Zighoud Youcef',null),
('26','AÃ¯n Boucif',null),
('26','AÃ¯n Ouksir',null),
('26','Aissaouia',null),
('26','Aziz',null),
('26','Baata',null),
('26','Benchicao',null),
('26','Beni Slimane',null),
('26','Berrouaghia',null),
('26','Bir Ben Laabed',null),
('26','Boghar',null),
('26','Bou Aiche',null),
('26','Bouaichoune',null),
('26','Bouchrahil',null),
('26','Boughezoul',null),
('26','Bouskene',null),
('26','Chahbounia',null),
('26','Chellalet El Adhaoura',null),
('26','Cheniguel',null),
('26','Derrag',null),
('26','Deux Bassins',null),
('26','Djouab',null),
('26','Draa Essamar',null),
('26','El Azizia',null),
('26','El Guelb El Kebir',null),
('26','El Hamdania',null),
('26','El Omaria',null),
('26','El Ouinet',null),
('26','Hannacha',null),
('26','Kef Lakhdar',null),
('26','Khams Djouamaa',null),
('26','Ksar Boukhari',null),
('26','Meghraoua',null),
('26','MÃ©dÃ©a',null),
('26','Moudjbar',null),
('26','Meftaha',null),
('26','Mezerana',null),
('26','Mihoub',null),
('26','Ouamri',null),
('26','Oued Harbil',null),
('26','Ouled Antar',null),
('26','Ouled Bouachra',null),
('26','Ouled Brahim',null),
('26','Ouled Deide',null),
('26','Ouled Hellal',null),
('26','Ouled Maaref',null),
('26','Oum El Djalil',null),
('26','Ouzera',null),
('26','Rebaia',null),
('26','Saneg',null),
('26','Sedraia',null),
('26','Seghouane',null),
('26','Si Mahdjoub',null),
('26','Sidi Damed',null),
('26','Sidi Errabia',null),
('26','Sidi Naamanez',null),
('26','Sidi Zahar',null),
('26','Sidi Ziane',null),
('26','Souagui',null),
('26','Tablat',null),
('26','Tafraout',null),
('26','Tamesguida',null),
('26','Tizi Mahdi',null),
('26','Tlatet Eddouar',null),
('26','Zoubiria',null),
('27','Abdelmalek Ramdane',null),
('27','Achaacha',null),
('27','AÃ¯n Boudinar',null),
('27','AÃ¯n Nouissy',null),
('27','AÃ¯n Sidi Cherif',null),
('27','AÃ¯n Tedles',null),
('27','Blad Touahria',null),
('27','Bouguirat',null),
('27','El Hassaine',null),
('27','Fornaka',null),
('27','Hadjadj',null),
('27','Hassi Mameche',null),
('27','Khadra',null),
('27','Kheireddine',null),
('27','Mansourah',null),
('27','Mesra',null),
('27','Mazagran',null),
('27','Mostaganem',null),
('27','Nekmaria',null),
('27','Oued El Kheir',null),
('27','Ouled Boughalem',null),
('27','Ouled Maallah',null),
('27','Safsaf',null),
('27','Sayada',null),
('27','Sidi Ali',null),
('27','Sidi Belattar',null),
('27','Sidi Lakhdar',null),
('27','Sirat',null),
('27','Souaflia',null),
('27','Sour',null),
('27','Stidia',null),
('27','Tazgait',null),
('28','AÃ¯n El Hadjel',null),
('28','AÃ¯n El Melh',null),
('28','AÃ¯n Errich',null),
('28','AÃ¯n Fares',null),
('28','AÃ¯n Khadra',null),
('28','Belaiba',null),
('28','Ben Srour',null),
('28','Beni Ilmane',null),
('28','Benzouh',null),
('28','Berhoum',null),
('28','Bir Foda',null),
('28','Bou SaÃ¢da',null),
('28','Bouti Sayah',null),
('28','Chellal',null),
('28','Dehahna',null),
('28','Djebel Messaad',null),
('28','El Hamel',null),
('28','El Houamed',null),
('28','Hammam Dhalaa',null),
('28','Khettouti Sed El Djir',null),
('28','Khoubana',null),
('28','Maadid',null),
('28','Maarif',null),
('28','Magra',null),
('28','M''Cif',null),
('28','Medjedel',null),
('28','Mohammed Boudiaf',null),
('28','M''Sila',null),
('28','M''Tarfa',null),
('28','Ouanougha',null),
('28','Ouled Addi Guebala',null),
('28','Ouled Atia',null),
('28','Ouled Derradj',null),
('28','Ouled Madhi',null),
('28','Ouled Mansour',null),
('28','Ouled Sidi Brahim',null),
('28','Ouled Slimane',null),
('28','Oultem',null),
('28','Sidi AÃ¯ssa',null)
on conflict (wilaya_code, name_fr) do update set
  name_ar = excluded.name_ar;

insert into public.communes (wilaya_code, name_fr, name_ar) values
('28','Sidi Ameur',null),
('28','Sidi Hadjeres',null),
('28','Sidi M''Hamed',null),
('28','Slim',null),
('28','Souamaa',null),
('28','Tamsa',null),
('28','Tarmount',null),
('28','Zarzour',null),
('29','AÃ¯n Fares',null),
('29','AÃ¯n Fekan',null),
('29','AÃ¯n Ferah',null),
('29','AÃ¯n Fras',null),
('29','AlaÃ¯mia',null),
('29','Aouf',null),
('29','Beniane',null),
('29','Bou Hanifia',null),
('29','Bou Henni',null),
('29','Chorfa',null),
('29','El Bordj',null),
('29','El Gaada',null),
('29','El Ghomri',null),
('29','El Guettana',null),
('29','El Keurt',null),
('29','El Menaouer',null),
('29','Ferraguig',null),
('29','Froha',null),
('29','Gharrous',null),
('29','Guerdjoum',null),
('29','Ghriss',null),
('29','Hachem',null),
('29','Hacine',null),
('29','Khalouia',null),
('29','Makdha',null),
('29','Mamounia',null),
('29','Maoussa',null),
('29','Mascara',null),
('29','Matemore',null),
('29','Mocta Douz',null),
('29','Mohammadia',null),
('29','Nesmoth',null),
('29','Oggaz',null),
('29','Oued El Abtal',null),
('29','Oued Taria',null),
('29','Ras El AÃ¯n Amirouche',null),
('29','Sedjerara',null),
('29','Sehailia',null),
('29','Sidi Abdeldjebar',null),
('29','Sidi Abdelmoumen',null),
('29','Sidi Kada',null),
('29','Sidi Boussaid',null),
('29','Sig',null),
('29','Tighennif',null),
('29','Tizi',null),
('29','Zahana',null),
('29','Zelmata',null),
('30','AÃ¯n Beida',null),
('30','Hassi Ben Abdellah',null),
('30','Hassi Messaoud',null),
('30','N''Goussa',null),
('30','Ouargla',null),
('30','Rouissat',null),
('30','Sidi Khouiled',null),
('31','Oran',null),
('31','Gdyel',null),
('31','Bir El Djir',null),
('31','Hassi Bounif',null),
('31','Es Senia',null),
('31','Arzew',null),
('31','Bethioua',null),
('31','Marsat El Hadjadj',null),
('31','AÃ¯n El Turk',null),
('31','El AnÃ§or',null),
('31','Oued Tlelat',null),
('31','Tafraoui',null),
('31','Sidi Chami',null),
('31','Boufatis',null),
('31','Mers El KÃ©bir',null),
('31','Bou Sfer',null),
('31','El Kerma',null),
('31','El Braya',null),
('31','Hassi Ben Okba',null),
('31','Ben Freha',null),
('31','Hassi Mefsoukh',null),
('31','Sidi Benyebka',null),
('31','Misserghin',null),
('31','Boutlelis',null),
('31','AÃ¯n El Kerma',null),
('31','AÃ¯n El Bia',null),
('32','El Bayadh',null),
('32','Rogassa',null),
('32','Stitten',null),
('32','Brezina',null),
('32','Ghassoul',null),
('32','Boualem',null),
('32','El Abiodh Sidi Cheikh',null),
('32','AÃ¯n El Orak',null),
('32','Arbaouat',null),
('32','Bougtoub',null),
('32','El Kheiter',null),
('32','Kef El Ahmar',null),
('32','Boussemghoun',null),
('32','Chellala',null),
('32','Kraakda',null),
('32','El Bnoud',null),
('32','Cheguig',null),
('32','Sidi Ameur',null),
('32','El Mehara',null),
('32','Tousmouline',null),
('32','Sidi Slimane',null),
('32','Sidi Tifour',null),
('33','Illizi',null),
('33','Debdeb',null),
('33','Bordj Omar Driss',null),
('33','In Amenas',null),
('34','AÃ¯n Taghrout',null),
('34','AÃ¯n Tesra',null),
('34','Belimour',null),
('34','Ben Daoud',null),
('34','Bir Kasdali',null),
('34','Bordj Bou Arreridj',null),
('34','Bordj GhÃ©dir',null),
('34','Bordj Zemoura',null),
('34','Colla',null),
('34','Djaafra',null),
('34','El Ach',null),
('34','El Achir',null),
('34','El Anseur',null),
('34','El Hamadia',null),
('34','El Main',null),
('34','El M''hir',null),
('34','Ghilassa',null),
('34','Haraza',null),
('34','Hasnaoua',null),
('34','Khelil',null),
('34','Ksour',null),
('34','Mansoura',null),
('34','Medjana',null),
('34','Ouled Brahem',null),
('34','Ouled Dahmane',null),
('34','Ouled Sidi Brahim',null),
('34','Rabta',null),
('34','Ras El Oued',null),
('34','Sidi Embarek',null),
('34','Tefreg',null),
('34','Taglait',null),
('34','Teniet En Nasr',null),
('34','Tassameurt',null),
('34','Tixter',null),
('35','Boumerdes',null),
('35','Boudouaou',null),
('35','Afir',null),
('35','Bordj Menaiel',null),
('35','Baghlia',null),
('35','Sidi Daoud',null),
('35','Naciria',null),
('35','Djinet',null),
('35','Issers',null),
('35','Zemmouri',null),
('35','Si Mustapha',null),
('35','Tidjelabine',null),
('35','Chabet el Ameur',null),
('35','Thenia',null),
('35','Timezrit',null),
('35','Corso',null),
('35','Ouled Moussa',null),
('35','Larbatache',null),
('35','Bouzegza Keddara',null),
('35','Taourga',null),
('35','Ouled Aissa',null),
('35','Ben Choud',null),
('35','Dellys',null),
('35','Ammal',null),
('35','Beni Amrane',null),
('35','Souk El Had',null),
('35','Boudouaou El Bahri',null),
('35','Ouled Hedadj',null),
('35','Leghata',null),
('35','Hammedi',null),
('35','Khemis El Khechna',null),
('35','El Kharrouba',null),
('36','AÃ¯n El Assel',null),
('36','AÃ¯n Kerma',null),
('36','Asfour',null),
('36','Ben Mehidi',null),
('36','Berrihane',null),
('36','Besbes',null),
('36','Bougous',null),
('36','Bouhadjar',null),
('36','Bouteldja',null),
('36','Chebaita Mokhtar',null),
('36','Chefia',null),
('36','Chihani',null),
('36','DrÃ©an',null),
('36','Echatt',null),
('36','El Aioun',null),
('36','El Kala',null),
('36','El Tarf',null),
('36','Hammam Beni Salah',null),
('36','Lac des Oiseaux',null),
('36','Oued Zitoun',null),
('36','Raml Souk',null),
('36','Souarekh',null),
('36','Zerizer',null),
('36','Zitouna',null),
('37','Oum el Assel',null),
('37','Tindouf',null),
('38','Ammari',null),
('38','Beni Chaib',null),
('38','Beni Lahcene',null),
('38','Boucaid',null),
('38','Bordj Bou Naama',null),
('38','Bordj El Emir Abdelkader',null),
('38','Khemisti',null),
('38','Larbaa',null),
('38','Lardjem',null),
('38','Layoune',null),
('38','Lazharia',null),
('38','Maacem',null),
('38','Melaab',null),
('38','Ouled Bessem',null),
('38','Sidi Abed',null),
('38','Sidi Boutouchent',null),
('38','Sidi Lantri',null),
('38','Sidi Slimane',null),
('38','Tamalaht',null),
('38','Theniet El Had',null),
('38','Tissemsilt',null),
('38','Youssoufia',null),
('39','El Oued',null),
('39','Robbah',null),
('39','Oued El Alenda',null),
('39','Bayadha',null),
('39','Nakhla',null),
('39','Guemar',null),
('39','Kouinine',null),
('39','Reguiba',null),
('39','Hamraia',null),
('39','Taghzout',null),
('39','Debila',null),
('39','Hassani Abdelkrim',null),
('39','Hassi Khalifa',null),
('39','Taleb Larbi',null),
('39','Douar El Ma',null),
('39','Sidi Aoun',null),
('39','Trifaoui',null),
('39','Magrane',null),
('39','Beni Guecha',null),
('39','Ourmas',null),
('39','El Ogla',null),
('39','Mih Ouansa',null),
('40','AÃ¯n Touila',null),
('40','Babar',null),
('40','Baghai',null),
('40','Bouhmama',null),
('40','Chechar',null),
('40','Chelia',null),
('40','Djellal',null),
('40','El Hamma',null),
('40','El Mahmal',null),
('40','El Oueldja',null),
('40','Ensigha',null),
('40','Kais',null),
('40','Khenchela',null),
('40','Khirane',null),
('40','M''Sara',null),
('40','M''Toussa',null),
('40','Ouled Rechache',null),
('40','Remila',null),
('40','Tamza',null),
('40','Taouzient',null),
('40','Yabous',null),
('41','Souk Ahras',null),
('41','Sedrata',null),
('41','Hanancha',null),
('41','Mechroha',null),
('41','Ouled Driss',null),
('41','Tiffech',null),
('41','Zaarouria',null),
('41','Taoura',null),
('41','Drea',null),
('41','Heddada',null),
('41','Khedara',null),
('41','Merahna',null),
('41','Ouled Moumene',null),
('41','Bir Bou Haouch',null),
('41','M''daourouch',null),
('41','Oum El Adhaim',null),
('41','AÃ¯n Zana',null),
('41','AÃ¯n Soltane',null),
('41','Ouillen',null),
('41','Sidi Fredj',null),
('41','Safel El Ouiden',null),
('41','Ragouba',null),
('41','Khemissa',null),
('41','Oued Keberit',null),
('41','Terraguelt',null),
('41','Zouabi',null),
('42','Tipaza',null),
('42','Menaceur',null),
('42','Larhat',null),
('42','Douaouda',null),
('42','Bourkika',null),
('42','Khemisti',null),
('42','Aghbal',null),
('42','Hadjout',null),
('42','Sidi Amar',null),
('42','Gouraya',null),
('42','Nador',null),
('42','Chaiba',null),
('42','AÃ¯n Tagourait',null),
('42','Cherchell',null),
('42','Damous',null),
('42','Merad',null),
('42','Fouka',null),
('42','Bou IsmaÃ¯l',null),
('42','Ahmar El AÃ¯n',null),
('42','Bouharoun',null),
('42','Sidi Ghiles',null),
('42','Messelmoun',null),
('42','Sidi Rached',null),
('42','KolÃ©a',null),
('42','Attatba',null),
('42','Sidi Semiane',null),
('42','Beni Milleuk',null),
('42','Hadjeret Ennous',null),
('43','Ahmed Rachedi',null),
('43','AÃ¯n Beida Harriche',null),
('43','AÃ¯n Mellouk',null),
('43','AÃ¯n Tine',null),
('43','Amira ArrÃ¨s',null),
('43','Benyahia Abderrahmane',null),
('43','Bouhatem',null),
('43','Chelghoum Laid',null),
('43','Chigara',null),
('43','Derradji Bousselah',null),
('43','El Mechira',null),
('43','Elayadi Barbes',null),
('43','Ferdjioua',null),
('43','Grarem Gouga',null),
('43','Hamala',null),
('43','Mila',null),
('43','Minar Zarza',null),
('43','Oued Athmania',null),
('43','Oued Endja',null),
('43','Oued Seguen',null),
('43','Ouled Khalouf',null),
('43','Rouached',null),
('43','Sidi Khelifa',null),
('43','Sidi Merouane',null),
('43','Tadjenanet',null),
('43','Tassadane Haddada',null),
('43','Teleghma',null),
('43','Terrai Bainen',null),
('43','Tessala LemtaÃ¯',null),
('43','Tiberguent',null),
('43','Yahia Beni Guecha',null),
('43','Zeghaia',null),
('44','AÃ¯n Defla',null),
('44','AÃ¯n Bouyahia',null),
('44','AÃ¯n Benian',null),
('44','AÃ¯n Lechiekh',null),
('44','AÃ¯n Soltane',null),
('44','AÃ¯n Torki',null),
('44','Arib',null),
('44','Bathia',null),
('44','Belaas',null),
('44','Ben Allal',null),
('44','Birbouche',null),
('44','Bir Ould Khelifa',null),
('44','Bordj Emir Khaled',null),
('44','Boumedfaa',null),
('44','Bourached',null),
('44','Djelida',null),
('44','Djemaa Ouled Cheikh',null),
('44','Djendel',null),
('44','El Abadia',null),
('44','El Amra',null),
('44','El Attaf',null),
('44','El Hassania',null),
('44','El Maine',null),
('44','Hammam Righa',null),
('44','Hoceinia',null),
('44','Khemis Miliana',null),
('44','Mekhatria',null),
('44','Miliana',null),
('44','Oued Chorfa',null),
('44','Oued Djemaa',null),
('44','Rouina',null),
('44','Sidi Lakhdar',null),
('44','Tacheta Zougagha',null),
('44','Tarik Ibn Ziad',null),
('44','Tiberkanine',null),
('44','Zeddine',null),
('45','NaÃ¢ma',null),
('45','Mecheria',null),
('45','AÃ¯n Sefra',null),
('45','Tiout',null),
('45','Sfissifa',null),
('45','Moghrar',null),
('45','Assela',null),
('45','Djeniene Bourezg',null),
('45','AÃ¯n Ben Khelil',null),
('45','Makman Ben Amer',null),
('45','Kasdir',null),
('45','El Biod',null),
('46','Aghlal',null),
('46','AÃ¯n El Arbaa',null),
('46','AÃ¯n Kihal',null),
('46','AÃ¯n TÃ©mouchent',null),
('46','AÃ¯n Tolba',null),
('46','Aoubellil',null),
('46','Beni Saf',null),
('46','Bouzedjar',null),
('46','Chaabat El Leham',null),
('46','Chentouf',null),
('46','El Amria',null),
('46','El Emir Abdelkader',null),
('46','El Malah',null),
('46','El Messaid',null),
('46','Hammam Bouhadjar',null),
('46','Hassasna',null),
('46','Hassi El Ghella',null),
('46','Oued Berkeche',null),
('46','Oued Sabah',null),
('46','Ouled Boudjemaa',null),
('46','Ouled Kihal',null),
('46','OulhaÃ§a El Gheraba',null),
('46','Sidi Ben Adda',null),
('46','Sidi Boumedienne',null),
('46','Sidi Ouriache',null),
('46','Sidi Safi',null),
('46','Tamzoura',null),
('46','Terga',null),
('47','Berriane',null),
('47','Bounoura',null),
('47','Dhayet Bendhahoua',null),
('47','El Atteuf',null),
('47','El Guerrara',null),
('47','GhardaÃ¯a',null),
('47','Mansoura',null),
('47','Metlili',null),
('47','Sebseb',null),
('47','Zelfana',null),
('48','AÃ¯n Rahma',null),
('48','AÃ¯n Tarek',null),
('48','Ammi Moussa',null),
('48','Belassel Bouzegza',null),
('48','Bendaoud',null),
('48','Beni Dergoun',null),
('48','Beni Zentis',null),
('48','Dar Ben Abdellah',null),
('48','Djidioua',null),
('48','El Guettar',null),
('48','El Hamadna',null),
('48','El Hassi',null),
('48','El Matmar',null),
('48','El Ouldja',null),
('48','Had Echkalla',null),
('48','Hamri',null),
('48','Kalaa',null),
('48','Lahlef',null),
('48','Mazouna',null),
('48','Mediouna',null),
('48','Mendes',null),
('48','Merdja Sidi Abed',null),
('48','Ouarizane',null),
('48','Oued Essalem',null),
('48','Oued Rhiou',null),
('48','Ouled Aiche',null),
('48','Oued El Djemaa',null),
('48','Ouled Sidi Mihoub',null),
('48','Ramka',null),
('48','Relizane',null),
('48','Sidi Khettab',null),
('48','Sidi Lazreg',null),
('48','Sidi M''Hamed Ben Ali',null),
('48','Sidi M''Hamed Benaouda',null),
('48','Sidi Saada',null),
('48','Souk El Had',null),
('48','Yellel',null),
('48','Zemmora',null),
('49','Charouine',null),
('49','Ksar Kaddour',null),
('49','Timimoun',null),
('49','Ouled SaÃ¯d',null),
('49','Tinerkouk',null),
('49','Deldoul',null),
('49','Metarfa',null),
('49','Aougrout',null),
('49','Talmine',null),
('49','Ouled AÃ¯ssa',null),
('50','Bordj Badji Mokhtar',null),
('50','Timiaouine',null),
('51','Besbes',null),
('51','Doucen',null),
('51','Ech ChaÃ¯ba',null),
('51','Ouled Djellal',null),
('51','Ras El Miaad',null),
('51','Sidi Khaled',null),
('52','Ouled Khoudir',null)
on conflict (wilaya_code, name_fr) do update set
  name_ar = excluded.name_ar;

insert into public.communes (wilaya_code, name_fr, name_ar) values
('52','Timoudi',null),
('52','BÃ©ni AbbÃ¨s',null),
('52','Beni Ikhlef',null),
('52','Igli',null),
('52','Tabelbala',null),
('52','El Ouata',null),
('52','Kerzaz',null),
('52','Ksabi',null),
('52','Tamtert',null),
('53','In Ghar',null),
('53','In Salah',null),
('53','Foggaret Ezzaouia',null),
('54','In Guezzam',null),
('54','Tin Zaouatine',null),
('55','Benaceur',null),
('55','Blidet Amor',null),
('55','El Allia',null),
('55','El Borma',null),
('55','El Hadjira',null),
('55','Megarine',null),
('55','M''Naguer',null),
('55','Nezla',null),
('55','Sidi Slimane',null),
('55','Taibet',null),
('55','Tamacine',null),
('55','Tebesbest',null),
('55','Touggourt',null),
('55','Zaouia El Abidia',null),
('56','Djanet',null),
('56','Bordj El Haouas',null),
('57','Still',null),
('57','M''Rara',null),
('57','Sidi Khellil',null),
('57','Tendla',null),
('57','El M''Ghair',null),
('57','Djamaa',null),
('57','Oum Touyour',null),
('57','Sidi Amrane',null),
('58','El Menia',null),
('58','Hassi Fehal',null),
('58','Hassi Gara',null)
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
    is_negotiable boolean not null default true,
    shipping_free boolean not null default false,
    exchange_after_delivery boolean not null default false,
    insurance_active boolean not null default false,
    declared_value numeric(12,2),
    weight_kg int default 1 check (weight_kg >= 0),
    height_cm int default 0 check (height_cm >= 0),
    width_cm int default 0 check (width_cm >= 0),
    length_cm int default 0 check (length_cm >= 0),
    allow_stopdesk boolean not null default true,
    category_id bigint references public.categories(id),
    category_slug text references public.categories(slug),
    condition text,
    brand text,
    size text,
    color text,
    search_tags text[] not null default '{}',
    search_keywords text,
    moderation_status text not null default 'approved',
    moderation_reason text,
    moderation_score numeric(6,4),
    moderation_labels jsonb,
    moderation_updated_at timestamptz,
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
alter table public.products
  add column if not exists is_negotiable boolean default true;
update public.products
  set is_negotiable = true
where is_negotiable is null;
alter table public.products
  alter column is_negotiable set default true;
alter table public.products
  alter column is_negotiable set not null;
alter table public.products
  add column if not exists allow_stopdesk boolean default true;
alter table public.products
  add column if not exists shipping_free boolean default false;
alter table public.products
  add column if not exists exchange_after_delivery boolean default false;
alter table public.products
  add column if not exists insurance_active boolean default false;
alter table public.products
  add column if not exists declared_value numeric(12,2);
alter table public.products
  add column if not exists weight_kg int default 1;
alter table public.products
  add column if not exists height_cm int default 0;
alter table public.products
  add column if not exists width_cm int default 0;
alter table public.products
  add column if not exists length_cm int default 0;
alter table public.products
  add column if not exists moderation_status text default 'approved';
alter table public.products
  add column if not exists moderation_reason text;
alter table public.products
  add column if not exists moderation_score numeric(6,4);
alter table public.products
  add column if not exists moderation_labels jsonb;
alter table public.products
  add column if not exists moderation_updated_at timestamptz;
alter table public.products
  add column if not exists search_tags text[] default '{}';
alter table public.products
  add column if not exists search_keywords text;
alter table public.products enable row level security;
drop policy if exists "products readable by all" on public.products;
drop policy if exists "products insert by seller" on public.products;
drop policy if exists "products update by owner" on public.products;
create policy "products readable by all" on public.products for select using (true);
create policy "products insert by seller" on public.products
  for insert with check (
    auth.uid() = owner_id
    and public.is_user_active(auth.uid())
  );
create policy "products update by owner" on public.products
  for update using (
    auth.uid() = owner_id
    and public.is_user_active(auth.uid())
  );
drop trigger if exists products_touch on public.products;
create trigger products_touch
  before update on public.products
  for each row execute procedure public.touch_updated_at();

-- Auto-archive products when stock reaches 0 (keep history)
create or replace function public.auto_archive_product()
returns trigger as $$
begin
  if new.stock_quantity is not null and new.stock_quantity <= 0 then
    new.is_archived = true;
    if new.status is distinct from 'sold' then
      new.status = 'sold';
    end if;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists products_auto_archive on public.products;
create trigger products_auto_archive
  before insert or update on public.products
  for each row execute procedure public.auto_archive_product();

create or replace function public.is_large_volume_product(
  p_title text,
  p_description text,
  p_category_slug text,
  p_weight_kg integer,
  p_height_cm integer,
  p_width_cm integer,
  p_length_cm integer
)
returns boolean
language plpgsql
immutable
as $$
declare
  txt text := lower(coalesce(p_title, '') || ' ' || coalesce(p_description, ''));
  slug text := lower(coalesce(p_category_slug, ''));
  volume integer := coalesce(p_height_cm, 0) * coalesce(p_width_cm, 0) * coalesce(p_length_cm, 0);
begin
  if coalesce(p_weight_kg, 0) > 15 then
    return true;
  end if;
  if coalesce(p_height_cm, 0) > 120
     or coalesce(p_width_cm, 0) > 120
     or coalesce(p_length_cm, 0) > 200 then
    return true;
  end if;
  if volume > 900000 then
    return true;
  end if;
  if slug ~ '(vehicle|car|moto|truck|furniture|appliance|electro)' then
    return true;
  end if;
  if txt ~ '(voiture|moto|camion|meuble|canape|armoire|frigo|refrigerateur|lave[- ]linge|machine[- ]a[- ]laver|climatiseur|lit|table|bureau)' then
    return true;
  end if;
  return false;
end;
$$;

create or replace function public.enforce_pickup_for_large_products()
returns trigger
language plpgsql
as $$
begin
  if public.is_large_volume_product(
    new.title,
    new.description,
    new.category_slug,
    new.weight_kg,
    new.height_cm,
    new.width_cm,
    new.length_cm
  ) then
    new.delivery_options := array['pickup']::text[];
    new.allow_stopdesk := false;
  end if;
  return new;
end;
$$;

drop trigger if exists products_enforce_pickup on public.products;
create trigger products_enforce_pickup
  before insert or update on public.products
  for each row execute procedure public.enforce_pickup_for_large_products();

create index if not exists products_owner_idx on public.products (owner_id);
create index if not exists products_category_slug_idx on public.products (category_slug);
create index if not exists products_category_id_idx on public.products (category_id);
create index if not exists products_status_created_idx on public.products (status, created_at desc);
create index if not exists products_moderation_status_idx on public.products (moderation_status);
create index if not exists products_search_tags_idx on public.products using gin (search_tags);
create index if not exists products_search_keywords_idx on public.products (search_keywords);

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
  last_validated_at timestamptz,
  last_validation_status text not null default 'unknown' check (last_validation_status in ('unknown','valid','invalid')),
  last_validation_error text,
  consecutive_failures integer not null default 0,
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
    )
    and coalesce(nullif(trim(s.last_validation_status), ''), 'unknown') <> 'invalid';
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
  v_shipping_free boolean := false;
  v_shipping_cost numeric;
  v_order_id bigint;
begin
  if v_buyer is null then
    raise exception 'auth required';
  end if;

  select owner_id, price, cost_price, stock_quantity, coalesce(shipping_free, false)
  into v_seller, v_price, v_cost, v_stock, v_shipping_free
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

  v_shipping_cost := case
    when v_shipping_free then 0
    else p_shipping_cost
  end;
  if not v_shipping_free and v_shipping_cost is null then
    raise exception 'shipping fee required';
  end if;
  if v_shipping_cost is not null and v_shipping_cost < 0 then
    raise exception 'invalid shipping fee';
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
    v_shipping_cost,
    coalesce(p_payment_method, 'cod'),
    case when coalesce(p_payment_method, 'cod') = 'cod' then 'pending' else 'paid' end,
    p_delivery_method,
    p_agreed_price,
    p_courier_id,
    p_courier_name,
    coalesce(p_agreed_price, v_price),
    v_cost,
    coalesce(p_fee_amount, 0),
    coalesce(v_shipping_cost, 0),
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

-- Buyer return tracking (NPAI/retours) --------------------------------------
create table if not exists public.buyer_return_events (
  id bigserial primary key,
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  order_id bigint not null references public.orders(id) on delete cascade,
  courier_id text,
  status text not null, -- returned_to_sender | not_claimed | refused | other
  returned_at timestamptz not null default now(),
  created_at timestamptz default now()
);
create unique index if not exists buyer_return_events_order_status_uniq
  on public.buyer_return_events (order_id, status);
create index if not exists buyer_return_events_buyer_returned_idx
  on public.buyer_return_events (buyer_id, returned_at desc);

create table if not exists public.buyer_return_stats (
  buyer_id uuid primary key references public.profiles(id) on delete cascade,
  returns_6m int not null default 0,
  returns_12m int not null default 0,
  last_return_at timestamptz,
  last_return_courier text,
  updated_at timestamptz default now()
);
create index if not exists buyer_return_stats_updated_idx
  on public.buyer_return_stats (updated_at desc);

alter table public.buyer_return_events enable row level security;
alter table public.buyer_return_stats enable row level security;
drop policy if exists "buyer return events service" on public.buyer_return_events;
create policy "buyer return events service" on public.buyer_return_events
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
drop policy if exists "buyer return stats service" on public.buyer_return_stats;
create policy "buyer return stats service" on public.buyer_return_stats
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

create or replace function public.refresh_buyer_return_stats()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
begin
  with latest as (
    select distinct on (buyer_id) buyer_id, courier_id, returned_at
    from public.buyer_return_events
    order by buyer_id, returned_at desc
  ),
  agg as (
    select
      buyer_id,
      count(*) filter (where returned_at >= now() - interval '6 months') as returns_6m,
      count(*) filter (where returned_at >= now() - interval '12 months') as returns_12m,
      max(returned_at) as last_return_at
    from public.buyer_return_events
    group by buyer_id
  )
  insert into public.buyer_return_stats (
    buyer_id,
    returns_6m,
    returns_12m,
    last_return_at,
    last_return_courier,
    updated_at
  )
  select
    agg.buyer_id,
    agg.returns_6m,
    agg.returns_12m,
    agg.last_return_at,
    latest.courier_id,
    now()
  from agg
  join latest on latest.buyer_id = agg.buyer_id
  on conflict (buyer_id) do update set
    returns_6m = excluded.returns_6m,
    returns_12m = excluded.returns_12m,
    last_return_at = excluded.last_return_at,
    last_return_courier = excluded.last_return_courier,
    updated_at = excluded.updated_at;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.refresh_buyer_return_stats() from public;
grant execute on function public.refresh_buyer_return_stats() to service_role;

create or replace function public.get_buyer_return_stats_for_seller()
returns table (
  buyer_id uuid,
  returns_6m int,
  returns_12m int,
  last_return_at timestamptz,
  last_return_courier text
)
language sql
security definer
set search_path = public
as $$
  with buyers as (
    select distinct buyer_id
    from public.orders
    where seller_id = auth.uid()
  )
  select s.buyer_id, s.returns_6m, s.returns_12m, s.last_return_at, s.last_return_courier
  from public.buyer_return_stats s
  join buyers b on b.buyer_id = s.buyer_id;
$$;
revoke all on function public.get_buyer_return_stats_for_seller() from public;
grant execute on function public.get_buyer_return_stats_for_seller() to authenticated;

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

-- Courier locations cache ----------------------------------------------------
create table if not exists public.courier_locations (
  id bigserial primary key,
  courier_key text not null,
  courier_id text,
  type text not null, -- wilaya | commune | stopdesk
  remote_id text not null,
  name_raw text not null,
  name_norm text not null,
  parent_remote_id text,
  wilaya_code text,
  extra jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create unique index if not exists courier_locations_uniq
  on public.courier_locations (courier_key, type, remote_id, parent_remote_id);
create index if not exists courier_locations_lookup_idx
  on public.courier_locations (courier_key, type, parent_remote_id);
create index if not exists courier_locations_updated_idx
  on public.courier_locations (updated_at desc);

alter table public.courier_locations enable row level security;
drop policy if exists "courier locations service" on public.courier_locations;
create policy "courier locations service" on public.courier_locations
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

-- Courier parcel rules ------------------------------------------------------
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
  ('zrexpress', 1, 60, 200, 200, 200, 8000000, 99999999, 5),
  ('guepex', 1, 60, 200, 200, 200, 8000000, 150000, 5)
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

-- Chat v2 (conversations/messages/reads) -------------------------------------
-- NOTE: Legacy chat cleanup removed to preserve history.

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
CREATE INDEX IF NOT EXISTS conv_last_message_idx
  ON public.conversations(last_message_at DESC, id DESC);

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
  deleted_at timestamptz,
  moderation_status text default 'approved',
  moderation_reason text,
  moderation_score numeric(6,4),
  moderation_labels jsonb,
  moderation_updated_at timestamptz
);
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS type text default 'text',
  ADD COLUMN IF NOT EXISTS payload jsonb,
  ADD COLUMN IF NOT EXISTS dedupe_key text,
  ADD COLUMN IF NOT EXISTS moderation_status text default 'approved',
  ADD COLUMN IF NOT EXISTS moderation_reason text,
  ADD COLUMN IF NOT EXISTS moderation_score numeric(6,4),
  ADD COLUMN IF NOT EXISTS moderation_labels jsonb,
  ADD COLUMN IF NOT EXISTS moderation_updated_at timestamptz;
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
    ORDER BY
      (c.order_id IS NULL) DESC,
      c.last_message_at DESC NULLS LAST,
      c.created_at DESC
    LIMIT 1;

    IF conv.id IS NOT NULL THEN
      UPDATE public.conversations
      SET buyer_hidden_at = NULL,
          seller_hidden_at = NULL,
          updated_at = now()
      WHERE id = conv.id;
      SELECT * INTO conv FROM public.conversations c WHERE c.id = conv.id;
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
  -- Serialize by thread key too, so two concurrent orders for the same
  -- buyer/seller/product cannot create duplicate canonical conversations.
  PERFORM pg_advisory_xact_lock(
    hashtext(
      'conv_thread:'
      || coalesce(ord.product_id::text, '')
      || ':'
      || coalesce(ord.buyer_id::text, '')
      || ':'
      || coalesce(ord.seller_id::text, '')
    )
  );

  -- Keep one canonical conversation per buyer/seller/product.
  -- Legacy per-order rooms are reused but no new per-order room is created.
  SELECT * INTO conv
  FROM public.conversations c
  WHERE c.product_id = ord.product_id
    AND c.buyer_id = ord.buyer_id
    AND c.seller_id = ord.seller_id
  ORDER BY
    (c.order_id IS NULL) DESC,
    c.last_message_at DESC NULLS LAST,
    c.created_at DESC
  LIMIT 1;

  IF conv.id IS NOT NULL THEN
    -- New order reactivates the thread for both sides.
    UPDATE public.conversations
    SET buyer_hidden_at = NULL,
        seller_hidden_at = NULL,
        updated_at = now()
    WHERE id = conv.id;

    -- If we selected a legacy order-specific room and no canonical room exists,
    -- normalize it to canonical (order_id = NULL).
    IF conv.order_id IS NOT NULL THEN
      BEGIN
        UPDATE public.conversations
        SET order_id = NULL,
            updated_at = now()
        WHERE id = conv.id;
      EXCEPTION
        WHEN unique_violation THEN
          -- Another canonical room exists; keep current room unchanged.
          NULL;
      END;
      SELECT * INTO conv
      FROM public.conversations c
      WHERE c.id = conv.id;
    END IF;

    RETURN conv;
  END IF;

    begin
      INSERT INTO public.conversations (
        product_id,
        buyer_id,
        seller_id,
        last_message_at,
        last_message_text
      ) VALUES (
        ord.product_id,
        ord.buyer_id,
        ord.seller_id,
        now(),
        NULL
      )
      RETURNING * INTO conv;
    exception
      when unique_violation then
        -- Canonical conversation already created by a concurrent tx.
        select *
          into conv
        from public.conversations c
        where c.product_id = ord.product_id
          and c.buyer_id = ord.buyer_id
          and c.seller_id = ord.seller_id
        order by
          (c.order_id is null) desc,
          c.last_message_at desc nulls last,
          c.created_at desc
        limit 1;
    end;

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
  IF NOT public.is_user_active(auth.uid()) THEN
    RAISE EXCEPTION 'account_suspended' USING errcode = '42501';
  END IF;
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

-- Auto-cancel stale orders (no bordereau after 3 days) + system chat message
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
  FOR INSERT WITH CHECK (
    auth.uid() IN (buyer_id, seller_id)
    AND public.is_user_active(auth.uid())
  );

DROP POLICY IF EXISTS conv_update ON public.conversations;
CREATE POLICY conv_update ON public.conversations
  FOR UPDATE USING (
    auth.uid() IN (buyer_id, seller_id)
    AND public.is_user_active(auth.uid())
  );

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
    AND public.is_user_active(auth.uid())
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
-- Backward compatibility for legacy offers table (pre-workflow columns).
alter table public.offers
  add column if not exists counter_amount numeric(12,2),
  add column if not exists agreed_amount numeric(12,2),
  add column if not exists counter_by uuid references public.profiles(id) on delete set null,
  add column if not exists responded_at timestamptz,
  add column if not exists updated_at timestamptz default now();
update public.offers
set updated_at = coalesce(updated_at, created_at, now())
where updated_at is null;
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

-- Offer workflow hardening (atomic actions + canonical chat thread) ---------
with ranked as (
  select
    id,
    row_number() over (
      partition by product_id, buyer_id
      order by created_at desc, id desc
    ) as rn
  from public.offers
  where status = 'pending'
)
update public.offers o
set status = 'cancelled',
    responded_at = coalesce(o.responded_at, now()),
    updated_at = now()
from ranked r
where o.id = r.id
  and r.rn > 1;

create unique index if not exists offers_pending_buyer_product_uniq
  on public.offers (product_id, buyer_id)
  where status = 'pending';

create or replace function public.emit_offer_system_message(
  p_product_id bigint,
  p_buyer_id uuid,
  p_seller_id uuid,
  p_offer_id bigint,
  p_event text,
  p_amount numeric default null,
  p_dedupe_key text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  conv public.conversations;
  msg public.messages;
  v_event text := lower(trim(coalesce(p_event, '')));
  v_text text;
  v_i18n text;
begin
  conv := public.ensure_conversation(p_product_id, p_buyer_id, p_seller_id);

  if v_event = 'created' then
    v_i18n := 'offer.system.created';
    v_text := 'Nouvelle offre: DA ' || coalesce(round(p_amount)::text, '0');
  elsif v_event = 'counter' then
    v_i18n := 'offer.system.counter';
    v_text := 'Contre-offre: DA ' || coalesce(round(p_amount)::text, '0');
  elsif v_event = 'accepted' then
    v_i18n := 'offer.system.accepted';
    v_text := 'Offre acceptee: DA ' || coalesce(round(p_amount)::text, '0');
  elsif v_event = 'rejected' then
    v_i18n := 'offer.system.rejected';
    v_text := 'Offre refusee';
  else
    v_i18n := 'offer.system.updated';
    v_text := 'Mise a jour offre';
  end if;

  if p_dedupe_key is null or p_dedupe_key = '' then
    insert into public.messages (
      conversation_id,
      sender_id,
      text,
      type,
      payload
    )
    values (
      conv.id,
      coalesce(auth.uid(), p_buyer_id),
      v_text,
      'system',
      jsonb_strip_nulls(
        jsonb_build_object(
          'i18n_key', v_i18n,
          'offer_id', p_offer_id,
          'event', v_event,
          'amount', p_amount,
          'actor_id', auth.uid()
        )
      )
    )
    returning * into msg;
  else
    insert into public.messages (
      conversation_id,
      sender_id,
      text,
      type,
      payload,
      dedupe_key
    )
    values (
      conv.id,
      coalesce(auth.uid(), p_buyer_id),
      v_text,
      'system',
      jsonb_strip_nulls(
        jsonb_build_object(
          'i18n_key', v_i18n,
          'offer_id', p_offer_id,
          'event', v_event,
          'amount', p_amount,
          'actor_id', auth.uid()
        )
      ),
      p_dedupe_key
    )
    on conflict (conversation_id, dedupe_key) do nothing
    returning * into msg;

    if msg.id is null then
      select * into msg
      from public.messages m
      where m.conversation_id = conv.id
        and m.dedupe_key = p_dedupe_key;
    end if;
  end if;

  if msg.id is not null then
    update public.conversations
    set last_message_at = msg.created_at,
        last_message_text = msg.text,
        updated_at = now()
    where id = conv.id;
  end if;
end;
$$;
revoke all on function public.emit_offer_system_message(bigint, uuid, uuid, bigint, text, numeric, text) from public;
grant execute on function public.emit_offer_system_message(bigint, uuid, uuid, bigint, text, numeric, text) to authenticated;

create or replace function public.make_offer(
  p_product_id bigint,
  p_amount numeric,
  p_message text default null
)
returns public.offers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer public.offers;
  v_product record;
  v_message text := nullif(left(coalesce(p_message, ''), 240), '');
  v_min_amount numeric := 1;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('offer_make:' || p_product_id::text || ':' || auth.uid()::text)
  );

  select p.id, p.owner_id, p.status, p.is_archived, p.stock_quantity, p.price, p.is_negotiable
    into v_product
  from public.products p
  where p.id = p_product_id
  for update;

  if v_product.id is null then
    raise exception 'product_missing' using errcode = 'P0002';
  end if;

  if v_product.owner_id = auth.uid() then
    raise exception 'cannot_offer_own_product' using errcode = '42501';
  end if;

  if coalesce(v_product.is_negotiable, true) = false then
    raise exception 'offer_not_negotiable' using errcode = '22023';
  end if;

  if coalesce(v_product.is_archived, false)
     or coalesce(v_product.stock_quantity, 0) <= 0
     or coalesce(v_product.status, 'active') <> 'active' then
    raise exception 'product_unavailable' using errcode = 'P0001';
  end if;

  v_min_amount := greatest(1::numeric, ceil(coalesce(v_product.price, 0::numeric) * 0.5));
  if p_amount < v_min_amount then
    raise exception 'offer_below_min_ratio'
      using errcode = '22023',
            detail = 'min_offer=' || v_min_amount::text,
            hint = 'offer must be at least 50% of product price';
  end if;

  update public.offers
  set status = 'cancelled',
      responded_at = coalesce(responded_at, now()),
      updated_at = now()
  where product_id = p_product_id
    and buyer_id = auth.uid()
    and status = 'pending';

  insert into public.offers (
    product_id,
    buyer_id,
    seller_id,
    status,
    amount,
    message,
    counter_amount,
    agreed_amount,
    counter_by,
    created_at,
    responded_at,
    updated_at
  )
  values (
    p_product_id,
    auth.uid(),
    v_product.owner_id,
    'pending',
    p_amount,
    v_message,
    null,
    null,
    null,
    now(),
    null,
    now()
  )
  returning * into v_offer;

  perform public.emit_offer_system_message(
    v_offer.product_id,
    v_offer.buyer_id,
    v_offer.seller_id,
    v_offer.id,
    'created',
    v_offer.amount,
    'offer:' || v_offer.id::text || ':created'
  );

  return v_offer;
end;
$$;
revoke all on function public.make_offer(bigint, numeric, text) from public;
grant execute on function public.make_offer(bigint, numeric, text) to authenticated;

create or replace function public.respond_offer(
  p_offer_id bigint,
  p_action text,
  p_amount numeric default null,
  p_message text default null
)
returns public.offers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer public.offers;
  v_action text := lower(trim(coalesce(p_action, '')));
  v_actor uuid := auth.uid();
  v_last_actor uuid;
  v_message text := nullif(left(coalesce(p_message, ''), 240), '');
  v_now timestamptz := now();
  v_agreed numeric;
begin
  if v_actor is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  select *
    into v_offer
  from public.offers
  where id = p_offer_id
  for update;

  if v_offer.id is null then
    raise exception 'offer_missing' using errcode = 'P0002';
  end if;

  if v_offer.status <> 'pending' then
    raise exception 'offer_not_pending' using errcode = 'P0001';
  end if;

  if v_actor not in (v_offer.buyer_id, v_offer.seller_id) then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  v_last_actor := coalesce(v_offer.counter_by, v_offer.buyer_id);
  if v_actor = v_last_actor then
    raise exception 'offer_waiting_other_party' using errcode = 'P0001';
  end if;

  if v_action in ('accept', 'accepted') then
    v_agreed := coalesce(p_amount, v_offer.counter_amount, v_offer.amount);
    if v_agreed is null or v_agreed <= 0 then
      raise exception 'invalid_amount' using errcode = '22023';
    end if;

    update public.offers
    set status = 'accepted',
        agreed_amount = v_agreed,
        responded_at = v_now,
        message = coalesce(v_message, message),
        updated_at = v_now
    where id = v_offer.id
    returning * into v_offer;

    update public.offers
    set status = 'rejected',
        responded_at = coalesce(responded_at, v_now),
        updated_at = v_now
    where product_id = v_offer.product_id
      and id <> v_offer.id
      and status = 'pending';

    perform public.emit_offer_system_message(
      v_offer.product_id,
      v_offer.buyer_id,
      v_offer.seller_id,
      v_offer.id,
      'accepted',
      v_agreed,
      'offer:' || v_offer.id::text || ':accepted'
    );

  elsif v_action in ('reject', 'rejected') then
    update public.offers
    set status = 'rejected',
        responded_at = v_now,
        message = coalesce(v_message, message),
        updated_at = v_now
    where id = v_offer.id
    returning * into v_offer;

    perform public.emit_offer_system_message(
      v_offer.product_id,
      v_offer.buyer_id,
      v_offer.seller_id,
      v_offer.id,
      'rejected',
      null,
      'offer:' || v_offer.id::text || ':rejected'
    );

  elsif v_action = 'counter' then
    if p_amount is null or p_amount <= 0 then
      raise exception 'invalid_amount' using errcode = '22023';
    end if;

    update public.offers
    set status = 'pending',
        counter_amount = p_amount,
        counter_by = v_actor,
        responded_at = v_now,
        message = coalesce(v_message, message),
        updated_at = v_now
    where id = v_offer.id
    returning * into v_offer;

    perform public.emit_offer_system_message(
      v_offer.product_id,
      v_offer.buyer_id,
      v_offer.seller_id,
      v_offer.id,
      'counter',
      p_amount,
      null
    );

  else
    raise exception 'invalid_action' using errcode = '22023';
  end if;

  return v_offer;
end;
$$;
revoke all on function public.respond_offer(bigint, text, numeric, text) from public;
grant execute on function public.respond_offer(bigint, text, numeric, text) to authenticated;

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
create unique index if not exists reports_product_reporter_uniq
  on public.reports(product_id, reporter_id);
create index if not exists reports_product_created_idx
  on public.reports(product_id, created_at desc);
alter table public.reports enable row level security;
drop policy if exists "reports select all" on public.reports;
drop policy if exists "reports insert own" on public.reports;
drop policy if exists "reports delete own" on public.reports;
create policy "reports select all" on public.reports
  for select using (true);
create policy "reports insert own" on public.reports
  for insert with check (
    auth.uid() = reporter_id
    and public.is_user_active(auth.uid())
    and exists (
      select 1 from public.products p
      where p.id = product_id
        and p.owner_id <> auth.uid()
    )
  );
create policy "reports delete own" on public.reports
  for delete using (auth.uid() = reporter_id);

create or replace function public.submit_listing_report(
  p_product_id bigint,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reporter uuid := auth.uid();
  v_owner uuid;
  v_count integer := 0;
  v_status text := 'approved';
  v_threshold constant integer := 10;
  v_reason text := left(coalesce(p_reason, ''), 500);
begin
  if v_reporter is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if not public.is_user_active(v_reporter) then
    raise exception 'account_suspended' using errcode = '42501';
  end if;

  select p.owner_id, coalesce(p.moderation_status, 'approved')
    into v_owner, v_status
  from public.products p
  where p.id = p_product_id;
  if v_owner is null then
    raise exception 'product_missing' using errcode = 'P0002';
  end if;
  if v_owner = v_reporter then
    raise exception 'self_report_forbidden' using errcode = '42501';
  end if;

  insert into public.reports (product_id, reporter_id, reason, created_at)
  values (p_product_id, v_reporter, nullif(v_reason, ''), now())
  on conflict (product_id, reporter_id)
  do update set reason = excluded.reason, created_at = now();

  select count(distinct reporter_id)
    into v_count
  from public.reports
  where product_id = p_product_id
    and created_at >= now() - interval '7 days';

  if v_count >= v_threshold then
    update public.products
    set moderation_status = 'masked',
        moderation_reason = coalesce(moderation_reason, 'auto_mask_reports'),
        moderation_score = greatest(coalesce(moderation_score, 0), 1),
        moderation_labels = coalesce(moderation_labels, '[]'::jsonb) || jsonb_build_array('reports_threshold'),
        moderation_updated_at = now()
    where id = p_product_id
      and coalesce(moderation_status, 'approved') = 'approved';
  end if;

  select coalesce(moderation_status, 'approved')
    into v_status
  from public.products
  where id = p_product_id;

  return jsonb_build_object(
    'ok', true,
    'reports_7d', v_count,
    'threshold', v_threshold,
    'status', v_status
  );
end;
$$;
revoke all on function public.submit_listing_report(bigint, text) from public;
grant execute on function public.submit_listing_report(bigint, text) to authenticated;

create or replace function public.admin_set_user_status(
  p_user_id uuid,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text := lower(coalesce(p_status, ''));
  v_reason text := nullif(left(coalesce(p_reason, ''), 300), '');
begin
  if not public.is_superadmin(auth.uid()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() and v_status <> 'active' then
    raise exception 'self_status_change_forbidden' using errcode = '42501';
  end if;
  if v_status not in ('active', 'suspended', 'banned') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  update public.profiles
  set status = v_status,
      updated_at = now(),
      preferences = coalesce(preferences, '{}'::jsonb) || jsonb_build_object(
        'admin_status_reason', v_reason,
        'admin_status_updated_at', now()
      )
  where id = p_user_id;
  if not found then
    raise exception 'user_missing' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.admin_set_user_status(uuid, text, text) from public;
grant execute on function public.admin_set_user_status(uuid, text, text) to authenticated;

create or replace function public.admin_set_product_moderation(
  p_product_id bigint,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text := lower(coalesce(p_status, ''));
  v_reason text := nullif(left(coalesce(p_reason, ''), 300), '');
begin
  if not public.is_superadmin(auth.uid()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if v_status not in ('approved', 'masked', 'blocked') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  update public.products
  set moderation_status = v_status,
      moderation_reason = v_reason,
      moderation_updated_at = now(),
      is_archived = case when v_status = 'blocked' then true else is_archived end,
      updated_at = now()
  where id = p_product_id;
  if not found then
    raise exception 'product_missing' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.admin_set_product_moderation(bigint, text, text) from public;
grant execute on function public.admin_set_product_moderation(bigint, text, text) to authenticated;

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

-- App error logs (client-side telemetry)
create table if not exists public.app_errors (
  id bigserial primary key,
  user_id uuid references public.profiles(id) on delete set null,
  message text not null,
  stack text,
  context jsonb default '{}'::jsonb,
  platform text,
  created_at timestamptz default now()
);
alter table public.app_errors enable row level security;
drop policy if exists "app errors insert own" on public.app_errors;
drop policy if exists "app errors select service" on public.app_errors;
drop policy if exists "app errors select admin" on public.app_errors;
create policy "app errors insert own" on public.app_errors
  for insert with check (auth.uid() = user_id or auth.uid() is not null);
create policy "app errors select service" on public.app_errors
  for select using (auth.role() = 'service_role');
create policy "app errors select admin" on public.app_errors
  for select using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin', 'superadmin')
    )
  );
create index if not exists app_errors_user_idx on public.app_errors (user_id, created_at desc);
create index if not exists app_errors_created_idx on public.app_errors (created_at desc);

-- Cleanup old app error logs (service-role only)
create or replace function public.cleanup_app_errors(p_days integer default 30)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'forbidden';
  end if;
  if p_days is null or p_days < 1 then
    p_days := 30;
  end if;
  delete from public.app_errors
  where created_at < now() - (p_days || ' days')::interval;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;
revoke all on function public.cleanup_app_errors(integer) from public;
grant execute on function public.cleanup_app_errors(integer) to service_role;

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
  -- Block only near-identical double-submit attempts (accidental double tap).
  -- Legit second orders with another courier/method should pass.
  if exists (
    select 1 from public.orders o
    where o.buyer_id = new.buyer_id
      and o.product_id = new.product_id
      and o.status in ('pending', 'paid', 'shipped')
      and o.created_at > now() - interval '20 seconds'
      and coalesce(o.courier_id, '') = coalesce(new.courier_id, '')
      and coalesce(o.delivery_method, '') = coalesce(new.delivery_method, '')
      and coalesce(o.shipping_option, '') = coalesce(new.shipping_option, '')
      and coalesce(o.shipping_address_id, -1) = coalesce(new.shipping_address_id, -1)
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

-- Seed courier ZR Express + Guepex if couriers table exists -----------------
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
      insert into public.couriers (code, name, contact, coverage)
      values ('guepex', 'Guepex', 'developer@guepex.com', 'National')
      on conflict (code) do update set name = excluded.name;
    exception when undefined_column then
      insert into public.couriers (code, name)
      values ('zrexpress', 'ZR Express')
      on conflict (code) do update set name = excluded.name;
      insert into public.couriers (code, name)
      values ('guepex', 'Guepex')
      on conflict (code) do update set name = excluded.name;
    end;
  end if;
end;
$$;

-- Cleanup mojibake location names after legacy seeds ------------------------
create or replace function public.fix_mojibake_text(p_value text)
returns text
language plpgsql
immutable
as $$
begin
  if p_value is null then
    return null;
  end if;
  if position(chr(195) in p_value) > 0
     or position(chr(194) in p_value) > 0
     or position(chr(65533) in p_value) > 0 then
    begin
      return convert_from(convert_to(p_value, 'LATIN1'), 'UTF8');
    exception
      when others then
        return p_value;
    end;
  end if;
  return p_value;
end;
$$;

update public.wilayas
set name_fr = public.fix_mojibake_text(name_fr),
    name_ar = public.fix_mojibake_text(name_ar)
where position(chr(195) in coalesce(name_fr, '')) > 0
   or position(chr(194) in coalesce(name_fr, '')) > 0
   or position(chr(65533) in coalesce(name_fr, '')) > 0
   or position(chr(195) in coalesce(name_ar, '')) > 0
   or position(chr(194) in coalesce(name_ar, '')) > 0
   or position(chr(65533) in coalesce(name_ar, '')) > 0;

-- Some rows become identical after decoding (ex: Ain encoded twice).
-- Keep one row per (wilaya_code, normalized_name_fr) before updating.
with normalized as (
  select
    c.id,
    c.wilaya_code,
    public.fix_mojibake_text(c.name_fr) as normalized_name_fr
  from public.communes c
),
ranked as (
  select
    n.id,
    row_number() over (
      partition by n.wilaya_code, n.normalized_name_fr
      order by
        case when c.name_fr = n.normalized_name_fr then 0 else 1 end,
        c.id
    ) as rn
  from normalized n
  join public.communes c on c.id = n.id
)
delete from public.communes c
using ranked r
where c.id = r.id
  and r.rn > 1;

update public.communes
set name_fr = public.fix_mojibake_text(name_fr),
    name_ar = public.fix_mojibake_text(name_ar)
where position(chr(195) in coalesce(name_fr, '')) > 0
   or position(chr(194) in coalesce(name_fr, '')) > 0
   or position(chr(65533) in coalesce(name_fr, '')) > 0
   or position(chr(195) in coalesce(name_ar, '')) > 0
   or position(chr(194) in coalesce(name_ar, '')) > 0
   or position(chr(65533) in coalesce(name_ar, '')) > 0;

drop function if exists public.fix_mojibake_text(text);





