---
name: yallidine-api
description: Guide d’intégration Yalidine (livraison Algérie) pour DZMarketAI : génération d’expéditions/bordereaux, tracking, annulation, avec rappels d’auth, formats, et vérifications à faire avant appel. À utiliser dès qu’on doit créer/annuler/consulter un envoi Yalidine ou générer un bordereau.
---

# Yalidine API (extrait docs officielles)

Source consultée via portail dev connecté : https://yalidine.app/app/dev/docs/api/index.php (Cloudflare protégé).

## 1) Auth & base
- Headers obligatoires : `X-API-ID`, `X-API-TOKEN`.
- Base URL : `https://api.yalidine.app/v1/`
- Test rapide : `GET /v1/wilayas/` avec les headers ci-dessus.

## 2) Endpoints typiques
- Parcels (colis) :
  - `GET /v1/parcels/` liste + filtres (tracking, order_id, import_id, to_wilaya_id, to_commune_name, is_stopdesk, freeshipping, dates, payment_status, last_status, order_by, page/page_size, fields).
  - `GET /v1/parcels/:tracking` détail.
  - `POST /v1/parcels` création batch (array de parcels).
  - `PATCH /v1/parcels/:tracking` mise à jour (mêmes champs que création, cf. docs).
  - `DELETE /v1/parcels/:tracking` ou `DELETE /v1/parcels/?tracking=yal-1,yal-2` si statut encore “en préparation”.
- Histories : `GET /v1/histories/:tracking` (statuts détaillés).
- Centers (stop-desk) : `GET /v1/centers` pour récupérer `stopdesk_id` requis quand `is_stopdesk=true`.
- Communes/Wilayas : `GET /v1/communes`, `GET /v1/wilayas`.
- Fees : `GET /v1/fees` (tarifs).

⚠️ Changement important (popup doc) : le lien de bordereau renvoyé par **POST** reste téléchargeable sans connexion ; ceux renvoyés par **GET/PATCH** nécessiteront une session. Donc stocker/utiliser le label retourné à la création (POST) et ne pas re-télécharger plus tard sans session.

## 3) Règles métiers DZMarketAI
- Appeler Yalidine côté Edge Function `create_shipment` (service_role) uniquement. Jamais depuis l’app cliente.  
- Vérifier/normaliser wilaya/commune avec nos tables avant appel ; rejeter si invalide.  
- Générer `reference` idempotente (order_id) et la passer si l’API le permet.  
- En cas d’échec réseau, planifier retry via `job_queue` (max 3 tentatives, backoff).  
- Stocker tracking + label_url dans `shipments` (source of truth) et éventuellement `orders.label_url` pour compat UI.  
- Si retour label base64 : uploader dans bucket `labels` (privé) et exposer URL signée au vendeur.  
- Blocage : ne pas créer si order.status != pending ou si credentials vendeur manquants.
- Accès vendeur uniquement : le JWT doit être le seller_id de la commande (sinon 403).
- Le bordereau est généré depuis l'UI vendeur (Profil > Mes ventes).

## 4) Schémas attendus (à recouper avec doc)
- Téléphone : doit commencer par 0 ; 9 chiffres mobile (0550123456) ou 8 fixe (023456789). Peut fournir plusieurs numéros séparés par virgule.
- Champs obligatoires création : order_id (unique par requête), from_wilaya_name, firstname, familyname, contact_phone, address, to_commune_name, to_wilaya_name, product_list, price (0..150000), do_insurance (bool), declared_value (0..150000), length/width/height/weight (>=0), freeshipping (bool), is_stopdesk (bool), has_exchange (bool). stopdesk_id requis si is_stopdesk=true. product_to_collect requis si has_exchange=true.
- Label renvoyé dans POST : `label` (URL) et `labels` (batch). Conserver dès la création.
- Statuts livraison (last_status) incluent : Pas encore expédié, A vérifier, En préparation, Pas encore ramassé, Prêt à expédier, En passation, Ramassé, Bloqué, Débloqué, Transfert, Expédié, Centre, En localisation, Vers Wilaya, En transit, Reçu à Wilaya, En attente du client, Prêt pour livreur, Sorti en livraison, En attente, En alerte, Tentative échouée, Livré, Échec livraison, Retour vers centre, Retourné au centre, Retour transfert, Retour groupé, Retour à retirer, Retour vers vendeur, Retourné au vendeur, Échange échoué.
- Payment_status possibles : not-ready, ready, receivable, payed.

## 5) Tests manuels rapides
- Ping wilayas/communes avec creds valides.  
- Créer un colis de test (wilaya 16 → 09), récupérer label PDF, vérifier qu’il s’ouvre.  
- Annuler le colis test.  
- Vérifier tracking renvoie statut “cancelled” ou équivalent.

## 6) Sécurité
- Stocker API keys Yalidine en seller_delivery_settings (chiffré via enc_key).  
- Ne jamais loguer les clés ni les adresses complètes en clair.  
- Service_role uniquement pour appels sortants. Client mobile ne doit jamais voir les clés ni l’URL direct Yalidine.

## 7) Patterns de code (Edge/Node)
```ts
// esquisser avant usage réel, adapter aux endpoints exacts
const res = await fetch(`${base}/shipments`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-API-ID': apiId,
    'X-API-KEY': apiKey,
  },
  body: JSON.stringify(payload),
});
if (!res.ok) throw new Error(`Yalidine ${res.status}: ${await res.text()}`);
const data = await res.json();
```

## 8) À faire (compléter dès accès aux docs)
- Valider la liste exacte des endpoints et champs obligatoires/optionnels.  
- Consigner les codes statut Yalidine → mapper vers nos statuses shipment.  
- Lister les erreurs API fréquentes (credentials invalides, commune inconnue, poids manquant).  
- Vérifier limites de rate limit et tailles batch.

## 9) Note DZMarketAI (Edge create_shipment)
- La fonction accepte `selection` et tolère les clés suivantes :  
  - `senderWilaya` OU `from_wilaya_name`  
  - `receiverWilaya` / `receiverCommune` OU `to_wilaya_name` / `to_commune_name`  
  - `freeshipping`, `is_stopdesk`, `stopdesk_id`, `has_exchange`  
- Si Yalidine renvoie un tracking sans label, la commande est mise à jour avec tracking (label_url vide) au lieu d'échouer.

- La RPC `get_seller_delivery_settings_secure` n'autorise que `service_role`. Le client Supabase utilisé pour lire les credentials doit être un client service (sans Authorization utilisateur).  
- Le client RLS (avec JWT utilisateur) reste utilisé pour `orders/shipments/messages/logs`.  
- Symptôme de l’oubli : réponse `{"ok":false,"message":"Missing courier settings"}` malgré les clés présentes en DB.  

## 10) Statut actuel (validation)
- La génération de bordereau fonctionne via l'UI vendeur.  
- Le formulaire n'exige plus `orders.product_price` (colonne inexistante).  
- Le prix est déduit de `agreed_price` / `sale_price` ou fallback `products.price`.



