-- Normalize legacy avatar and product public-storage URLs to the external API
-- domain. Use explicit host replacements to keep the backfill deterministic.

update public.profiles
set avatar_url = replace(
  avatar_url,
  'https://maumwzbvzbcamvlivqpe.supabase.co',
  'https://api.dzmarket.pro'
)
where coalesce(avatar_url, '') like
  'https://maumwzbvzbcamvlivqpe.supabase.co/%';

update public.products
set image_url = replace(
  image_url,
  'http://91.107.239.5:8000',
  'https://api.dzmarket.pro'
)
where coalesce(image_url, '') like 'http://91.107.239.5:8000/%';

update public.products
set image_urls = array(
  select case
    when u like 'http://91.107.239.5:8000/%' then replace(
      u,
      'http://91.107.239.5:8000',
      'https://api.dzmarket.pro'
    )
    when u like 'https://maumwzbvzbcamvlivqpe.supabase.co/%' then replace(
      u,
      'https://maumwzbvzbcamvlivqpe.supabase.co',
      'https://api.dzmarket.pro'
    )
    else u
  end
  from unnest(coalesce(image_urls, '{}'::text[])) as u
)
where exists (
  select 1
  from unnest(coalesce(image_urls, '{}'::text[])) as u
  where u like 'http://91.107.239.5:8000/%'
     or u like 'https://maumwzbvzbcamvlivqpe.supabase.co/%'
);
