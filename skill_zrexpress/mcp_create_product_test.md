# MCP Test Run - Create Listing (Seller test2@gmail.com)

Date: 2026-02-09
Target: DZMarket web (http://127.0.0.1:9105)
Account: test2@gmail.com (seller)

## Goal
Create a new product listing end-to-end and capture any UX/data issues.

## Preconditions
- App running in Chrome via flutter web server.
- Seller account already logged in.

## Steps
1) Open tab "Mes annonces" and click create new listing ("Nouvelle annonce").
2) Upload 1 photo (test image file).
3) Category: Electronique.
4) Details:
   - Title: "Test ZR Produit"
   - Description: "Produit test creation via MCP."
   - Brand: "TestBrand"
   - Size: "M"
5) Price:
   - Price: 1234
   - Stock: 5
   - Cost price: 800
6) Location:
   - Wilaya: Mila (43)
   - Commune: Mila
7) Delivery:
   - COD enabled
8) Preview -> click "Publier".

## Result
- App returned to "Mes annonces".
- New listing "Test ZR Produit" appears in the list.

## Issues / Axes to Improve
1) Stock mismatch
   - Entered stock=5, but preview and list show "Stock: 1".
   - Check form state mapping and save logic (stock_quantity) in create listing flow.

2) Wilaya/commune selector usability
   - Dropdown list was hard to scroll to some wilayas (M'Sila could not be reached).
   - Suggest adding search, better scroll handling, and list virtualization.

3) Step indicator / preview state
   - Step 6 (Livraison) still marked active while preview group (Step 7) was visible.
   - Consider clearer step state (active step should reflect preview).

4) Publish feedback
   - No explicit success toast/confirmation after publish (optional improvement).

## Follow-up
- Verify stock persistence in DB (products.stock_quantity) for this listing.
- Re-test creation once stock mapping is fixed.