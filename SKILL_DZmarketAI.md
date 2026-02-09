---
name: dzmarket-ai-reference
description: Reference synthetique et prescriptive pour DZMarketAI (Flutter + Supabase) couvrant vision, donnees, regles metier, livraison multi-transporteurs, chat Vinted-like, securite, configs, tests et TODO.
---

1. Vision & perimetre
   - Marketplace algerienne C2C/B2C. Roles: buyer, seller, admin (service_role backend uniquement).
   - Flux clefs: Auth -> Profil -> Parcourir -> Favoris -> Contacter vendeur -> Commande (COD) -> Livraison/suivi -> Avis.
   - Objectifs: mobile-first, pas d'exposition de coordonnees perso (chat in-app), perfs/realtime fiables, soft-delete partout.

2. Architecture
   - Client Flutter: UI (screens/pages/widgets) -> services/repos (Supabase client) -> models.
   - Backend Supabase: Postgres + RLS + Realtime + Storage + Edge Functions.
   - RPC pour operations atomiques (create_order, send_message, ensure_conversation, post_order_event, etc.).
   - Storage buckets: products, messages, labels (private), avatars.
   - Realtime: streams `.from(...).stream(primaryKey: ...)`; tri final cote client pour eviter ORDER BY lourds.
   - Refresh unifie: `RefreshController` (timeout, anti double-run, Snackbar erreurs) + `RefreshIndicator` sur listings/chat/orders.

3. Auth & profils
   - Table profiles (id = auth.users.id) + trigger handle_new_user.
   - Champs: email, full_name, avatar_url, role, is_seller, phone, wilaya, daira, prefs.
   - RLS: select public, update/insert self (auth.uid = id).

4. Listings / Produits
   - Table products (bigserial id, owner_id uuid FK profiles, category_id bigint FK categories, category_slug).
   - Aucun champ libre category. Statuts: active/paused/sold.
   - Champs prix, image_url + image_urls[], stock_quantity, sold_count, is_archived.
   - Categories hierarchiques (table categories seed FR/AR).
   - Index: status+created_at, category_slug/id; FTS non active (a prevoir si besoin).
   - Favoris: table favorites (PK user_id, product_id) RLS user-only.

5. Commandes
   - RPC create_order (security definer): verifie auth, interdit achat auto, stock>0, rate-limit, reserve stock immediatement.
   - Table orders: buyer_id, seller_id (auto), status pending|paid|shipped|delivered|cancelled, payment_method cod/online (actuel COD), tracking info, shipping_selection jsonb.
   - Triggers: set_order_seller, apply_order_delivery (decremente stock et augmente sold_count au delivered).
   - RLS: select buyer/seller/driver; insert buyer; update seller/service_role; updates limites buyer/driver.
   - Apres creation: message systeme auto dans chat d'ordre (order_created) avec dedupe.

6. Paiement
   - Actuel: COD uniquement. payment_intents/events en place mais non utilises.
   - Impact: COD -> status pending; livraison suit orders.status.

7. Livraison / Transporteurs
   - seller_delivery_settings (owner_id, courier_id, api_key, api_secret, sender_id, extra) RLS owner-only; chiffree via encrypt_seller_secrets (enc_key).
   - validate-courier (Edge): verifie les tokens avant save/update cote vendeur.
   - courier-locations (Edge): renvoie wilayas/communes/stopdesk selon transporteur et credentials du vendeur.
   - create_shipment (Edge, service_role): cree bordereau, met a jour shipments + orders, poste message systeme dans la room d'ordre.
   - Transporteurs supportes: Yalidine, Ecotrack, ZR Express.
   - ZR Express: telephone E.164 +213 (mobile 05/06/07), territoires par UUID (receiverWilayaId/receiverCommuneId), stopdesk via hubId.
   - Buyer choisit la societe parmi celles configurees par le vendeur.
   - Bordereau genere cote vendeur uniquement (UI Mes ventes).

8. Bordereaux / Labels
   - shipments = source of truth (tracking/label). orders.label_url conserve pour compat UI.
   - labels stockes dans bucket `labels` (private). URL label visible cote vendeur uniquement dans le chat.

9. Chat style Vinted + commandes
   - Tables: conversations (product_id, order_id, buyer_id, seller_id, last_message_at/text, hidden_at), messages (type, payload, dedupe_key), reads, user_blocks.
   - Conversations d'ordre: unique par order_id (partial unique index).
   - RPCs: ensure_conversation, ensure_order_conversation, send_message, post_order_event, delete/restore_conversation, mark_read, get_conversations.
   - Messages systeme: order_created, order_validated, order_shipped (payload i18n_key/status/tracking/label_url).
   - Dedupe: unique (conversation_id, dedupe_key) pour eviter doublons sur retries.
   - Client: ChatRepository streams (tri client), header produit sticky, badge non-lu, hide/restore explicite.
   - Label visible vendeur uniquement; buyer voit status + tracking sans bouton label.

10. Securite & secrets
   - Jamais de secrets dans le client: anon key uniquement.
   - service_role reserve Edge/cron.
   - Encryption app.settings.enc_key, rotation via reencrypt_seller_secrets.
   - job_queue + claim_jobs/complete_job (service_role).

11. Flavors & config
   - Android appId base com.mustapha.dzmarket, flavors dev/staging/prod.
   - Run dev: `flutter run -d <device> --flavor dev -t lib/main.dart --dart-define=APP_ENV=dev --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --no-dds --no-enable-impeller`.
   - Web: APP_ENV + web/config.json.
   - Supabase options dans lib/src/config/supabase_options.dart (pas de secrets commits).

12. i18n
   - Clefs dans assets/i18n/fr.json et assets/i18n/ar.json.
   - Helper: L10n.tr(context, 'key', fallback: ...).
   - Toute nouvelle UI/texte doit avoir FR+AR.

13. Tests
   - Unit/widget: `flutter test`, `test/phone_formatter_test.dart`, `test/i18n_keys_test.dart`.
   - Integration: chat_flow, order_system_messages, shipping_validation_* (yallidine/ecotrack/zrexpress).

14. CI/CD
   - GitHub Actions: lint + tests.
   - Fichiers volumineux: verifier Git LFS ou ignore.
   - Secrets via env/CI only.

15. TODO priorisee (<=20)
   Must:
   - Stabiliser l'UX ZR Express (formulaire specialise, blocage si territoires vides, phone E.164).
   - Couvrir Contacts (liste personnes contacte/favoris, tri activite).
   - Ajouter attachments images chat (storage/messages + previews).
   - Durcir anti-spam (liens/nums) + blocage UI/notifications.
   Should:
   - Activer FTS produits (title/description) + filtres wilaya/prix.
   - Pagination stable watchConversations (cursor RPC + merge stream).
   - Monitoring job_queue (dashboard simple).
   Could:
   - Mode offline leger (cache dernieres conversations/messages).
   - Paiement en ligne (intent + status transitions).
   - Push notif nouveau message/commande.

16. Annexes
   - Nommage: snake_case tables/colonnes, camelCase Dart, status en lower_snake.
   - Erreurs frequentes: duplicate key trio si bypass ensure_conversation; statement timeout si ORDER BY server.
   - Commandes utiles:
     * Run dev: `flutter run -d <device> --flavor dev -t lib/main.dart --dart-define=APP_ENV=dev --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --no-dds --no-enable-impeller`
     * Tests: `flutter test`, `flutter test integration_test/shipping_validation_zrexpress_test.dart`
     * SQL: appliquer `supabase.sql` via SQL editor (sections idempotentes).
