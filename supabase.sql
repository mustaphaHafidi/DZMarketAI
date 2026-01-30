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
  ('browse', 'ar', 'ØªØµÙØ­'),
  ('orders', 'fr', 'Commandes'),
  ('orders', 'ar', 'Ø§Ù„Ø·Ù„Ø¨Ø§Øª'),
  ('chat', 'fr', 'Chat'),
  ('chat', 'ar', 'Ø¯Ø±Ø¯Ø´Ø©')
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
('women','Femmes','Femmes','نساء',null,10,true,'woman'),
('men','Hommes','Hommes','رجال',null,20,true,'man'),
('kids','Enfants','Enfants','أطفال',null,30,true,'child_care'),
('home','Maison','Maison','المنزل',null,40,true,'home'),
('beauty','Beauté & Santé','Beauté & Santé','الجمال والصحة',null,50,true,'spa'),
('electronics','Électronique','Électronique','إلكترونيات',null,60,true,'devices'),
('sports','Sport & Outdoor','Sport & Outdoor','رياضة وخارجية',null,70,true,'sports_soccer'),
('media','Livres & Divertissement','Livres & Divertissement','كتب وترفيه',null,80,true,'menu_book'),
('toys','Jouets & Jeux','Jouets & Jeux','ألعاب',null,90,true,'toys'),
('other','Autres','Autres','أخرى',null,100,true,'category')
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
('women-clothing','Vêtements','Vêtements','ملابس',(select id from public.categories where slug='women'),1,true,'checkroom'),
('women-shoes','Chaussures','Chaussures','أحذية',(select id from public.categories where slug='women'),2,true,'hiking'),
('women-bags','Sacs','Sacs','حقائب',(select id from public.categories where slug='women'),3,true,'work'),
('women-accessories','Accessoires','Accessoires','إكسسوارات',(select id from public.categories where slug='women'),4,true,'watch'),
('women-jewelry','Bijoux','Bijoux','مجوهرات',(select id from public.categories where slug='women'),5,true,'diamond'),
('women-lingerie','Lingerie','Lingerie','ملابس داخلية',(select id from public.categories where slug='women'),6,true,'local_mall')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- MEN
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('men-clothing','Vêtements','Vêtements','ملابس',(select id from public.categories where slug='men'),1,true,'checkroom'),
('men-shoes','Chaussures','Chaussures','أحذية',(select id from public.categories where slug='men'),2,true,'hiking'),
('men-accessories','Accessoires','Accessoires','إكسسوارات',(select id from public.categories where slug='men'),3,true,'watch'),
('men-bags','Sacs','Sacs','حقائب',(select id from public.categories where slug='men'),4,true,'work'),
('men-watches','Montres','Montres','ساعات',(select id from public.categories where slug='men'),5,true,'watch')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- KIDS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('kids-baby','Bébé (0-24 mois)','Bébé (0-24 mois)','رضع',(select id from public.categories where slug='kids'),1,true,'child_friendly'),
('kids-clothing','Vêtements','Vêtements','ملابس',(select id from public.categories where slug='kids'),2,true,'checkroom'),
('kids-shoes','Chaussures','Chaussures','أحذية',(select id from public.categories where slug='kids'),3,true,'hiking'),
('kids-accessories','Accessoires','Accessoires','إكسسوارات',(select id from public.categories where slug='kids'),4,true,'backpack'),
('kids-school','École','École','لوازم مدرسية',(select id from public.categories where slug='kids'),5,true,'school')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- HOME
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('home-furniture','Meubles','Meubles','أثاث',(select id from public.categories where slug='home'),1,true,'weekend'),
('home-decor','Décoration','Décoration','ديكور',(select id from public.categories where slug='home'),2,true,'auto_awesome'),
('home-kitchen','Cuisine','Cuisine','مطبخ',(select id from public.categories where slug='home'),3,true,'kitchen'),
('home-textiles','Textiles','Textiles','منسوجات',(select id from public.categories where slug='home'),4,true,'curtains'),
('home-appliances','Électroménager','Électroménager','أجهزة منزلية',(select id from public.categories where slug='home'),5,true,'microwave')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- BEAUTY
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('beauty-makeup','Maquillage','Maquillage','مكياج',(select id from public.categories where slug='beauty'),1,true,'brush'),
('beauty-skincare','Soins de la peau','Soins de la peau','عناية بالبشرة',(select id from public.categories where slug='beauty'),2,true,'face'),
('beauty-hair','Cheveux','Cheveux','الشعر',(select id from public.categories where slug='beauty'),3,true,'content_cut'),
('beauty-fragrance','Parfums','Parfums','عطور',(select id from public.categories where slug='beauty'),4,true,'local_florist'),
('beauty-wellness','Bienêtre','Bienêtre','عناية وصحة',(select id from public.categories where slug='beauty'),5,true,'favorite')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- ELECTRONICS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('electronics-phones','Téléphones','Téléphones','هواتف',(select id from public.categories where slug='electronics'),1,true,'smartphone'),
('electronics-computers','Ordinateurs','Ordinateurs','حواسيب',(select id from public.categories where slug='electronics'),2,true,'laptop'),
('electronics-tablets','Tablettes','Tablettes','أجهزة لوحية',(select id from public.categories where slug='electronics'),3,true,'tablet'),
('electronics-audio','Audio','Audio','صوتيات',(select id from public.categories where slug='electronics'),4,true,'headphones'),
('electronics-gaming','Gaming','Gaming','ألعاب',(select id from public.categories where slug='electronics'),5,true,'sports_esports'),
('electronics-accessories','Accessoires','Accessoires','إكسسوارات',(select id from public.categories where slug='electronics'),6,true,'cable')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- SPORTS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('sports-clothing','Vêtements de sport','Vêtements de sport','ملابس رياضية',(select id from public.categories where slug='sports'),1,true,'sports'),
('sports-shoes','Chaussures de sport','Chaussures de sport','أحذية رياضية',(select id from public.categories where slug='sports'),2,true,'hiking'),
('sports-equipment','Équipement','Équipement','معدات',(select id from public.categories where slug='sports'),3,true,'fitness_center'),
('sports-bikes','Vélos','Vélos','دراجات',(select id from public.categories where slug='sports'),4,true,'pedal_bike'),
('sports-outdoor','Camping & Outdoor','Camping & Outdoor','تخييم وخارجية',(select id from public.categories where slug='sports'),5,true,'terrain')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- MEDIA
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('media-books','Livres','Livres','كتب',(select id from public.categories where slug='media'),1,true,'menu_book'),
('media-movies','Films & Séries','Films & Séries','أفلام ومسلسلات',(select id from public.categories where slug='media'),2,true,'movie'),
('media-music','Musique','Musique','موسيقى',(select id from public.categories where slug='media'),3,true,'music_note'),
('media-games','Jeux vidéo','Jeux vidéo','ألعاب فيديو',(select id from public.categories where slug='media'),4,true,'sports_esports')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- TOYS
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('toys-figures','Figurines','Figurines','مجسمات',(select id from public.categories where slug='toys'),1,true,'smart_toy'),
('toys-boardgames','Jeux de société','Jeux de société','ألعاب جماعية',(select id from public.categories where slug='toys'),2,true,'casino'),
('toys-construction','Construction','Construction','تركيب وبناء',(select id from public.categories where slug='toys'),3,true,'construction'),
('toys-baby','Jouets bébé','Jouets bébé','ألعاب للرضع',(select id from public.categories where slug='toys'),4,true,'child_friendly')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- OTHER
insert into public.categories (slug, name, name_fr, name_ar, parent_id, sort_order, is_active, icon) values
('other-services','Services','Services','خدمات',(select id from public.categories where slug='other'),1,true,'support_agent'),
('other-collectibles','Collections','Collections','مقتنيات',(select id from public.categories where slug='other'),2,true,'collections'),
('other-misc','Divers','Divers','متنوع',(select id from public.categories where slug='other'),3,true,'more_horiz')
on conflict (slug) do update set name=excluded.name, name_fr=excluded.name_fr, name_ar=excluded.name_ar, parent_id=excluded.parent_id, sort_order=excluded.sort_order, is_active=excluded.is_active, icon=excluded.icon;

-- Quick check
-- select slug, name_fr, parent_id from public.categories order by parent_id nulls first, sort_order;

-- Seed wilayas (FR/AR)
insert into public.wilayas (code, name_fr, name_ar) values
('01','Adrar','أدرار'),
('02','Chlef','الشلف'),
('03','Laghouat','الأغواط'),
('04','Oum El Bouaghi','أم البواقي'),
('05','Batna','باتنة'),
('06','Bejaia','بجاية'),
('07','Biskra','بسكرة'),
('08','Bechar','بشار'),
('09','Blida','البليدة'),
('10','Bouira','البويرة'),
('11','Tamanrasset','تمنراست'),
('12','Tebessa','تبسة'),
('13','Tlemcen','تلمسان'),
('14','Tiaret','تيارت'),
('15','Tizi Ouzou','تيزي وزو'),
('16','Alger','الجزائر'),
('17','Djelfa','الجلفة'),
('18','Jijel','جيجل'),
('19','Setif','سطيف'),
('20','Saida','سعيدة'),
('21','Skikda','سكيكدة'),
('22','Sidi Bel Abbes','سيدي بلعباس'),
('23','Annaba','عنابة'),
('24','Guelma','قالمة'),
('25','Constantine','قسنطينة'),
('26','Medea','المدية'),
('27','Mostaganem','مستغانم'),
('28','M''Sila','المسيلة'),
('29','Mascara','معسكر'),
('30','Ouargla','ورقلة'),
('31','Oran','وهران'),
('32','El Bayadh','البيض'),
('33','Illizi','إليزي'),
('34','Bordj Bou Arreridj','برج بوعريريج'),
('35','Boumerdes','بومرداس'),
('36','El Tarf','الطارف'),
('37','Tindouf','تندوف'),
('38','Tissemsilt','تيسمسيلت'),
('39','El Oued','الوادي'),
('40','Khenchela','خنشلة'),
('41','Souk Ahras','سوق أهراس'),
('42','Tipaza','تيبازة'),
('43','Mila','ميلة'),
('44','Ain Defla','عين الدفلى'),
('45','Naama','النعامة'),
('46','Ain Temouchent','عين تموشنت'),
('47','Ghardaia','غرداية'),
('48','Relizane','غليزان'),
('49','El M''Ghair','المغير'),
('50','El Meniaa','المنيعة'),
('51','Ouled Djellal','أولاد جلال'),
('52','Bordj Baji Mokhtar','برج باجي مختار'),
('53','Beni Abbes','بني عباس'),
('54','Timimoun','تيميمون'),
('55','Touggourt','تقرت'),
('56','Djanet','جانت'),
('57','In Salah','عين صالح'),
('58','In Guezzam','عين قزام')
on conflict (code) do update set
  name_fr = excluded.name_fr,
  name_ar = excluded.name_ar;
-- Seed communes (minimal placeholder list; replace with full dataset when available)
insert into public.communes (wilaya_code, name_fr, name_ar) values
('01','Adrar','أدرار'),
('02','Chlef','الشلف'),
('03','Laghouat','الأغواط'),
('04','Oum El Bouaghi','أم البواقي'),
('05','Batna','باتنة'),
('06','Bejaia','بجاية'),
('07','Biskra','بسكرة'),
('08','Bechar','بشار'),
('09','Blida','البليدة'),
('10','Bouira','البويرة'),
('11','Tamanrasset','تمنراست'),
('12','Tebessa','تبسة'),
('13','Tlemcen','تلمسان'),
('14','Tiaret','تيارت'),
('15','Tizi Ouzou','تيزي وزو'),
('16','Alger Centre','الجزائر الوسطى'),
('17','Djelfa','الجلفة'),
('18','Jijel','جيجل'),
('19','Setif','سطيف'),
('20','Saida','سعيدة'),
('21','Skikda','سكيكدة'),
('22','Sidi Bel Abbes','سيدي بلعباس'),
('23','Annaba','عنابة'),
('24','Guelma','قالمة'),
('25','Constantine','قسنطينة'),
('26','Medea','المدية'),
('27','Mostaganem','مستغانم'),
('28','M''Sila','المسيلة'),
('29','Mascara','معسكر'),
('30','Ouargla','ورقلة'),
('31','Oran','وهران'),
('32','El Bayadh','البيض'),
('33','Illizi','إليزي'),
('34','Bordj Bou Arreridj','برج بوعريريج'),
('35','Boumerdes','بومرداس'),
('36','El Tarf','الطارف'),
('37','Tindouf','تندوف'),
('38','Tissemsilt','تيسمسيلت'),
('39','El Oued','الوادي'),
('40','Khenchela','خنشلة'),
('41','Souk Ahras','سوق أهراس'),
('42','Tipaza','تيبازة'),
('43','Mila','ميلة'),
('44','Ain Defla','عين الدفلى'),
('45','Naama','النعامة'),
('46','Ain Temouchent','عين تموشنت'),
('47','Ghardaia','غرداية'),
('48','Relizane','غليزان'),
('49','El M''Ghair','المغير'),
('50','El Meniaa','المنيعة'),
('51','Ouled Djellal','أولاد جلال'),
('52','Bordj Baji Mokhtar','برج باجي مختار'),
('53','Beni Abbes','بني عباس'),
('54','Timimoun','تيميمون'),
('55','Touggourt','تقرت'),
('56','Djanet','جانت'),
('57','In Salah','عين صالح'),
('58','In Guezzam','عين قزام')
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
drop policy if exists "seller delivery delete own" on public.seller_delivery_settings;
create policy "seller delivery select own" on public.seller_delivery_settings
  for select using (auth.uid() = owner_id);
create policy "seller delivery upsert own" on public.seller_delivery_settings
  for insert with check (auth.uid() = owner_id);
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
  select s.courier_id, c.name
  from public.seller_delivery_settings s
  join public.couriers c on c.code = s.courier_id
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
  p_fee_amount numeric
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
    'pending'
  ) returning id into v_order_id;

  update public.products
  set stock_quantity = stock_quantity - 1
  where id = p_product_id;

  return v_order_id;
end;
$$;
revoke all on function public.create_order(bigint, bigint, text, text, text, numeric, text, text, numeric, numeric) from public;
grant execute on function public.create_order(bigint, bigint, text, text, text, numeric, text, text, numeric, numeric) to authenticated;

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

-- Messages -------------------------------------------------------------------
create table if not exists public.messages (
  id bigserial primary key,
  room_id text not null, -- "general" or "order:<id>" or "product:<id>:buyer:seller"
  content text not null,
  type text not null default 'text', -- text | label | image
  payload jsonb,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  read_by jsonb default '[]',
  created_at timestamptz default now()
);
alter table public.messages enable row level security;
drop policy if exists "messages select" on public.messages;
drop policy if exists "messages insert" on public.messages;
create policy "messages select" on public.messages
  for select using (
    room_id = 'general'
    or (
      room_id like 'order:%'
      and exists (
        select 1 from public.orders o
        where room_id = 'order:' || o.id
          and (
            auth.uid() = o.buyer_id
            or auth.uid() = o.seller_id
            or auth.uid() = o.driver_id
          )
      )
    )
    or (
      room_id like 'product:%'
      and exists (
        select 1 from public.products p
        where split_part(room_id, ':', 2)::bigint = p.id
          and (
            auth.uid() = p.owner_id
            or auth.uid() = split_part(room_id, ':', 3)::uuid
            or auth.uid() = split_part(room_id, ':', 4)::uuid
          )
      )
    )
  );
create policy "messages insert" on public.messages
  for insert with check (
    sender_id = auth.uid()
    and (
      room_id = 'general'
      or exists (
        select 1 from public.orders o
        where room_id = 'order:' || o.id
          and (
            auth.uid() = o.buyer_id
            or auth.uid() = o.seller_id
            or auth.uid() = o.driver_id
          )
      )
      or (
        room_id like 'product:%'
        and exists (
          select 1 from public.products p
          where split_part(room_id, ':', 2)::bigint = p.id
            and (
              auth.uid() = p.owner_id
              or auth.uid() = split_part(room_id, ':', 3)::uuid
              or auth.uid() = split_part(room_id, ':', 4)::uuid
            )
        )
      )
    )
  );
create index if not exists messages_room_created_idx on public.messages (room_id, created_at);

-- Chat rooms ----------------------------------------------------------------
create table if not exists public.chat_rooms (
  room_id text primary key,
  product_id bigint references public.products(id) on delete set null,
  buyer_id uuid references public.profiles(id) on delete set null,
  seller_id uuid references public.profiles(id) on delete set null,
  order_id bigint references public.orders(id) on delete set null,
  last_message text,
  last_message_type text,
  last_message_at timestamptz,
  last_sender_id uuid references public.profiles(id) on delete set null,
  unread_by_buyer integer not null default 0,
  unread_by_seller integer not null default 0,
  hidden_by text[] not null default '{}',
  deleted_by_buyer boolean not null default false,
  deleted_by_seller boolean not null default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.chat_rooms add column if not exists updated_at timestamptz default now();
alter table public.chat_rooms add column if not exists last_sender_id uuid;
alter table public.chat_rooms add column if not exists unread_by_buyer integer default 0;
alter table public.chat_rooms add column if not exists unread_by_seller integer default 0;
alter table public.chat_rooms add column if not exists hidden_by text[] default '{}';
alter table public.chat_rooms add column if not exists deleted_by_buyer boolean default false;
alter table public.chat_rooms add column if not exists deleted_by_seller boolean default false;
alter table public.chat_rooms enable row level security;
drop policy if exists "chat rooms read" on public.chat_rooms;
drop policy if exists "chat rooms insert" on public.chat_rooms;
drop policy if exists "chat rooms update" on public.chat_rooms;
create policy "chat rooms read" on public.chat_rooms
  for select using (auth.uid() = buyer_id or auth.uid() = seller_id);
create policy "chat rooms insert" on public.chat_rooms
  for insert with check (auth.uid() = buyer_id or auth.uid() = seller_id);
create policy "chat rooms update" on public.chat_rooms
  for update using (auth.uid() = buyer_id or auth.uid() = seller_id);
drop trigger if exists chat_rooms_touch on public.chat_rooms;
create trigger chat_rooms_touch
  before update on public.chat_rooms
  for each row execute procedure public.touch_updated_at();
create index if not exists chat_rooms_last_message_idx on public.chat_rooms (last_message_at desc);

-- Per-user visibility --------------------------------------------------------
create table if not exists public.chat_room_users (
  room_id text not null references public.chat_rooms(room_id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  deleted_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  primary key (room_id, user_id)
);
alter table public.chat_room_users enable row level security;
drop policy if exists "chat_room_users select own" on public.chat_room_users;
drop policy if exists "chat_room_users insert own" on public.chat_room_users;
drop policy if exists "chat_room_users update own" on public.chat_room_users;
drop policy if exists "chat_room_users insert by participants" on public.chat_room_users;
drop policy if exists "chat_room_users update by participants" on public.chat_room_users;
create policy "chat_room_users select own" on public.chat_room_users
  for select using (
    auth.uid() = user_id
    and exists (
      select 1 from public.chat_rooms r
      where r.room_id = chat_room_users.room_id
        and (r.buyer_id = auth.uid() or r.seller_id = auth.uid())
    )
  );
create policy "chat_room_users insert by participants" on public.chat_room_users
  for insert with check (
    exists (
      select 1 from public.chat_rooms r
      where r.room_id = chat_room_users.room_id
        and (r.buyer_id = auth.uid() or r.seller_id = auth.uid())
    )
  );
create policy "chat_room_users update by participants" on public.chat_room_users
  for update using (
    exists (
      select 1 from public.chat_rooms r
      where r.room_id = chat_room_users.room_id
        and (r.buyer_id = auth.uid() or r.seller_id = auth.uid())
    )
  );

drop view if exists public.chat_rooms_visible;
create view public.chat_rooms_visible as
select
  cru.user_id,
  cru.deleted_at,
  r.room_id,
  r.product_id,
  r.buyer_id,
  r.seller_id,
  r.order_id,
  r.last_message,
  r.last_message_type,
  r.last_message_at,
  r.last_sender_id,
  r.unread_by_buyer,
  r.unread_by_seller,
  r.hidden_by,
  r.deleted_by_buyer,
  r.deleted_by_seller,
  r.created_at,
  r.updated_at
from public.chat_room_users cru
join public.chat_rooms r on r.room_id = cru.room_id;


create index if not exists chat_room_users_deleted_idx
  on public.chat_room_users (user_id, deleted_at);

-- Backfill chat rooms from existing product messages.
insert into public.chat_rooms (room_id, product_id, buyer_id, seller_id, last_message, last_message_type, last_message_at)
select distinct on (m.room_id)
  m.room_id,
  split_part(m.room_id, ':', 2)::bigint as product_id,
  split_part(m.room_id, ':', 3)::uuid as buyer_id,
  split_part(m.room_id, ':', 4)::uuid as seller_id,
  m.content as last_message,
  m.type as last_message_type,
  m.created_at as last_message_at
from public.messages m
where m.room_id like 'product:%'
  and split_part(m.room_id, ':', 3) ~* '^[0-9a-f-]{36}$'
  and split_part(m.room_id, ':', 4) ~* '^[0-9a-f-]{36}$'
order by m.room_id, m.created_at desc
on conflict (room_id) do update set
  last_message = excluded.last_message,
  last_message_type = excluded.last_message_type,
  last_message_at = excluded.last_message_at;

create or replace function public.update_chat_room_last_message()
returns trigger as $$
declare
  v_buyer uuid;
  v_seller uuid;
  v_product bigint;
  v_order bigint;
begin
  if new.room_id like 'product:%' then
    if split_part(new.room_id, ':', 3) !~* '^[0-9a-f-]{36}$'
      or split_part(new.room_id, ':', 4) !~* '^[0-9a-f-]{36}$' then
      return new;
    end if;
    v_product := split_part(new.room_id, ':', 2)::bigint;
    v_buyer := split_part(new.room_id, ':', 3)::uuid;
    v_seller := split_part(new.room_id, ':', 4)::uuid;
  elsif new.room_id like 'order:%' then
    v_order := split_part(new.room_id, ':', 2)::bigint;
    select buyer_id, seller_id into v_buyer, v_seller
    from public.orders where id = v_order;
    if v_buyer is null or v_seller is null then
      return new;
    end if;
  else
    return new;
  end if;

  insert into public.chat_rooms (
    room_id,
    product_id,
    order_id,
    buyer_id,
    seller_id,
    last_message,
    last_message_type,
    last_message_at,
    last_sender_id
  )
  values (
    new.room_id,
    v_product,
    v_order,
    v_buyer,
    v_seller,
    new.content,
    new.type,
    new.created_at,
    new.sender_id
  )
  on conflict (room_id) do update set
    last_message = excluded.last_message,
    last_message_type = excluded.last_message_type,
    last_message_at = excluded.last_message_at,
    last_sender_id = excluded.last_sender_id,
    unread_by_buyer = case
      when new.sender_id = v_buyer then public.chat_rooms.unread_by_buyer
      else public.chat_rooms.unread_by_buyer + 1 end,
    unread_by_seller = case
      when new.sender_id = v_seller then public.chat_rooms.unread_by_seller
      else public.chat_rooms.unread_by_seller + 1 end,
    deleted_by_buyer = false,
    deleted_by_seller = false,
    hidden_by = array_remove(public.chat_rooms.hidden_by, new.sender_id::text);

  insert into public.chat_room_users (room_id, user_id, deleted_at)
  values (new.room_id, v_buyer, null), (new.room_id, v_seller, null)
  on conflict (room_id, user_id) do update set
    deleted_at = null,
    updated_at = now();

  return new;
end;
$$ language plpgsql;

create or replace function public.mark_chat_room_read(p_room_id text)
  returns void as $$
  begin
    update public.chat_rooms
    set unread_by_buyer = case when auth.uid() = buyer_id then 0 else unread_by_buyer end,
        unread_by_seller = case when auth.uid() = seller_id then 0 else unread_by_seller end
    where room_id = p_room_id;
  end;
$$ language plpgsql security definer;

create or replace function public.hide_chat_room(p_room_id text)
  returns void as $$
  begin
    update public.chat_rooms
    set deleted_by_buyer = case when auth.uid() = buyer_id then true else deleted_by_buyer end,
        deleted_by_seller = case when auth.uid() = seller_id then true else deleted_by_seller end,
        hidden_by = case
          when hidden_by @> array[auth.uid()::text] then hidden_by
          else array_append(hidden_by, auth.uid()::text)
        end
    where room_id = p_room_id;

    insert into public.chat_room_users (room_id, user_id, deleted_at)
    values (p_room_id, auth.uid(), now())
    on conflict (room_id, user_id) do update set
      deleted_at = now(),
      updated_at = now();
  end;
$$ language plpgsql security definer;

drop trigger if exists messages_chat_rooms_touch on public.messages;
create trigger messages_chat_rooms_touch
  after insert on public.messages
  for each row execute procedure public.update_chat_room_last_message();

create index if not exists chat_rooms_last_message_at_idx on public.chat_rooms (last_message_at desc);

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
drop policy if exists "chat_room_users insert by participants" on public.chat_room_users;
drop policy if exists "chat_room_users update by participants" on public.chat_room_users;
create policy "chat_room_users insert by participants" on public.chat_room_users
  for insert with check (
    exists (
      select 1 from public.chat_rooms r
      where r.room_id = chat_room_users.room_id
        and (r.buyer_id = auth.uid() or r.seller_id = auth.uid())
    )
  );
create policy "chat_room_users update by participants" on public.chat_room_users
  for update using (
    exists (
      select 1 from public.chat_rooms r
      where r.room_id = chat_room_users.room_id
        and (r.buyer_id = auth.uid() or r.seller_id = auth.uid())
    )
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
  if length(new.content) > 2000 then
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



