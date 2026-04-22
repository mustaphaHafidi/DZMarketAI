create index if not exists seller_delivery_settings_validation_status_idx
  on public.seller_delivery_settings (owner_id, last_validation_status);
