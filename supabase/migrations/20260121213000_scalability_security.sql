-- Scalability + security hardening: rate limiting, anti-spam, audit, queues

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
