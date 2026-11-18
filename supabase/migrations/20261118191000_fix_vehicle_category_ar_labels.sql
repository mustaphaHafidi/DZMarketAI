-- Correct the Arabic labels seeded with a legacy encoding issue. This is
-- additive to the already-applied category migration and changes no IDs,
-- hierarchy, RLS policy, or listing data.
update public.categories
set name_ar = case slug
  when 'vehicles' then U&'\\0645\\0631\\0643\\0628\\0627\\062A'
  when 'vehicles-cars' then U&'\\0633\\064A\\0627\\0631\\0627\\062A'
  when 'vehicles-motorcycles' then U&'\\062F\\0631\\0627\\062C\\0627\\062A \\0646\\0627\\0631\\064A\\0629 \\0648\\0633\\0643\\0648\\062A\\0631'
  when 'vehicles-utility' then U&'\\0645\\0631\\0643\\0628\\0627\\062A \\0646\\0641\\0639\\064A\\0629'
  when 'vehicles-trucks' then U&'\\0634\\0627\\062D\\0646\\0627\\062A'
  when 'vehicles-equipment' then U&'\\0622\\0644\\064A\\0627\\062A \\062B\\0642\\064A\\0644\\0629'
  when 'vehicles-boats' then U&'\\0642\\0648\\0627\\0631\\0628'
  else name_ar
end
where slug in (
  'vehicles',
  'vehicles-cars',
  'vehicles-motorcycles',
  'vehicles-utility',
  'vehicles-trucks',
  'vehicles-equipment',
  'vehicles-boats'
);
