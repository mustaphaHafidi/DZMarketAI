# 1) Objectif
Ce document centralise toute la configuration DB/Supabase necessaire pour faire fonctionner DZMarketAI sur un nouveau projet Supabase (ou apres migration).
Il ne contient aucun secret, uniquement la structure, les dependances et les etapes.

# 2) Prerequis Supabase
1) Extensions Postgres:
   - pgcrypto (gen_random_uuid, encryption optionnelle).
2) Realtime active (tables: conversations, messages, reads, orders, shipments).
3) Storage buckets:
   - products (public)
   - messages (public)
   - labels (private)
   - avatars (public)

# 3) Fichiers SQL a appliquer
1) Fichier principal: supabase.sql (a appliquer dans l'editeur SQL Supabase).
2) Migrations (optionnel si CLI): supabase/migrations/*.

# 4) Schema DB (resume)
## 4.1 Auth / Profiles
- profiles (id = auth.users.id)
- Champs: email, full_name, avatar_url, role, is_seller, phone, wilaya, daira, ...
- Trigger auto-create profile apres insertion user.

## 4.2 Listings / Catalog
- categories (hierarchie + slug + FR/AR)
- products (owner_id, category_id, category_slug, price, stock, location_wilaya/daira)

## 4.3 Orders / Shipments
- orders: buyer_id, seller_id, courier_id, courier_name, shipping_selection (jsonb), tracking_number, label_url
- shipments: label_url, tracking_number, carrier, delivery_mode, status, events (jsonb)
- RPC create_order(...) (atomic, stock reservation) + message systeme order_created

## 4.4 Chat v2 (Vinted style)
- conversations: buyer_id, seller_id, product_id, order_id, last_message_at/text, buyer_hidden_at, seller_hidden_at
- messages: conversation_id, sender_id, text, type (text/system/label), payload, dedupe_key
- reads: last_read_at/message_id
- RPCs: ensure_conversation, ensure_order_conversation, send_message, post_order_event, mark_read, get_conversations

## 4.5 Couriers / Settings
- seller_delivery_settings (owner_id, courier_id, api_key, api_secret, sender_id, extra)
- courier_credentials (legacy)
- couriers (static list, si present)
  - ZR Express: courier_id = zrexpress, api_key = secretKey, api_secret = tenantId

## 4.6 Retours colis (score fiabilite acheteur)
- buyer_return_events (historique factuel)
  - id bigserial PK
  - buyer_id uuid (FK profiles)
  - order_id bigint (FK orders)
  - courier_id text
  - status text (ex: returned_to_sender / not_claimed)
  - returned_at timestamptz
  - created_at timestamptz default now()
- buyer_return_stats (agrégats)
  - buyer_id uuid PK
  - returns_6m int default 0
  - returns_12m int default 0
  - last_return_at timestamptz
  - last_return_courier text
  - updated_at timestamptz default now()
- RLS: ecriture service_role uniquement; lecture vendeur via RPC (verifie seller_id sur order).

## 4.7 Selection livraison (shipping_selection)
- Champs communs: firstname, familyname, phone, address, receiverWilaya/Commune, weight, dimensions, price, etc.
- Champs ZR Express:
  - receiverWilayaId (UUID territoire)
  - receiverCommuneId (UUID territoire)
  - stopdeskId (hub UUID) si pickup
  - phone_e164 (+213...) et phone2_e164 si present

# 5) RLS / Policies (essentiel)
- profiles: user-only update, public read
- products: readable by all, insert/update by owner
- orders: read buyer/seller/driver; insert buyer; update seller/service
- shipments: read buyer/seller/driver; update/insert seller/service
- conversations/messages/reads: access uniquement buyer/seller
- seller_delivery_settings: select/insert/update/delete owner
- Storage policies: labels private (seller/service only), products/messages/avatars public read

# 6) Edge Functions (Supabase Functions)
## 6.1 create_shipment
Cree bordereau (Yalidine/Ecotrack/ZR Express), stocke label dans Storage `labels`, met a jour shipments + orders, poste message systeme dans chat.

## 6.2 validate-courier
Verifie token/API (Yalidine/Ecotrack/ZR Express) avant enregistrement cote vendeur.

## 6.3 courier-locations
Retourne wilayas/communes/stopdesk pour le transporteur choisi, en utilisant les credentials du vendeur.

## 6.4 seller-delivery-settings
Expose les infos d'un transporteur pour un vendeur (sans secrets cote client).

## 6.5 job-runner
Traitement asynchrone (jobs queue) + suivi transporteurs.

## 6.6 job retour-colis (cron)
- Job quotidien (03:00 UTC) qui:
  1) collecte les statuts transporteurs (Yalidine/Ecotrack/ZR Express),
  2) enregistre les events retours,
  3) met a jour buyer_return_stats,
  4) publie un message systeme de suivi dans la chat room,
  5) met a jour shipments.status + shipments.events (timeline transporteur).

### Deploiement CLI
```
supabase functions deploy create_shipment --project-ref <PROJECT_REF>
supabase functions deploy validate-courier --project-ref <PROJECT_REF>
supabase functions deploy courier-locations --project-ref <PROJECT_REF>
supabase functions deploy seller-delivery-settings --project-ref <PROJECT_REF>
supabase functions deploy job-runner --project-ref <PROJECT_REF>
```

# 7) Variables d'environnement (Edge)
Configurer dans Supabase Functions:
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY
- ECOTRACK_BASE_URL (optionnel, fallback auto)
- APP_SETTINGS_ENC_KEY (si chiffrement des secrets)

# 8) Donnees de seed
supabase.sql contient:
- Categories FR/AR
- Wilayas + communes (Algerie)
- Buckets Storage

# 9) i18n / Translations
- JSON locaux: assets/i18n/fr.json, assets/i18n/ar.json
- Table DB: translations (fallback dynamique)
- Test de coherence cles: test/i18n_keys_test.dart

# 10) Test de validation (checklist)
1) Creer un user -> profile auto cree.
2) Creer produit -> visible en browse.
3) Creer commande -> RPC OK + message systeme chat.
4) Cote vendeur -> generer bordereau -> shipment + label + message systeme.
5) Buyer -> voit status; seller -> voit bordereau.
6) Courier settings -> token valide avant save.
7) Buyer choisit transporteur -> communes/stopdesk charges via courier-locations.

# 11) Notes importantes
- Ne jamais exposer service_role cote client.
- Labels dans Storage labels (private).
- Realtime doit rester active pour chat + orders.
