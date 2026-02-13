1. Purpose
   - This document captures Ecotrack API knowledge and the DZMarketAI mapping.

2. Base URL
   - Docs use {{url}} placeholders.
   - Edge create_shipment supports optional ECOTRACK_BASE_URL.
   - Fallback order: https://api.ecotrack.dz then https://ovred.ecotrack.dz.

3. Authentication
   - Token generated from Ecotrack account.
   - Send as Bearer token in Authorization header.
   - Token validation endpoint:
     - GET {{url}}/api/v1/validate/token?api_token={{api_token}}
   - Possible responses: INVALID_TOKEN, TOKEN_NOT_ALLOWED, VALID_TOKEN.

4. Rate limits
   - 15,000 requests/day, 1,500/hour, 50/minute.
   - 429 with Retry-After.

5. Orders (Core)
   5.1 Create single order
     - POST {{url}}/api/v1/create/order
     - Params: reference, nom_client, telephone, telephone_2, adresse, commune, code_wilaya, montant, produit, type, stop_desk, weight, etc.
   5.2 Create multiple orders
     - POST {{url}}/api/v1/create/orders (limit 100)

6. Updates / Validation
   - Update order (before validation only): POST /api/v1/update/order?tracking=...
   - Delete order (before validation only): DELETE /api/v1/delete/order?tracking=...
   - Validate/ship: POST /api/v1/valid/order?tracking=...&ask_collection

7. Labels
   - GET /api/v1/get/order/label?tracking=...

8. Tracking
   - POST /api/v1/add/maj?tracking=...&content=...
   - GET /api/v1/get/maj?tracking=...
   - GET /api/v1/get/tracking/info?tracking=...
   - Status codes observed in tracking history:
     - order_information_received_by_carrier
     - picked
     - accepted_by_carrier
     - dispatched_to_driver
     - attempt_delivery
     - return_asked
     - return_in_transit
     - Return_received
     - livred
     - encaissed
     - payed
   - Return-related endpoints:
     - POST /api/v1/ask/for/order/return?tracking=...
     - GET /api/v1/get/orders?page=...&start_date=YYYY-MM-DD&end_date=YYYY-MM-DD

9. Locations (wilayas/communes)
   - GET /api/v1/get/wilayas
   - GET /api/v1/get/communes?wilaya_id=...
   - GET /api/v1/get/fees (tarifs + stopdesk)

10. DZMarketAI mapping
   - validate-courier Edge validates token before save/update.
   - courier-locations Edge loads wilayas/communes for buyer based on seller credentials.
   - create_shipment Edge uses service_role, updates shipments + orders, posts system messages.
   - Label visible for seller only in chat; buyer sees status/tracking only.

11. Open questions
   - Confirm exact base URL per environment.
   - Confirm if Authorization header is mandatory for all endpoints.
   - Confirm mapping wilaya/commune naming for stopdesk validation.

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

