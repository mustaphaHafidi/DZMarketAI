-- Cleanup mojibake names in wilayas/communes seeded with wrong encoding.

create or replace function public.fix_mojibake_text(p_value text)
returns text
language plpgsql
immutable
as $$
begin
  if p_value is null then
    return null;
  end if;

  if position(chr(195) in p_value) > 0
     or position(chr(194) in p_value) > 0
     or position(chr(65533) in p_value) > 0 then
    begin
      return convert_from(convert_to(p_value, 'LATIN1'), 'UTF8');
    exception
      when others then
        return p_value;
    end;
  end if;

  return p_value;
end;
$$;

update public.wilayas
set name_fr = public.fix_mojibake_text(name_fr),
    name_ar = public.fix_mojibake_text(name_ar)
where position(chr(195) in coalesce(name_fr, '')) > 0
   or position(chr(194) in coalesce(name_fr, '')) > 0
   or position(chr(65533) in coalesce(name_fr, '')) > 0
   or position(chr(195) in coalesce(name_ar, '')) > 0
   or position(chr(194) in coalesce(name_ar, '')) > 0
   or position(chr(65533) in coalesce(name_ar, '')) > 0;

-- Some rows become identical after decoding (ex: Ain encoded twice).
-- Keep one row per (wilaya_code, normalized_name_fr) before updating.
with normalized as (
  select
    c.id,
    c.wilaya_code,
    public.fix_mojibake_text(c.name_fr) as normalized_name_fr
  from public.communes c
),
ranked as (
  select
    n.id,
    row_number() over (
      partition by n.wilaya_code, n.normalized_name_fr
      order by
        case when c.name_fr = n.normalized_name_fr then 0 else 1 end,
        c.id
    ) as rn
  from normalized n
  join public.communes c on c.id = n.id
)
delete from public.communes c
using ranked r
where c.id = r.id
  and r.rn > 1;

update public.communes
set name_fr = public.fix_mojibake_text(name_fr),
    name_ar = public.fix_mojibake_text(name_ar)
where position(chr(195) in coalesce(name_fr, '')) > 0
   or position(chr(194) in coalesce(name_fr, '')) > 0
   or position(chr(65533) in coalesce(name_fr, '')) > 0
   or position(chr(195) in coalesce(name_ar, '')) > 0
   or position(chr(194) in coalesce(name_ar, '')) > 0
   or position(chr(65533) in coalesce(name_ar, '')) > 0;

drop function if exists public.fix_mojibake_text(text);
