# 1) Objectif
Ce document centralise **toute la configuration DB/Supabase** nécessaire pour faire fonctionner DZMarketAI sur un nouveau projet Supabase (ou après migration).  
Il ne contient **aucun secret**, uniquement la structure, les dépendances et les étapes.

# 2) Prérequis Supabase
1. Extension Postgres :
   - `pgcrypto` (utilisé pour `gen_random_uuid()` et encryption optionnelle).
2. Realtime activé (tables: `conversations`, `messages`, `reads`, `orders`, `shipments`).
3. Storage buckets :
   - `products` (public)
   - `messages` (public)
   - `labels` (private)
   - `avatars` (public)

# 3) Fichiers SQL à appliquer
1. **Fichier principal** : `supabase.sql`  
   - Appliquer dans l’éditeur SQL Supabase.
2. Migrations (optionnel si vous utilisez la CLI) :
   - `supabase/migrations/*`

# 4) Schéma DB (résumé)
## 4.1 Auth / Profiles
- `profiles` (id = auth.users.id)
- Champs: `email, full_name, avatar_url, role, is_seller, phone, wilaya, daira, ...`
- Trigger auto‑create profile après insertion user.

## 4.2 Listings / Catalog
- `categories` (hiérarchie + slug + FR/AR)
- `products` (owner_id, category_id, category_slug, price, stock, location_wilaya/daira)

## 4.3 Orders / Shipments
- `orders` : buyer_id, seller_id, courier_id, courier_name, shipping_selection(jsonb), tracking_number, label_url
- `shipments` : label_url, tracking_number, carrier, delivery_mode, events(jsonb)
- RPC `create_order(...)` (atomic, stock reservation)

## 4.4 Chat v2 (Vinted style)
- `conversations` : buyer_id, seller_id, product_id, order_id, last_message_at/text, hidden flags
- `messages` : conversation_id, sender_id, text, type, payload, dedupe_key
- `reads` : last_read_at/message_id
- RPCs: `ensure_conversation`, `ensure_order_conversation`, `send_message`, `post_order_event`, `mark_read`, `get_conversations`

## 4.5 Couriers / Settings
- `seller_delivery_settings` (owner_id, courier_id, api_key, api_secret, sender_id, extra)
- `courier_credentials` (legacy)
- `couriers` (static list, if present)
  - ZR Express : `courier_id = zrexpress`, `api_key = secretKey`, `api_secret = tenantId`

## 4.6 Selection livraison (shipping_selection)
- En plus des champs classiques (wilaya/commune/noms), stocke maintenant :
  - `receiverWilayaId` (ID territoire ZR Express ou code wilaya)
  - `receiverCommuneId` (ID territoire ZR Express / commune)
  - `stopdeskId` (hub ZR Express) si livraison point relais

# 5) RLS / Policies (essentiel)
- `profiles` : user only update, public read
- `products` : readable by all, insert/update by owner
- `orders` : read buyer/seller/driver; insert by buyer; update by seller/service
- `shipments` : read buyer/seller/driver; update/insert seller/service
- `conversations/messages/reads` : access uniquement buyer/seller
- `seller_delivery_settings` : select/insert/update/delete owner
- Storage policies : `labels` private (seller/service only), `products/messages/avatars` public read

# 6) Edge Functions (Supabase Functions)
## 6.1 create_shipment
Crée bordereau (Yalidine/Ecotrack), stocke label dans Storage `labels`, met à jour `shipments` + `orders`, poste message système dans chat.

## 6.2 validate-courier
Vérifie token/API (Yalidine/Ecotrack) avant enregistrement côté vendeur.

## 6.3 seller-delivery-settings
Expose les infos d’un transporteur pour un vendeur (sans secrets côté client).

## 6.4 courier-locations
Retourne les **communes / stopdesk** pour le transporteur choisi (Yalidine/Ecotrack), en utilisant les credentials du vendeur.

## 6.5 job-runner
Traitement asynchrone (jobs queue).

### Déploiement CLI
```bash
supabase functions deploy create_shipment --project-ref <PROJECT_REF>
supabase functions deploy validate-courier --project-ref <PROJECT_REF>
supabase functions deploy seller-delivery-settings --project-ref <PROJECT_REF>
supabase functions deploy courier-locations --project-ref <PROJECT_REF>
supabase functions deploy job-runner --project-ref <PROJECT_REF>
```

# 7) Variables d’environnement (Edge)
Configurer dans Supabase Functions (Project Settings):
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ECOTRACK_BASE_URL` (optionnel, fallback auto)
- (Si besoin) `APP_SETTINGS_ENC_KEY` (si vous chiffrez secrets)

# 8) Données de seed
`supabase.sql` contient :
- Catégories FR/AR
- Wilayas + communes (Algérie)
- Buckets Storage

# 9) I18n / Translations
- JSON locaux : `assets/i18n/fr.json`, `assets/i18n/ar.json`
- Table DB : `translations` (fallback dynamique)
- Test de cohérence clés : `test/i18n_keys_test.dart`

# 10) Test de validation (checklist)
1. Créer un user → profile auto créé.
2. Créer produit → visible en browse.
3. Créer commande → RPC OK + message système chat.
4. Côté vendeur → générer bordereau → shipment + label + message système.
5. Buyer → voit status, seller → voit bordereau.
6. Courier settings → token validé avant save.
7. Buyer choisit transporteur → stopdesk/communes correspondants.

# 11) Notes importantes
- **Jamais** exposer `service_role` côté client.
- Les labels sont stockés dans Storage `labels` (private).
- Realtime doit rester activé pour les tables chat + orders.
