-- Add Guepex courier seeds and parcel constraints.

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
) values (
  'guepex',
  1,
  60,
  200,
  200,
  200,
  8000000,
  150000,
  5
)
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

do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'couriers'
  ) then
    begin
      insert into public.couriers (code, name, contact, coverage)
      values ('guepex', 'Guepex', 'developer@guepex.com', 'National')
      on conflict (code) do update set name = excluded.name;
    exception
      when undefined_column then
        insert into public.couriers (code, name)
        values ('guepex', 'Guepex')
        on conflict (code) do update set name = excluded.name;
    end;
  end if;
end;
$$;
