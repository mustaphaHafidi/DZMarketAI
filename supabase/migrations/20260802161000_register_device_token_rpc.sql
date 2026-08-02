create or replace function public.register_device_token(
  p_token text,
  p_platform text default 'unknown',
  p_locale text default 'fr'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'auth_required';
  end if;
  if nullif(btrim(p_token), '') is null then
    raise exception 'token_required';
  end if;

  insert into public.device_tokens (
    token,
    user_id,
    platform,
    locale,
    updated_at,
    last_seen_at
  )
  values (
    btrim(p_token),
    v_user_id,
    coalesce(nullif(btrim(p_platform), ''), 'unknown'),
    coalesce(nullif(btrim(p_locale), ''), 'fr'),
    now(),
    now()
  )
  on conflict (token) do update set
    user_id = excluded.user_id,
    platform = excluded.platform,
    locale = excluded.locale,
    updated_at = now(),
    last_seen_at = now();
end;
$$;

revoke all on function public.register_device_token(text, text, text) from public;
grant execute on function public.register_device_token(text, text, text) to authenticated;
