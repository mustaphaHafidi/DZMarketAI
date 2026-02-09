---
name: zrexpress-api
description: Guide d'integration ZR Express pour DZMarketAI (livraison Algerie) : auth, wilayas/communes, points relais, creation colis, labels PDF, tracking, et regles de securite.
---

# ZR Express API (docs ReadMe + portail ZR Express)

Source consultee via ZR Express Portal + docs publiques ReadMe :
- https://docs.zrexpress.app/docs/authentication
- https://docs.zrexpress.app/reference/createparcelendpoint
- https://docs.zrexpress.app/reference/searchterritoriesendpoint
- https://docs.zrexpress.app/reference/searchhubsendpoint
- https://docs.zrexpress.app/reference/generateindividuallabelspdfendpoint
- https://docs.zrexpress.app/reference/getparcelbytrackingnumbersupplierendpoint
- https://docs.zrexpress.app/reference/rates

## 1) Auth & base
- Base URL : `https://api.zrexpress.app`
- Headers requis sur tous les endpoints :
  - `X-Tenant` (tenant id)
  - `X-Api-Key` (token/secret key)
- Generation des tokens : portail ZR Express > API Rest > Token API.
  - Le token n'est affiche qu'une seule fois, a sauvegarder immediatement.
- Exemple auth simple (docs) : `GET /api/v1/users/profile` avec `X-Api-Key`.

## 2) Endpoints utiles DZMarketAI

### 2.1 Territoires (wilayas/communes)
`POST /api/v{version}/territories/search`
- But : recuperer la liste des territoires (wilayas/communes) + capacites livraison.
- Champs utiles : `id`, `code`, `name`, `level` (wilaya/commune), `parentId`.
- `DeliveryCapability.HasHomeDelivery` et `DeliveryCapability.HasPickupPoint` permettent de filtrer par mode.
- Requete type :
  - `pageSize` (ex: 5000)
  - `orderBy` (ex: `["code asc"]`)
  - `advancedFilter` pour filtrer par `level` ou `parentId`.

### 2.2 Hubs / points relais
`POST /api/v{version}/hubs/search`
- But : recuperer les points relais (pickup points).
- Champs utiles : `IsPickupPoint`, `address.cityTerritoryId`, `address.districtTerritoryId`, `name`, `openingHours`.
- Filtrage conseille :
  - `IsPickupPoint == true`
  - `cityTerritoryId` = wilaya selectionnee
  - `districtTerritoryId` = commune selectionnee

### 2.3 Creation colis (shipping)
`POST /api/v{version}/parcels`
- `deliveryType` : `home` | `pickup-point` | `return`
- `hubId` requis si `deliveryType == pickup-point`
- `deliveryAddress.cityTerritoryId` (wilaya id) et `deliveryAddress.districtTerritoryId` (commune id) requis.
- `customer` obligatoire (name + phone).
- `orderedProducts` obligatoire (au moins 1 produit).
- `amount` max 150000 DZD (incluant frais).
- Si `stateId` absent, le colis est cree avec le statut `OrderReceived`.

### 2.4 Labels (bordereaux)
`POST /api/v{version}/parcels/labels/individual/pdf`
- Corps : `trackingNumbers` (array)
- Retour : URLs PDF par tracking + liste des echecs.
- Max 100 colis par requete.

### 2.5 Tracking
`GET /api/v{version}/parcels/{trackingNumber}`
- Retourne detail d'un colis par tracking.

### 2.6 Tarifs
`GET /api/v1/delivery-pricing/rates/{toTerritoryId}`
`GET /api/v1/delivery-pricing/rates`
- Permet de recuperer les tarifs (home / pickup-point / return) par territoire.

## 3) Mapping DZMarketAI (regles)
- Les credentials ZR Express (X-Tenant, X-Api-Key) sont stockes dans `seller_delivery_settings`.
- Jamais d'appel ZR Express depuis le client : tout passe par Edge Functions (service_role).
- L'acheteur choisit la societe de livraison parmi celles configurees par le vendeur.
- Pour le stopdesk (pickup point) :
  1) Charger wilayas via `territories/search`.
  2) Charger communes via `territories/search` avec `parentId = wilayaId`.
  3) Charger hubs via `hubs/search`, filtre `IsPickupPoint == true` et `districtTerritoryId` correspondant.
- Le bordereau est genere cote vendeur uniquement (UI Mes ventes).
- Le tracking + label_url sont stockes dans `shipments` (source of truth).

## 4) i18n DZMarketAI (FR/AR)
- Chaque nouveau texte UI doit utiliser une cle i18n (pas de texte hardcode).
- Ajouter la cle dans `assets/i18n/fr.json` et `assets/i18n/ar.json`.
- Toujours fournir FR + AR + fallback.

## 5) Erreurs courantes
- 400 : validation (deliveryType invalide, champs manquants, amount > 150000).
- 403 : permissions/role insuffisant.
- 404 : territoire/hub/parcel introuvable.

## 6) Exemple de payload (creation colis)
```json
{
  "customer": {
    "customerId": "uuid-aleatoire",
    "name": "Nom Prenom",
    "phone": { "number1": "+213550050505" }
  },
  "deliveryAddress": {
    "street": "Adresse",
    "cityTerritoryId": "UUID_WILAYA",
    "districtTerritoryId": "UUID_COMMUNE"
  },
  "orderedProducts": [
    {
      "productName": "Produit",
      "unitPrice": 300,
      "quantity": 1,
      "stockType": "local"
    }
  ],
  "amount": 300,
  "description": "Produit",
  "deliveryType": "home"
}
```

## 7) Tests manuels rapides
- Verifier wilayas/communes via `territories/search`.
- Si pickup : hubs via `hubs/search` (IsPickupPoint).
- Creer un colis, recuperer tracking, generer label PDF.
- Verifier tracking via `GET /parcels/{trackingNumber}`.

## 8) Notes securite
- Ne jamais loguer `X-Api-Key` ou `X-Tenant`.
- Stocker les secrets chiffrés (enc_key) et utiliser uniquement le service_role en Edge.
