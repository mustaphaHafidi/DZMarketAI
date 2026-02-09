---
name: zrexpress-api
description: Guide d'integration ZR Express pour DZMarketAI (livraison Algerie): auth, territoires, points relais, creation colis, labels PDF, tracking, securite.
---

# ZR Express API

Sources:
- https://docs.zrexpress.app/docs/authentication
- https://docs.zrexpress.app/reference/createparcelendpoint
- https://docs.zrexpress.app/reference/searchterritoriesendpoint
- https://docs.zrexpress.app/reference/searchhubsendpoint
- https://docs.zrexpress.app/reference/generateindividuallabelspdfendpoint
- https://docs.zrexpress.app/reference/getparcelbytrackingnumbersupplierendpoint
- https://docs.zrexpress.app/reference/rates

## 1) Auth & base
- Base URL: https://api.zrexpress.app
- Headers requis:
  - X-Tenant (tenant id)
  - X-Api-Key (token/secret key)
- Token genere via portail ZR Express (affiche une seule fois).

## 2) Territoires (wilayas/communes)
POST /api/v{version}/territories/search
- Champs utiles: id, code, name, level (wilaya/commune), parentId
- Filtrage: level, parentId
- DeliveryCapability permet de filtrer home/pickup.

## 3) Hubs / points relais
POST /api/v{version}/hubs/search
- Filtrer IsPickupPoint == true
- Filtrer par cityTerritoryId/districtTerritoryId

## 4) Creation colis
POST /api/v{version}/parcels
- deliveryType: home | pickup-point | return
- hubId requis si pickup-point
- deliveryAddress.cityTerritoryId (wilaya UUID) + districtTerritoryId (commune UUID)
- customer + orderedProducts obligatoires
- amount <= 150000 DZD

### Telephone (important)
- ZR Express exige un format international E.164.
- DZMarket normalise automatiquement: 05/06/07xxxxxxx -> +2135/6/7xxxxxxx.
- Validation stricte cote Edge (number1 et number2).

## 5) Labels
POST /api/v{version}/parcels/labels/individual/pdf
- Corps: trackingNumbers[]
- Retour: URL ou base64.

## 6) Tracking
GET /api/v{version}/parcels/{trackingNumber}

## 7) Tarifs
GET /api/v1/delivery-pricing/rates/{toTerritoryId}
GET /api/v1/delivery-pricing/rates

## 8) Mapping DZMarketAI
- Credentials ZR Express stockes dans seller_delivery_settings (api_key = secretKey, api_secret = tenantId).
- validate-courier verifie les tokens avant save/update.
- courier-locations fournit wilayas/communes/hubs au buyer.
- create_shipment (Edge, service_role) cree le colis et poste message systeme.
- shipments = source of truth (tracking/label); label visible vendeur uniquement dans chat.

## 9) Exemple de payload (create parcel)
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
      "productId": "UUID",
      "productSku": "SKU-123",
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

## 10) Notes securite
- Ne jamais loguer X-Api-Key / X-Tenant.
- Secrets chiffres via enc_key; appels sortants uniquement via service_role.
