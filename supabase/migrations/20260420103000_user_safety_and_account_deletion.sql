-- User safety and account deletion initiation for App Store compliance.

create table if not exists public.user_reports (
  id bigserial primary key,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid not null references public.profiles(id) on delete cascade,
  source text not null default 'profile' check (source in ('profile', 'chat', 'listing')),
  reason text not null,
  created_at timestamptz not null default now(),
  constraint user_reports_not_self check (reporter_id <> reported_user_id)
);

create index if not exists user_reports_reported_created_idx
  on public.user_reports (reported_user_id, created_at desc);

alter table public.user_reports enable row level security;

drop policy if exists user_reports_select_own on public.user_reports;
drop policy if exists user_reports_insert_own on public.user_reports;

create policy user_reports_select_own on public.user_reports
  for select using (auth.uid() = reporter_id);

create policy user_reports_insert_own on public.user_reports
  for insert with check (
    auth.uid() = reporter_id
    and public.is_user_active(auth.uid())
    and reporter_id <> reported_user_id
  );

create or replace function public.submit_user_report(
  p_reported_user_id uuid,
  p_reason text default null,
  p_source text default 'profile'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := nullif(left(trim(coalesce(p_reason, '')), 500), '');
  v_source text := lower(trim(coalesce(p_source, 'profile')));
begin
  if auth.uid() is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  if p_reported_user_id is null or p_reported_user_id = auth.uid() then
    raise exception 'invalid_user' using errcode = '22023';
  end if;

  if v_reason is null then
    raise exception 'missing_reason' using errcode = '22023';
  end if;

  if v_source not in ('profile', 'chat', 'listing') then
    v_source := 'profile';
  end if;

  insert into public.user_reports (
    reporter_id,
    reported_user_id,
    source,
    reason
  ) values (
    auth.uid(),
    p_reported_user_id,
    v_source,
    v_reason
  );

  return jsonb_build_object(
    'status', 'reported',
    'reported_user_id', p_reported_user_id,
    'source', v_source
  );
end;
$$;

revoke all on function public.submit_user_report(uuid, text, text) from public;
grant execute on function public.submit_user_report(uuid, text, text) to authenticated;

create table if not exists public.account_deletion_requests (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  email text,
  reason text,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'rejected', 'cancelled')),
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists account_deletion_requests_pending_unique
  on public.account_deletion_requests (user_id)
  where status in ('pending', 'processing');

create index if not exists account_deletion_requests_status_idx
  on public.account_deletion_requests (status, requested_at desc);

alter table public.account_deletion_requests enable row level security;

drop policy if exists account_deletion_requests_select_own on public.account_deletion_requests;
drop policy if exists account_deletion_requests_insert_own on public.account_deletion_requests;

create policy account_deletion_requests_select_own on public.account_deletion_requests
  for select using (auth.uid() = user_id);

create policy account_deletion_requests_insert_own on public.account_deletion_requests
  for insert with check (auth.uid() = user_id);

drop trigger if exists account_deletion_requests_touch on public.account_deletion_requests;
create trigger account_deletion_requests_touch
  before update on public.account_deletion_requests
  for each row execute procedure public.touch_updated_at();

create or replace function public.submit_account_deletion_request(
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := nullif(left(trim(coalesce(p_reason, '')), 500), '');
  v_email text;
  v_existing_id bigint;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  select email
    into v_email
  from public.profiles
  where id = auth.uid();

  select id
    into v_existing_id
  from public.account_deletion_requests
  where user_id = auth.uid()
    and status in ('pending', 'processing')
  order by requested_at desc
  limit 1;

  if v_existing_id is not null then
    update public.account_deletion_requests
    set reason = coalesce(v_reason, reason),
        requested_at = now(),
        updated_at = now()
    where id = v_existing_id;
  else
    insert into public.account_deletion_requests (
      user_id,
      email,
      reason,
      status
    ) values (
      auth.uid(),
      v_email,
      v_reason,
      'pending'
    )
    returning id into v_existing_id;
  end if;

  update public.profiles
  set is_public = false,
      updated_at = now()
  where id = auth.uid();

  delete from public.device_tokens where user_id = auth.uid();

  return jsonb_build_object(
    'status', 'pending',
    'request_id', v_existing_id
  );
end;
$$;

revoke all on function public.submit_account_deletion_request(text) from public;
grant execute on function public.submit_account_deletion_request(text) to authenticated;
