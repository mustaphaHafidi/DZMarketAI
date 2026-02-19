-- Restore storage RLS policies for product/message/avatar uploads after DB restores.
-- Idempotent: safe to re-run.

alter table if exists storage.objects enable row level security;
alter table if exists storage.buckets enable row level security;

insert into storage.buckets (id, name, public)
values ('products', 'products', true)
on conflict (id) do update
set name = excluded.name, public = excluded.public;

insert into storage.buckets (id, name, public)
values ('messages', 'messages', true)
on conflict (id) do update
set name = excluded.name, public = excluded.public;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update
set name = excluded.name, public = excluded.public;

insert into storage.buckets (id, name, public)
values ('labels', 'labels', false)
on conflict (id) do update
set name = excluded.name, public = excluded.public;

drop policy if exists "product images public read" on storage.objects;
drop policy if exists "product images upload" on storage.objects;
drop policy if exists "product images delete own" on storage.objects;

create policy "product images public read" on storage.objects
  for select using (bucket_id = 'products');

create policy "product images upload" on storage.objects
  for insert with check (
    bucket_id = 'products'
    and auth.role() in ('authenticated', 'service_role')
  );

create policy "product images delete own" on storage.objects
  for delete using (
    bucket_id = 'products'
    and auth.uid() = owner
  );

drop policy if exists "message images public read" on storage.objects;
drop policy if exists "message images upload" on storage.objects;
drop policy if exists "message images delete own" on storage.objects;

create policy "message images public read" on storage.objects
  for select using (bucket_id = 'messages');

create policy "message images upload" on storage.objects
  for insert with check (
    bucket_id = 'messages'
    and auth.role() in ('authenticated', 'service_role')
  );

create policy "message images delete own" on storage.objects
  for delete using (
    bucket_id = 'messages'
    and auth.uid() = owner
  );

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
