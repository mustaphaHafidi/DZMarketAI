---
name: yallidine-api
description: Guide d'integration Yalidine (livraison Algerie) pour DZMarketAI : generation d'expeditions/bordereaux, tracking, annulation, auth, formats, et verifications avant appel.
---

# Yalidine API (extrait docs officielles)

Source consultee via portail dev connecte : https://yalidine.app/app/dev/docs/api/index.php (Cloudflare protege).

## 1) Auth & base
- Headers obligatoires : X-API-ID, X-API-TOKEN.
- Base URL : https://api.yalidine.app/v1/
- Test rapide : GET /v1/wilayas/ avec les headers ci-dessus.

## 2) Endpoints typiques
- Parcels (colis) :
  - GET /v1/parcels/ liste + filtres.
  - GET /v1/parcels/:tracking detail.
  - POST /v1/parcels creation batch (array).
  - PATCH /v1/parcels/:tracking mise a jour.
  - DELETE /v1/parcels/:tracking ou DELETE /v1/parcels/?tracking=...
- Histories : GET /v1/histories/:tracking
- Centers (stop-desk) : GET /v1/centers (stopdesk_id requis si is_stopdesk=true)
- Communes/Wilayas : GET /v1/communes, GET /v1/wilayas
- Fees : GET /v1/fees

## 3) Regles metier DZMarketAI
- Appel Yalidine cote Edge Function create_shipment (service_role) uniquement.
- validate-courier valide le token avant save/update cote vendeur.
- courier-locations fournit wilayas/communes/stopdesk au buyer (via credentials vendeur).
- Stocker tracking + label_url dans shipments (source of truth) et orders.label_url pour compat UI.
- Le label est visible cote vendeur uniquement dans le chat (buyer voit status + tracking).
- Bordereau genere depuis l'UI vendeur (Profil > Mes ventes).

## 4) Champs requis creation
- order_id (unique dans la requete)
- from_wilaya_name
- firstname, familyname
- contact_phone (doit commencer par 0; 9 chiffres mobile ou 8 fixe)
- address
- to_commune_name, to_wilaya_name
- product_list
- price (0..150000)
- do_insurance, declared_value
- length, width, height, weight
- freeshipping, is_stopdesk (+ stopdesk_id si true)
- has_exchange (+ product_to_collect si true)

## 5) Labels
- Le label renvoye par POST est a conserver (GET/PATCH peut exiger session).
- Stocker le label dans Storage labels (private) et fournir URL au vendeur.

## 6) Tests manuels rapides
- Ping wilayas/communes avec creds valides.
- Creer un colis test, recuperer label PDF, verifier ouverture.
- Annuler le colis si statut encore en preparation.

## 7) Securite
- Stocker les cles dans seller_delivery_settings (chiffre via enc_key).
- Ne jamais loguer les cles ni les adresses completes.
- service_role uniquement pour appels sortants.

## 8) Note create_shipment (Edge)
- La fonction accepte selection avec cles equivalentes :
  - senderWilaya ou from_wilaya_name
  - receiverWilaya/receiverCommune ou to_wilaya_name/to_commune_name
  - freeshipping, is_stopdesk, stopdesk_id, has_exchange
- Si tracking sans label, mettre a jour tracking et continuer (label_url vide).

## 9) Statut actuel
- Generation de bordereau OK cote vendeur.
- Message systeme order_created apres create_order.
- Message systeme order_shipped apres bordereau.

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

