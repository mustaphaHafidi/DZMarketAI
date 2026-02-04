---
name: dzmarket-ai-reference
description: Reference synthetique et prescriptive pour DZMarketAI (Flutter + Supabase) couvrant vision, donnees, regles metier (chat Vinted-like, commandes, livraison), securite RLS/roles, configs flavors, tests, et TODO priorisee.
---

1. Vision & perimetre  
   - Marketplace algerienne C2C/B2C. Roles : buyer, seller, admin (service_role backend).  
   - Flux clefs : Auth → Profil → Parcourir categories/listings → Favoris → Contacter vendeur → Commande (COD) → Livraison/suivi → Avis.  
   - Objectifs : mobile-first, pas d’exposition de coordonnees perso (chat in-app), perfs/realtime fiables, soft-delete partout.

2. Architecture  
   - Client Flutter : UI (screens/pages/widgets) → services/repos (Supabase client) → models. Navigation go_router.  
   - Backend Supabase : Postgres + RLS + Realtime + Storage + Edge Functions. RPC pour operations atomiques (create_order, send_message, ensure_conversation, etc.).  
   - Storage buckets : products, messages, labels, avatars (policies dediees).  
   - Realtime : streams `.from(...).stream(primaryKey: ...)`; tri final cote client pour eviter ORDER BY lourds.  
   - Refresh unifie : `RefreshController` (timeout, anti double-run, Snackbar erreurs) + `RefreshIndicator` sur listings/chat hub/chat room/orders.

3. Auth & profils  
   - Table profiles (id = auth.users.id) + trigger handle_new_user. Champs : email, full_name, avatar_url, role, is_seller, localisation, prefs.  
   - RLS : select public, update/insert self (auth.uid = id).  
   - Roles logiques : buyer par defaut, seller via flag, admin via service_role uniquement.

4. Listings / Produits  
   - Table products (bigserial id, owner_id uuid FK profiles, category_id bigint FK categories, category_slug). Aucun champ libre category.  
   - Statuts : active/paused/sold. Champs prix, image_url + image_urls[], stock_quantity, sold_count, is_archived.  
   - Categories hierarchiques (table categories seed FR/AR).  
   - Recherche : index status+created_at, category_slug/id; FTS non active (a prevoir si besoin).  
   - Favoris : table favorites (PK user_id, product_id) RLS user-only.

5. Commandes  
   - RPC create_order security definer : verifie auth, interdit achat auto, stock>0, rate-limit, reserve stock immediatement. Retourne order_id.  
   - Table orders : buyer_id, seller_id (auto), status pending|paid|shipped|delivered|cancelled, payment_method cod/online (actuel COD), tracking info.  
   - Triggers : set_order_seller, apply_order_delivery (decremente/sold_count on delivered). Pas de delete/rollback cote client; annulation = status update.  
   - RLS : select buyer/seller/driver; insert buyer; update seller/service_role; updates limites buyer/driver.

6. Paiement  
   - Actuel : COD uniquement. payment_status pending/paid (online futur). payment_intents/events en place mais non utilises.  
   - Impact : COD → status pending ; livraison suit orders.status.

7. Livraison / Transporteurs  
   - seller_delivery_settings (owner_id, courier_id text, api_key/secret/sender_id/extra) RLS owner-only; chiffree via trigger encrypt_seller_secrets (cle app.settings.enc_key), rotation via reencrypt_seller_secrets(old,new).  
   - courier_credentials legacy owner-only.  
   - shipments = source of truth tracking/label (FK order_id); orders.label_url conserve pour compat.  
   - Edge Function create_shipment (service_role) centralise appels transporteur.  
   - Ecotrack endpoints : POST /api/v1/create/order, POST /api/v1/create/orders, GET /api/v1/get/order/label?tracking=... ; valider wilaya/commune, idempotence par reference, retries job-runner.  
   - Erreurs typiques : wilaya/commune invalides, credentials manquants.

8. Bordereaux / Labels  
   - Bucket labels non public : acces seller/service_role, signed URL si besoin.  
   - Generation/refresh via Edge + job_queue ; orders.label_url garde pour UI.

9. Chat style Vinted  
   - Tables : conversations(id uuid, buyer_id, seller_id, product_id bigint FK, last_message_at/text, buyer_hidden_at, seller_hidden_at, created_at, updated_at, unique (product_id,buyer_id,seller_id) where product_id not null), messages(id uuid, conversation_id, sender_id, text, created_at, deleted_at), reads(PK conversation_id,user_id, last_read_at, last_read_message_id), user_blocks(PK user_id, blocked_user_id).  
   - RPCs (security definer) : ensure_conversation (upsert trio), send_message (check participant + block, MAJ last_message_*), delete_conversation (set hidden_at), restore_conversation, mark_read, get_conversations (visible pour caller; tri client desc last_message_at).  
   - RLS : conversations/messages participants select/insert/update; reads select/upsert self; user_blocks self.  
   - Client : ChatRepository streams (tri client), header produit sticky dans ChatRoomPage, onglets Messages/Archivees, swipe hide/restore, badge non-lu (last_message_at vs reads), pull-to-refresh sur hub et room.  
   - UX : preview dernier message, soft-delete ne revient pas sauf restore explicite; realtime multi-device; pagination RPC possible; attachments pas encore.

10. Securite & secrets  
   - Secrets jamais dans le client : seul anon via --dart-define. service_role reserve Edge/cron.  
   - Encryption app.settings.enc_key, rotation via reencrypt_seller_secrets.  
   - job_queue + claim_jobs/complete_job (service_role) pour async.  
   - RLS stricte sur orders, shipments, delivery settings, chat.

11. Flavors & config  
   - Android appId base com.mustapha.dzmarket, flavors dev/staging/prod (suffix). Commande type : `flutter run -d <device> --flavor dev -t lib/main.dart --dart-define=APP_ENV=dev --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --no-dds --no-enable-impeller`.  
   - Web : APP_ENV + web/config.json.  
   - Firebase par flavor (dev placeholders).  
   - Supabase options dans lib/src/config/supabase_options.dart (pas de secrets commits).

12. Tests  
   - Unit/widget : `flutter test`, `flutter test test/refresh_controller_test.dart`.  
   - Integration : `integration_test/chat_flow_test.dart` (hide/restore), auth_flow, router_refresh, courier/order flows (toolchain Windows requise).  
   - Scripts : `scripts/run_live_courier_test.ps1` (seller courier settings seeds, env vars, pas de secrets logs).  
   - Skips possibles si test_env.json manquant.

13. CI/CD  
   - GitHub Actions : lint + tests (flutter test).  
   - Fichiers volumineux : verifier Git LFS ou ignore (supabase tar, etc.).  
   - Secrets : toujours via env/CI secrets (service_role, enc_key).

14. TODO priorisee (<=20)  
   Must:  
   - Finaliser Contacts page (liste personnes deja contacte/favoris, tri activite).  
   - Implementer report_message/report_user (RPC + UI).  
   - Ajouter attachments images chat (storage/messages + previews).  
   - Durcir anti-spam (liens/nums) + blocage UI/notifications.  
   Should:  
   - Activer FTS produits (title/description) + filtres wilaya/prix.  
   - Ajouter pagination stable watchConversations (cursor RPC + merge stream).  
   - Stabiliser Firebase config par flavor (remplacer placeholders).  
   - Edge retry/backoff Ecotrack + journal echecs.  
   - Monitoring job_queue (dashboard simple).  
   Could:  
   - Mode offline leger (cache dernieres conversations/messages).  
   - Paiement en ligne (intent + status transitions).  
   - UI analytics vendeur.  
   - Push notif nouveau message/commande (functions + FCM tokens).  
   - Export CSV commandes vendeur.

15. Annexes  
   - Nommage : snake_case tables/colonnes, camelCase Dart, status en lower_snake.  
   - Erreurs frequentes : duplicate key trio si bypass ensure_conversation; statement timeout si ORDER BY server; Firebase placeholder -> desactiver analytics en dev.  
   - Commandes utiles :  
     * Run dev : `flutter run -d <device> --flavor dev -t lib/main.dart --dart-define=APP_ENV=dev --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --no-dds --no-enable-impeller`  
     * Attacher : `flutter attach -d <device>`  
     * Tests : `flutter test`, `flutter test integration_test/chat_flow_test.dart`, `flutter test test/refresh_controller_test.dart`  
     * SQL : appliquer `supabase.sql` via SQL editor (sections idempotentes).
