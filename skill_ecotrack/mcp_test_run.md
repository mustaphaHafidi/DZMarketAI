# MCP Playwright Test Run — Ecotrack (Web)

Date: 2026-02-09
App: DZMarket (web release) @ http://127.0.0.1:9105
Accounts:
- Buyer: test@gmail.com
- Seller: test2@gmail.com

## Scenario (buyer)
1) Buyer logs in.
2) Open product "xbox" (30 000 DA).
3) Choose delivery: COD.
4) Choose courier: **Ecotrack**.
5) Fill recipient details:
   - Nom/Prénom: Test / Test
   - Phone: 0664589785
   - Wilaya: Mila
   - Commune: Mila
   - Daïra: Mila
   - Address: cite 2
   - Product list: Produit #26
   - COD price: 300
   - Weight/Dimensions: 2kg, 30x30x30
6) Accept terms.
7) Confirm order.
8) App redirects to chat room.

## Scenario (seller)
9) Seller logs in → Mes ventes.
10) Find **Commande 78** (Ecotrack).
11) Click **Générer bordereau + expédier**.
12) Open chat for the order and open label.

## Results
- Order created: ✅ (order id **78**)
- Buyer chat shows system message:
  - "Commande enregistree, en attente de validation vendeur. Statut: En attente" ✅
- Seller can generate bordereau: ✅
- Seller chat shows shipped system message with tracking:
  - "Commande expediee. Statut: Expediee Tracking: EC1NOC260209182000" ✅
- Label opens in new tab (seller): ✅
- Buyer sees status/tracking only (no label button): ✅

## Notes
- The message flow is now correct after the dedupe index fix.

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

