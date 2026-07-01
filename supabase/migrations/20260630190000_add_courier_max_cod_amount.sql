alter table public.courier_parcel_rules
  add column if not exists max_cod_amount numeric(12,2) not null default 99999999
  check (max_cod_amount >= 0);

update public.courier_parcel_rules
set max_cod_amount = case courier_code
  when 'ecotrack' then 150000
  when 'zrexpress' then 150000
  when 'guepex' then 150000
  else 99999999
end,
updated_at = now()
where coalesce(max_cod_amount, 0) <> case courier_code
  when 'ecotrack' then 150000
  when 'zrexpress' then 150000
  when 'guepex' then 150000
  else 99999999
end;
