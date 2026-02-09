# ZR Express - MCP Playwright E2E (Web)

## 1) Goal
Validate the ZR Express order flow after the latest updates:
- Buyer creates order with ZR Express.
- Shipping parameters are locked to seller-defined product settings.
- System messages appear in the order chat.
- Seller generates the label/bordereau without phone errors.

## 2) Prereqs
- Web app served at `http://127.0.0.1:9105/`.
- Seller has ZR Express configured in "Parametres transporteurs" (token validated).
- Test product: **ID 26** (owned by seller, in stock).
- Test accounts:
  - Buyer: `test@gmail.com`
  - Seller: `test2@gmail.com`
  - Passwords: keep out of repo.

## 3) Buyer flow (MCP)
1. Open the app (`http://127.0.0.1:9105/`).
2. Sign in as **buyer**.
3. Open product **ID 26**.
4. Tap **Acheter** -> choose **Livraison COD** -> choose **ZR Express**.
5. Fill receiver form:
   - First name / Last name: `Test` / `Test`
   - Phone: `0664589785` (local)
   - Daira: `M'Sila`
   - Address: `2 cite silmane amirat`
   - Wilaya: `M'Sila`
   - Commune: `M'Sila`
6. Confirm:
   - Phone preview shows `+213...` for ZR.
   - Shipping section is **read-only** and matches product settings
     (free shipping, exchange, insurance, declared value, weight, dimensions).
7. Accept terms and confirm order.
8. Verify: redirect to **order chat**.

## 4) Seller flow (MCP)
1. Sign out, then sign in as **seller**.
2. Profile -> **Mes ventes**.
3. Find the order for product **26**.
4. Tap **Generer bordereau + expedier**.
5. Verify:
   - No ZR error: "Phone_Number1 must be a valid international phone number".
   - Order status -> **Expedie**.
   - Chat shows system message "commande validee / bordereau genere".
   - Label link visible for seller (hidden for buyer).

## 5) Expected results
- No ZR phone validation error.
- Bordereau generated with tracking + label.
- System messages in chat:
  - "Commande enregistree, en attente de validation vendeur"
  - "Commande validee / bordereau genere"
- Order chat visible on both sides.

## 6) Last run (fill after test)
- Date/time: 2026-02-09
- Result: PASS
- Notes:
  - Buyer order created with ZR Express; redirect to order chat OK.
  - Phone preview normalized to +213.
  - Shipping fields locked to product values (read-only).
  - Seller generated bordereau without phone validation errors.
  - Chat shows 2 system messages (created + expediee) and label button for seller.
