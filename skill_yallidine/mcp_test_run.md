# MCP Playwright Test Run — Yalidine (Web)

Date: 2026-02-09
App: DZMarket (web release) @ http://127.0.0.1:9105
Accounts:
- Buyer: test@gmail.com
- Seller: test2@gmail.com

## Scenario (buyer)
1) Buyer logs in.
2) Open product "xbox" (30 000 DA).
3) Choose delivery: COD.
4) Choose courier: **Yalidine Express**.
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
10) Find **Commande 77** (Yalidine Express).
11) Click **Générer bordereau + expédier**.
12) Open chat for the order.

## Results (after DB index fix)
- Order created: ✅ (order id **77**)
- Seller can generate bordereau: ✅
- Label button visible for seller: ✅
- Chat system message after shipment: ✅
  - "Commande expédiée. Statut: Expédiée Tracking: yal-Z87FSN"
- Buyer sees status/tracking only (no label button): ✅

## Note
- The **initial** order-created message did not appear for order 77 because the DB index fix was applied **after** the order was created.
- New orders created **after** the index fix should receive the "commande enregistrée" message as expected.

## DB Fix Applied (required)
```sql
DROP INDEX IF EXISTS public.messages_dedupe_uniq;
CREATE UNIQUE INDEX IF NOT EXISTS messages_dedupe_uniq
  ON public.messages(conversation_id, dedupe_key);
```
