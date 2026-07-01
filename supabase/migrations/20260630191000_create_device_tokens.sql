create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null default 'android',
  locale text not null default 'fr',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

alter table public.device_tokens
  add column if not exists locale text not null default 'fr';

alter table public.device_tokens
  add column if not exists updated_at timestamptz not null default now();

alter table public.device_tokens
  add column if not exists last_seen_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'device_tokens_platform_check'
  ) then
    alter table public.device_tokens
      add constraint device_tokens_platform_check
      check (platform in ('android', 'ios', 'web', 'unknown'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'device_tokens_locale_check'
  ) then
    alter table public.device_tokens
      add constraint device_tokens_locale_check
      check (locale in ('fr', 'ar'));
  end if;
end $$;

create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id, updated_at desc);

alter table public.device_tokens enable row level security;

drop policy if exists device_tokens_select_own on public.device_tokens;
create policy device_tokens_select_own
  on public.device_tokens
  for select
  using (auth.uid() = user_id);

drop policy if exists device_tokens_insert_own on public.device_tokens;
create policy device_tokens_insert_own
  on public.device_tokens
  for insert
  with check (auth.uid() = user_id);

drop policy if exists device_tokens_update_own on public.device_tokens;
create policy device_tokens_update_own
  on public.device_tokens
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists device_tokens_delete_own on public.device_tokens;
create policy device_tokens_delete_own
  on public.device_tokens
  for delete
  using (auth.uid() = user_id);

grant select, insert, update, delete on public.device_tokens to authenticated;

drop trigger if exists device_tokens_touch on public.device_tokens;
create trigger device_tokens_touch
  before update on public.device_tokens
  for each row execute procedure public.touch_updated_at();
