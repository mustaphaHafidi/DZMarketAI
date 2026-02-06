1. Purpose
   - This document captures the Ecotrack API knowledge gathered via the official docs.
   - Use it to implement the carrier integration similar to Yalidine in DZMarket.

2. Base URL (TODO)
   - The docs use {{url}} placeholders.
   - Confirm the exact base URL for the environment (prod/test) before coding.
   - In Edge `create_shipment`, we support optional env `ECOTRACK_BASE_URL`.
     - If not set, fallback order: https://api.ecotrack.dz then https://ovred.ecotrack.dz.

3. Authentication
   - Use a token generated from the Ecotrack account.
   - Send it as Bearer token in the Authorization header.
   - Token validation endpoint:
     - GET {{url}}/api/v1/validate/token?api_token={{api_token}}
   - Possible responses:
     - INVALID_TOKEN
     - TOKEN_NOT_ALLOWED
     - VALID_TOKEN

4. Rate limits
   - 15,000 requests/day
   - 1,500 requests/hour
   - 50 requests/minute
   - Headers: X-RateLimit-Limit-*, X-RateLimit-Remaining-*, X-RateLimit-Reset-*
   - 429 Too Many Requests with Retry-After

5. Orders (Core)
   5.1 Create single order
     - POST {{url}}/api/v1/create/order
     - Params (query):
       - reference (optional, string)
       - nom_client (required, string)
       - telephone (required, numeric 9-10 digits)
       - telephone_2 (optional)
       - adresse (required, string)
       - code_postal (optional)
       - commune (required, string)
       - code_wilaya (required, integer 1-58)
       - montant (required, numeric)
       - remarque (optional)
       - produit (optional, string)
       - stock (optional, 0/1)
       - quantite (required if stock=1)
       - produit_a_recuperer (optional)
       - boutique (optional)
       - type (required, integer: 1 Livraison, 2 Echange, 3 PICKUP, 4 Recouvrement)
       - stop_desk (optional, 0 domicile, 1 STOP DESK)
       - weight (optional)
       - fragile (optional, 0/1)
       - gps_link (optional)
   5.2 Create multiple orders
     - POST {{url}}/api/v1/create/orders
     - Limit: 100 orders per request
     - Body: JSON with orders array

6. Order updates / validation / deletion
   - Update order (before validation only):
     - POST {{url}}/api/v1/update/order?tracking=...&reference&client&tel&tel2&adresse&code_postal&commune&wilaya&montant&remarque&product&boutique&type&stop_desk&fragile&gps_link
   - Delete order (before validation only):
     - DELETE {{url}}/api/v1/delete/order?tracking=...
   - Validate / ship order:
     - POST {{url}}/api/v1/valid/order?tracking=...&ask_collection
     - After this, updates/deletes are not allowed.

7. Label (Bordereau)
   - GET {{url}}/api/v1/get/order/label?tracking=...
   - Returns PDF label file.

8. Tracking and status
   - Add manual update:
     - POST {{url}}/api/v1/add/maj?tracking=...&content=...
   - Get updates list:
     - GET {{url}}/api/v1/get/maj?tracking=...
   - Get tracking history:
     - GET {{url}}/api/v1/get/tracking/info?tracking=...
   - Request return:
     - POST {{url}}/api/v1/ask/for/order/return?tracking=...
   - List orders by status:
     - GET {{url}}/api/v1/get/orders/status?api_token=...&trackings=...&status=...
     - Status values (examples): prete_a_expedier, en_livraison, livre_non_encaisse, encaisse_non_paye, retour_recu, annule, all
   - List orders (pagination):
     - GET {{url}}/api/v1/get/orders?page=...&start_date=Y-m-d&end_date=Y-m-d

9. Configuration helpers
   - Active wilayas:
     - GET {{url}}/api/v1/get/wilayas
   - Active communes:
     - GET {{url}}/api/v1/get/communes?wilaya_id=...
     - wilaya_id optional; range 1-58
   - Fees:
     - GET {{url}}/api/v1/get/fees
     - Returns tariffs per service type (livraison/pickup/echange/recouvrement/retour) with wilaya_id and stopdesk tariff.

10. Products
   - List products:
     - GET {{url}}/api/v1/get/products/list

11. Integration guidance (DZMarket)
   - Use seller-side action to create shipment and fetch label.
   - Store tracking + label_url in shipments (source of truth).
   - Emit system messages in order chat room after validation/label generation.
   - Use dedupe keys for system messages to avoid duplicates on retries.

12. Open questions (resolve before production)
   - Confirm exact base URL for prod and test environments.
   - Confirm whether Authorization header is always required or some endpoints accept api_token in query only.
   - Confirm mapping from app wilaya/commune naming to Ecotrack naming for stopdesk validation.
