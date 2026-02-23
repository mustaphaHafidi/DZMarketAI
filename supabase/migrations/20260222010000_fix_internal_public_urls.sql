-- Normalize legacy internal/public-IP URLs to the external API domain.
-- This prevents mixed-content failures in web (HTTPS app loading HTTP assets).

-- Products: fix old image URLs pointing to the server public IP over HTTP.
update public.products
set image_url = regexp_replace(
  image_url,
  '^http://91\.107\.239\.5:8000',
  'https://api.dzmarket.pro',
  'i'
)
where coalesce(image_url, '') ~* '^http://91\.107\.239\.5:8000';

-- Orders: fix old label URLs pointing to internal kong host/public IP.
update public.orders
set label_url = regexp_replace(
  label_url,
  '^https?://(kong|supabase-kong|91\.107\.239\.5)(:8000)?',
  'https://api.dzmarket.pro',
  'i'
)
where coalesce(label_url, '') ~*
  '^https?://(kong|supabase-kong|localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]|::1|91\.107\.239\.5)(:8000)?';

-- Keep shipments in sync with normalized order labels.
update public.shipments s
set label_url = o.label_url
from public.orders o
where s.order_id = o.id
  and coalesce(o.label_url, '') <> ''
  and coalesce(s.label_url, '') <> o.label_url;

