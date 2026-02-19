-- Search tags for listing discoverability (AI/user assisted)
alter table public.products
  add column if not exists search_tags text[] default '{}';

alter table public.products
  add column if not exists search_keywords text;

create index if not exists products_search_tags_idx
  on public.products using gin (search_tags);

create index if not exists products_search_keywords_idx
  on public.products (search_keywords);

