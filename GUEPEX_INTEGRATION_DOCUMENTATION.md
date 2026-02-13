# GUEPEX_INTEGRATION_DOCUMENTATION

Last update: 2026-02-13
Status: Documentation only (no code changes)

## 1) Objective
Document the Guepex carrier API + webhooks end-to-end so it can be added later to DZMarket without starting from zero.

## 2) Sources reviewed (via MCP Playwright)
Main app and docs:
- https://guepex.app/app/
- https://guepex.app/app/dev/docs/api/index.php
- https://guepex.app/app/dev/docs/api/authentication.php
- https://guepex.app/app/dev/docs/api/ratelimits.php
- https://guepex.app/app/dev/docs/api/pagination.php
- https://guepex.app/app/dev/docs/api/parcels.php
- https://guepex.app/app/dev/docs/api/histories.php
- https://guepex.app/app/dev/docs/api/centers.php
- https://guepex.app/app/dev/docs/api/communes.php
- https://guepex.app/app/dev/docs/api/wilayas.php
- https://guepex.app/app/dev/docs/api/fees.php
- https://guepex.app/app/dev/docs/webhooks/index.php
- https://guepex.app/app/dev/docs/webhooks/eventsformat.php
- https://guepex.app/app/dev/docs/webhooks/retrypolicy.php
- https://guepex.app/app/dev/docs/webhooks/validateawebhook.php
- https://guepex.app/app/dev/docs/webhooks/secureyourwebhook.php

Developer contact shown in docs:
- developer@guepex.com

## 3) API overview
- API style: REST
- Base URL: `https://api.guepex.app/v1/`
- Content format: JSON responses
- Typical transport objects and naming are very close to Yalidine style.

## 4) Authentication
Headers required on API requests:
- `X-API-ID: <api_id>`
- `X-API-TOKEN: <api_token>`

DZMarket credential storage mapping (compatible with existing model):
- `seller_delivery_settings.api_key` -> Guepex API ID
- `seller_delivery_settings.api_secret` -> Guepex API TOKEN
- `seller_delivery_settings.courier_id` -> `guepex` (recommended code)

## 5) Rate limits (documented defaults)
- 5 requests / second
- 50 requests / minute
- 1000 requests / hour
- 10000 requests / day

Headers expose remaining quotas by window (second/minute/hour/day). If exceeded, API returns 429.

## 6) Pagination
Standard query params:
- `page`
- `page_size` (docs mention up to 1000)

Response includes:
- `has_more`
- `total_data`
- `data`
- `links` (self/before/next)

## 7) Endpoint catalog

### 7.1 Parcels
Main endpoints:
- `GET /v1/parcels`
- `GET /v1/parcels/:tracking`
- `POST /v1/parcels`
- `PATCH /v1/parcels/:tracking`
- `DELETE /v1/parcels/:tracking`
- `DELETE /v1/parcels/?tracking=...`

Common filters:
- `tracking`
- `order_id`
- `to_wilaya_id`
- `is_stopdesk`
- `freeshipping`
- `last_status`
- date filters (`date_creation`, `date_last_status`)
- `fields`, `order_by`, `asc`/`desc`

Important business constraints from docs:
- Edit allowed only when parcel is in preparation state.
- Delete allowed only in preparation state.
- `price` and `declared_value` are documented with max range (up to 150000).
- If `is_stopdesk=true`, `stopdesk_id` is required.
- If `has_exchange=true`, `product_to_collect` is required.

Create payload (high-level fields used in docs):
- receiver identity: `firstname`, `familyname`, `contact_phone`, `address`
- route: `from_wilaya_name`, `to_wilaya_name`, `to_commune_name`
- parcel info: `product_list`, `price`, `do_insurance`, `declared_value`, `height`, `width`, `length`, `weight`
- delivery options: `freeshipping`, `is_stopdesk`, `stopdesk_id`, `has_exchange`, `product_to_collect`
- business id: `order_id`

Create response (key fields for integration):
- `success`
- `order_id`
- `tracking`
- `import_id`
- `label` (single label URL)
- `labels` (bulk labels URL)
- `message`

### 7.2 Histories (tracking timeline)
Endpoints:
- `GET /v1/histories`
- `GET /v1/histories/:tracking`

Useful filters:
- `tracking`
- `status`
- `reason`
- `date_status`
- `fields`, `order_by`, `asc`/`desc`

Useful response fields:
- `date_status`
- `tracking`
- `status`
- `reason`
- `center_id`, `center_name`
- `wilaya_id`, `wilaya_name`
- `commune_id`, `commune_name`

### 7.3 Centers / Communes / Wilayas
Location endpoints:
- `GET /v1/centers`
- `GET /v1/centers/:center_id`
- `GET /v1/communes`
- `GET /v1/communes/:id`
- `GET /v1/wilayas`
- `GET /v1/wilayas/:id`

Usage in DZMarket:
- Populate stopdesk list (`centers`)
- Validate destination territory (`communes`, `wilayas`)
- Normalize IDs/names for shipping selection

### 7.4 Fees
Endpoint:
- `GET /v1/fees/?from_wilaya_id=<id>&to_wilaya_id=<id>`

Fields include:
- `retour_fee`
- `cod_percentage`
- `insurance_percentage`
- `oversize_fee`
- per-commune prices (`express_home`, `express_desk`, etc.)

Weight logic documented:
- billable weight uses volumetric vs actual weight (take larger)
- extra fee applies above threshold (docs example around 5 KG)

## 8) Webhooks overview

### 8.1 Event types
Docs list these webhook event types:
- `parcel_created`
- `parcel_edited`
- `parcel_deleted`
- `parcel_status_updated`
- `parcel_payment_updated`

### 8.2 Payload shape
Top-level structure:
- `type`
- `events[]`

Each event item contains:
- `event_id` (use for dedupe)
- `occurred_at`
- `data` (event-specific payload)

### 8.3 CRC validation
Docs require endpoint challenge-response:
- request contains `subscribe` and `crc_token`
- endpoint must return the exact `crc_token`

If CRC validation fails repeatedly, webhook can be disabled.

### 8.4 Signature verification
Docs indicate an HMAC-SHA256 signature header (naming in docs still mentions Yalidine style). Verify signature using:
- raw request body
- webhook secret key
- compare computed digest vs received signature

### 8.5 Retry policy
If endpoint does not return HTTP 200 fast enough (docs mention <=10s), retries happen with exponential-ish delays and final automatic disable after the last attempt.

## 9) DZMarket mapping proposal (design level only)

### 9.1 Courier code and credential mapping
- Add carrier code: `guepex`
- Reuse existing credential fields:
  - `api_key` = API ID
  - `api_secret` = API TOKEN

### 9.2 Shipment creation mapping
From DZMarket selection -> Guepex payload:
- buyer/seller names/phones/address -> receiver block fields
- wilaya/commune destination -> `to_wilaya_name` + `to_commune_name`
- stopdesk flow -> `is_stopdesk=true` + `stopdesk_id`
- home flow -> `is_stopdesk=false`
- dimensions/weight/insurance/value -> same numeric fields

Expected create outputs to store:
- `tracking_number` <- `tracking`
- `label_url` <- `label` (or signed copy if downloaded)
- `orders.status` -> `shipped` when label exists

### 9.3 Tracking sync mapping
Use `GET /histories` (or by tracking) in runner to:
- append shipment timeline events
- post deduped chat system events
- detect return/not-claimed/failure states

## 10) Integration test plan (manual, before coding)
1. Auth smoke: test API ID/TOKEN on `wilayas`.
2. Territory load: fetch wilayas + communes + centers.
3. Create parcel home delivery.
4. Create parcel stopdesk delivery.
5. Validate returned tracking and label URL.
6. Pull histories until status updates appear.
7. Verify fee endpoint for route and overweight.
8. Configure webhook endpoint and pass CRC challenge.
9. Send webhook test events from Guepex dashboard.
10. Validate signature and dedupe with `event_id`.

## 11) Risks and points to confirm with Guepex before production
1. Header naming inconsistency in webhook docs (`X_YALIDINE_SIGNATURE` wording in Guepex docs).
2. Some examples still use `yal-` tracking style; confirm whether Guepex tracking prefix is always this or not guaranteed.
3. Confirm maximum parcel dimensions/weight and hard validation errors at API level.
4. Confirm phone format rules for all Algerian prefixes and landline handling.
5. Confirm webhook retention window and exact failure disable rules.
6. Confirm SLA and incident contact path beyond email.

## 12) Go/No-Go checklist for implementation phase
Go only when all are confirmed:
- API credential validation works from DZMarket backend.
- At least one successful end-to-end label generation in sandbox/real account.
- Histories sync provides reliable status transitions.
- Webhook CRC + signature validation stable.
- Error handling for 429/5xx fully tested.

---
This document is intentionally documentation-only.
No application code, SQL, or function logic was changed in this step.
