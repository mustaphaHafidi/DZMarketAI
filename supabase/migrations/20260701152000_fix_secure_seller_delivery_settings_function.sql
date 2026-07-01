create or replace function public.get_seller_delivery_settings_secure(
  p_owner uuid,
  p_courier_id text
)
returns table (
  courier_id text,
  owner_id uuid,
  api_key text,
  api_secret text,
  sender_id text,
  extra jsonb
)
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
    s.courier_id,
    s.owner_id,
    coalesce(
      s.api_key,
      case
        when v_key is not null and v_key <> ''
          then extensions.pgp_sym_decrypt(s.api_key_enc, v_key)::text
      end
    ),
    coalesce(
      s.api_secret,
      case
        when v_key is not null and v_key <> ''
          then extensions.pgp_sym_decrypt(s.api_secret_enc, v_key)::text
      end
    ),
    s.sender_id,
    s.extra
  from public.seller_delivery_settings s
  where s.owner_id = p_owner
    and s.courier_id = p_courier_id;
end;
$$;

revoke all on function public.get_seller_delivery_settings_secure(uuid, text) from public;
grant execute on function public.get_seller_delivery_settings_secure(uuid, text) to service_role;
