-- Job runner + secret rotation helpers

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

-- Rotate encrypted courier secrets (service_role only)
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
