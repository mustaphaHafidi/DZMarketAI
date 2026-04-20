alter table public.account_deletion_requests
  add column if not exists admin_note text,
  add column if not exists processed_by uuid references public.profiles(id) on delete set null,
  add column if not exists account_status_before text,
  add column if not exists account_status_after text;

create index if not exists account_deletion_requests_processed_by_idx
  on public.account_deletion_requests (processed_by, updated_at desc);
