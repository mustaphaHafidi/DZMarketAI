---
name: skill_validation_yallidine
description: Procédure de validation/diagnostic Yalidine pour la création de bordereaux (parcels) dans DZMarket.
---

# Validation Yalidine – création de bordereaux

But : diagnostiquer et valider l’appel `POST /v1/parcels` (Yalidine) avec les clés vendeur, en isolant rapidement les causes d’échec (format, encodage, permissions, données).

## 1) Pré‑requis
- API ID / API TOKEN Yalidine du vendeur (`seller_delivery_settings`).
- Connexion au compte vendeur pour récupérer un order_id à tester.
- Base URL Yalidine : `https://api.yalidine.app/v1/`
- Headers obligatoires : `X-API-ID`, `X-API-TOKEN`.
- Ne jamais stocker de clés ou mots de passe en clair dans le repo (utiliser un gestionnaire de secrets).

## 2) Format attendu (doc officielle)
- Appel `POST /v1/parcels`
- Body JSON = **tableau** d’objets colis.
- Champs requis par objet :
  - `order_id` (string, unique dans la requête)
  - `from_wilaya_name`
  - `firstname`, `familyname`
  - `contact_phone` (doit commencer par 0, 9 chiffres mobile ou 8 fixe, virgules possibles)
  - `address`
  - `to_commune_name`, `to_wilaya_name`
  - `product_list`
  - `price` (0..150000)
  - `do_insurance` (bool)
  - `declared_value` (0..150000)
  - `length`, `width`, `height`, `weight` (>=0)
  - `freeshipping` (bool)
  - `is_stopdesk` (bool) + `stopdesk_id` requis si true
  - `has_exchange` (bool) + `product_to_collect` requis si true

## 3) Check rapide côté Supabase
```sql
-- Vérifier credentials vendeur
select api_key, api_secret from seller_delivery_settings
where owner_id = '<seller_uuid>' and courier_id = 'yalidine';
```

## 4) Scénario de test (PowerShell)
```pwsh
$apiId    = '<API_ID>'
$apiToken = '<API_TOKEN>'
$parcel = @{
  order_id         = 'TestOrder-123'
  from_wilaya_name = 'Alger'
  firstname        = 'Test'
  familyname       = 'Test'
  contact_phone    = '0550123456'
  address          = '2 cite silmane amirat'
  to_commune_name  = "M'Sila"
  to_wilaya_name   = "M'Sila"
  product_list     = 'Produit #X'
  price            = 300
  do_insurance     = $false
  declared_value   = 300
  length           = 30
  width            = 30
  height           = 30
  weight           = 2
  freeshipping     = $false
  is_stopdesk      = $false
  has_exchange     = $false
}
$payload = @($parcel) | ConvertTo-Json -Depth 6
Invoke-RestMethod -Method Post -Uri 'https://api.yalidine.app/v1/parcels/' `
  -Headers @{ 'X-API-ID'=$apiId; 'X-API-TOKEN'=$apiToken; 'Content-Type'='application/json'; 'Accept'='application/json' } `
  -Body $payload -TimeoutSec 60
```

## 5) Points de blocage fréquents
- Réponse `400 "order_id param is missing"` : peut indiquer un problème d’encodage JSON ou une attente d’un format différent (compte spécifique). Tester :
  - form-urlencoded avec clés `0[order_id]=...` etc.
  - enveloppe `data: [...]`
  - éliminer les accents/quotes dans order_id/adresse.
- Réponse vide en form-urlencoded : serveur ignore le body → confirmer format attendu avec support.
- Si stopdesk : `is_stopdesk=true` + `stopdesk_id` requis.

## 6) Quand escalader au support Yalidine
- Si le même payload que l’exemple officiel retourne toujours `order_id missing`.
- Demander un curl exact accepté par leur backend pour le compte concerné.
- Vérifier si le compte est autorisé à créer des parcels via API (droits, environnement dev/prod).

## 7) Adaptation côté Edge Function
- Permettre plusieurs formats d’envoi :
  - JSON array (par défaut)
  - fallback form-urlencoded indexé (`0[field]`) si le compte l’exige.
- Tolérer absence de label : si tracking reçu sans label, stocker tracking et continuer (label_url vide).
- Logs d’erreur : retourner le message Yalidine et le payload minimal (sans clés).

## 8) Critères de succès
- HTTP 200 ou 201, avec `tracking` non vide.
- Label présent ou au moins tracking (label_url peut être vide).
- `shipments` et `orders` mis à jour, message “Bordereau disponible” publié si label dispo.
- Côté buyer, le label n’est pas visible (status/tracking uniquement).

## 9) Rappel UX / droits
- Seul le vendeur (`seller_id` de la commande) peut appeler `create_shipment` (RLS). Un acheteur reçoit 403.
- Parcours attendu : acheteur crée la commande → vendeur se connecte → Profil > Mes ventes (ou Tableau de livraisons).  
  - Si un bordereau existe, bouton **Ouvrir label**.  
  - Si aucun bordereau n’existe, action temporaire = appeler l’edge via curl/service_role; correctif UI prévu : bouton **Générer bordereau** (ouvre `FulfillmentPage(orderId)` pour appeler `create_shipment`).
- Credentials Yalidine sont stockés dans `seller_delivery_settings` pour chaque vendeur : vérifier/ensemencer avant test.


## 10) Statut actuel (validation)
- Le bouton **Générer bordereau** est disponible côté vendeur (Profil > Mes ventes).  
- La sélection (`selection`) est auto-construite à partir de l'order/adresse/produit.

