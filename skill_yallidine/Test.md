# Test manuel – création de bordereau Yalidine (DZMarket)

But : valider bout‑en‑bout la fonction `create_shipment` (Edge) avec un vendeur réel, et détecter toute régression sur les credentials / RLS / label.

Pré‑requis
- Compte vendeur: <SELLER_EMAIL> / <SELLER_PASSWORD>
- Compte acheteur: <BUYER_EMAIL> / <BUYER_PASSWORD>
- Order: <ORDER_ID>, product_id: <PRODUCT_ID> (seller_id = vendeur)
- Supabase URL: https://maumwzbvzbcamvlivqpe.supabase.co
- anon key: <SUPABASE_ANON_KEY>
- seller_delivery_settings pour `courier_id=yalidine` doit contenir l’API ID/TOKEN du vendeur.

Payload de test
```json
{
  "order_id": "<ORDER_ID>",
  "selection": {
    "firstname": "Test",
    "familyname": "Test",
    "phone": "0744552233",
    "address": "2 cité silmane amirat",
    "to_commune_name": "M'Sila",
    "to_wilaya_name": "M'Sila",
    "weight": 2,
    "length": 30,
    "width": 30,
    "height": 30,
    "price": 300,
    "freeshipping": true,
    "is_stopdesk": false,
    "productList": "Produit #<PRODUCT_ID>"
  }
}
```

Commande (PowerShell)
```pwsh
$URL = 'https://maumwzbvzbcamvlivqpe.supabase.co'
$ANON = '<SUPABASE_ANON_KEY>'
$EMAIL = '<SELLER_EMAIL>'; $PASSWORD = '<SELLER_PASSWORD>'
$auth = Invoke-RestMethod -Method Post -Uri "$($URL)/auth/v1/token?grant_type=password" `
  -Headers @{ apikey=$ANON } -ContentType 'application/json' `
  -Body (@{email=$EMAIL; password=$PASSWORD} | ConvertTo-Json)
$token = $auth.access_token
# Mettre ici le JSON du payload ci-dessus
$body = '<PASTE_JSON_PAYLOAD_HERE>'
Invoke-RestMethod -Method Post -Uri "$($URL)/functions/v1/create_shipment" `
  -Headers @{ apikey=$ANON; Authorization="Bearer $token" } `
  -ContentType 'application/json' -Body $body -TimeoutSec 30
```

Résultats attendus
1. HTTP 200, body `{ ok: true, tracking_number: "...", label_url: "https://..." }`.
2. Table `shipments` contient `order_id=<ORDER_ID>`, tracking_number, label_url (non null), status=shipped.
3. Table `orders` mise à jour (tracking_number, label_url, status éventuellement `shipped`).
4. Message automatique ajouté dans `messages` (type=system) avec `i18n_key=order.system.shipped`.
5. Côté vendeur, le bouton label est visible; côté buyer, seul le status/tracking s’affiche.
6. Le label est téléchargeable (signed URL) et s’ouvre en PDF.

Erreurs à surveiller
- `Missing courier settings` : la fonction n’a pas pu lire les credentials (vérifier déploiement, seller_delivery_settings).
- 403 Forbidden : `order.seller_id` ≠ JWT ou auth absent.
- 429 Rate limit exceeded : retester après 1 minute.
- 502/400 Yalidine : problème côté Yalidine (crédentials invalides, commune/wilaya incorrectes, poids/prix hors plage).

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

