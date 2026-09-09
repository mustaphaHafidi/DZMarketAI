# JOURNAL-IA — DZMarket

Fiche de coordination partagée entre agents IA (Claude, Codex, autres).
**À lire avant toute intervention. À mettre à jour juste après, dans le même tour.**

Même rôle que le `JOURNAL-IA.md` des autres projets du studio (Afus, Tirra, Akud,
Adrim, Auresdev, TASSHIL_Recovery). Ici : état courant + suivi des findings +
journal des changements. Le détail opérationnel reste dans `docs/agent/`.

---

## Règles (rappel court)

- Le code / les migrations / la config **live** priment sur les vieux docs et les vieux chats.
- Projet **déjà en production, utilisé par des users publics** → aucune modif à risque,
  aucune régression. Read-only par défaut ; tout changement passe par test staging.
- Ne jamais afficher ni committer de secret (clé SSH, `.p8`, `.env`, service-role,
  keystore, token transporteur, JWT).
- Ne pas charger les vieux JSONL Codex en entier — extraits ciblés seulement.
- Une modif de comportement/déploiement/tests → mettre à jour le plus petit fichier
  `docs/agent/*.md` concerné **et** ajouter une ligne au journal ci-dessous.
- Routage détaillé : `docs/agent/README.md`.

---

## État courant (vérification locale du 2026-09-08)

- Branche `main`, code de référence `0a009f0`, identique au `main` distant vérifié en HTTPS.
- Coordination : journal partagé référencé dans `docs/agent/README.md`. Recontrôler Git à chaque reprise ; aucun changement applicatif lors de cette vérification.
- Repo : `github.com/mustaphaHafidi/DZMarketAI.git`.
- App Flutter locale `1.0.7+39` ; Android/Web et iOS via Codemagic → TestFlight documentés, versions déployées et stores non revérifiés.
- Backend documenté (non revérifié en production le 2026-09-08) : Supabase self-host sur Hetzner (`dzm-app-01` / `dzm-db-01` / `dzm-storage-01`),
  Caddy + Kong. Migration hosted→Hetzner **en phase cutover** (données + storage migrées ;
  reste durcissement + rotation des secrets de l'ancienne plateforme).
- Domaines : `app.dzmarket.pro`, `api.dzmarket.pro`, `www.dzmarket.pro`.
- Accès / credentials : carte complète dans `infra/hetzner/SERVERS_CONFIG_AND_KEYS.md`
  (config sans valeurs) + skills `dzmarket-connect-hetzner` / `dzmarket-servers-activity`.

---

## Findings ouverts — audit lecture seule du 2026-09-07

Trouvés par passage des skills (repo-continuation-brief, env-secrets-ci-audit,
security-review baseline) + pistes des audits Codex du 2026-09-02 (sessions coupées
avant rapport final). **Rien n'a été corrigé.** À revalider sur la base live avant tout fix.

### Résumé par priorité

- **🔴 Urgent (à traiter en premier)** — #1 RLS `profiles` : lecture de toutes les lignes autorisée dans le SQL local ; exposition effective des colonnes à vérifier avec les grants/policies live. #2 Copies d'accès dans `Historique/`, ignoré seulement localement ; le dossier APNs `Apple/` est déjà ignoré dans le `.gitignore` versionné. Présence vérifiée par métadonnées, contenus non ouverts.
- **🟠 Moyen (revalider sur le live avant fix)** — #3 Edge Functions `estimate-shipping`
  / `courier-locations` : service-role + `seller_id` fourni par l'appelant ; authentification et rate limits présents. Préserver les demandes légitimes des acheteurs lors du contrôle d'autorisation. #4 Transition `orders.status=paid` pilotée côté client (policy
  UPDATE peut-être trop permissive côté acheteur). #5 URL de label qui fait confiance à
  l'origine de la requête si l'origine publique n'est pas fixée. #6 `job-runner-cron.yml` :
  garde sur le mauvais slug repo → exécution GitHub planifiée ignorée dans `DZMarketAI` ; les éventuels crons serveur ne sont pas vérifiés.
- **🟢 Normal (dette, pas de risque immédiat)** — #7 `google-services.json` Android
  commités alors que l'iOS plist est gitignoré + injecté CI. #8 Checklist de durcissement
  cutover (`SERVERS_CONFIG_AND_KEYS.md §8`) en attente. #9 Aucun test policies RLS ni
  contract-test app↔Edge Functions en CI.

### Détail des findings

| # | Prio | Sujet | À faire | Risque régression si mal fait |
|---|------|-------|---------|-------------------------------|
| 1 | 🔴 | `public.profiles` : policy `for select using (true)` (`supabase.sql:65`) ; aucune migration corrective trouvée. Grants et exposition effective live non vérifiés | Vérifier la DB live, puis séparer projection publique à colonnes limitées et accès privé. `is_public` seul ne masque aucune colonne sensible ; une vue seule ne retire pas l'accès direct à la table | Tester browse public, profil vendeur et compte privé en staging |
| 2 | 🔴 | Plusieurs copies nommées `dzmarket_hetzner` et mot de passe de transfert sous `Historique/`, ignoré via `.git/info/exclude`. APNs présent sous `Apple/`, ignoré par `.gitignore:63`. Aucun contenu secret lu | Ajouter l'exclusion versionnée, sortir les archives du repo et planifier les rotations après identification des usages | Une rotation SSH/APNs peut couper accès, CI ou push ; vérifier le remplacement avant révocation |
| 3 | 🟠 | Devis/localités : utilisateur authentifié et rate limits vérifiés dans le code ; identité vendeur fournie par l'appelant. `estimate-shipping` vérifie le propriétaire si un produit existant est fourni (`index.ts:674`) | Vérifier le contrat acheteur/produit/vendeur et les abus possibles en staging. Ne pas imposer `user == seller_id` : le checkout acheteur appelle ces fonctions (`product_detail_page.dart:824`, `:2768`) | Un contrôle propriétaire copié de la configuration vendeur bloquerait devis et localités côté acheteur |
| 4 | 🟠 | `createMockPaymentIntent` écrit `succeeded`, puis l'UI demande `orders.status=paid` (`orders_page.dart:117`). Paiement réel explicitement non configuré (`payment_service.dart:49`) | Vérifier le comportement métier attendu, la version déployée et les policies live ; ne jamais traiter ce mock comme preuve d'encaissement | Moyen — vérifier achat, COD et états de commande bout-en-bout |
| 5 | 🟠 | Réécriture URL de label : peut faire confiance à l'origine de la requête si l'env ne fixe pas d'origine publique | Vérifier `SUPABASE_PUBLIC_URL` / origine publique explicite sur `dzm-app-01` | Faible |
| 6 | 🟠 | `.github/workflows/job-runner-cron.yml:14` : garde sur `mustaphaHafidi/DZmarket`, différente de `DZMarketAI` ; le job GitHub planifié est ignoré, le lancement manuel reste permis | Corriger le slug après vérification des planifications serveur pour éviter un doublon | L'activation déclenche le job de production ; contrôler les effets et la cadence |
| 7 | 🟢 | 3 `android/app/src/*/google-services.json` commités alors que l'iOS plist est gitignoré + injecté CI | Décider : gitignore + inject CI, ou assumer et documenter | Nul |
| 8 | 🟢 | Durcissement cutover en attente (`SERVERS_CONFIG_AND_KEYS.md §8`) : rotation JWT/DB ancienne plateforme, SSH par IP source, fail2ban, backups PG + test restore, snapshots MinIO, dashboard monitoring | Dérouler la checklist §8 | Faible, à faire par étapes |
| 9 | 🟢 | Pas de tests policies RLS (pgTAP) ni contract-tests app↔Edge Functions ; couverture non mesurée en CI | Ajouter au fur et à mesure des changements | Nul |

---

## Table des erreurs runtime — `public.app_errors`

Télémétrie des erreurs client (Flutter). Schéma (`supabase.sql` ~L4557) :

| colonne | type | note |
|---|---|---|
| `id` | bigserial | PK |
| `user_id` | uuid → `profiles(id)` | `on delete set null` |
| `message` | text | tronqué à 2000 par le client |
| `stack` | text | tronqué à 8000 |
| `context` | jsonb | `{}` par défaut |
| `platform` | text | android / ios / web |
| `created_at` | timestamptz | `now()` |

**Ce qui est écrit** (`lib/src/services/app_error_service.dart`) : erreurs fatales +
erreurs non-fatales d'utilisateurs authentifiés, **après** filtrage du bruit (JWT expiré
/ 401, timeouts realtime / websocket code 1006, erreurs média) et **dédup** des empreintes
identiques sur une fenêtre de 15 min.

**RLS lecture** : `service_role` **ou** `profiles.role in ('admin','superadmin')`.
**Purge** : `cleanup_app_errors(p_days integer default 30)` (service-role uniquement).

**Lire les lignes live** — 3 voies sans risque (lecture seule) :

1. App déployée, compte admin/superadmin → `https://app.dzmarket.pro/admin/errors`
   (charge les 600 dernières, tri `created_at desc` — `lib/src/features/admin/app_errors_page.dart`).
2. Supabase Studio sur `dzm-app-01`.
3. SQL sur `dzm-app-01` (synthèse 7 j, read-only) :
   ```bash
   docker exec -i supabase-db psql -U postgres -d postgres -c "
     select date_trunc('day',created_at) d, platform, count(*) n, left(message,80) msg
     from public.app_errors
     where created_at > now() - interval '7 days'
     group by 1,2,4 order by n desc limit 40;"
   ```

Accès DB direct impossible depuis certaines sessions Claude (pare-feu 5432 en IP privée
+ classifier qui bloque SSH et lecture de clé privée — cf. obs #5 du skill-observations
log) → dans ce cas, passer par la voie 1.

---

## Journal des changements (plus récent en haut)

### 2026-09-09 - Codex - durcissement COD et conversations

- Retire le bouton et le parcours de paiement mock des commandes; `PaymentService.createMockPaymentIntent` refuse maintenant explicitement toute tentative. Le flux reste paiement a la livraison.
- Le contact vendeur et l'offre valide envoient un premier message avant l'ouverture du salon, afin d'eviter les nouveaux salons vides lors d'une action valide. Les annulations/offres invalides sortent toujours avant toute creation.
- Test de regression ajoute: `test/payment_service_test.dart`.
- Verification: `flutter analyze --no-pub` sans erreur, 2 warnings preexistants dans `auth_service.dart`; `flutter test --no-pub --reporter expanded` = 136 OK, 2 ignores. Aucun secret, acces prod, migration ou deploiement.
- Limite: les URLs/tenants Ecotrack et la projection RLS des profils restent a traiter avec les informations fournisseur et un staging valide.

### 2026-09-09 - Codex - audit admin, COD, transporteurs et conversations

- Audit live en lecture seule termine: stack et cron serveur verifies; aucun secret, JSONL ancien, ecriture de production ou deploiement.
- Priorite P0: les profils publics exposent encore des donnees privees; conserver l'acces complet des superadmins mais passer par une projection publique minimale et une vue admin autorisee.
- COD confirme en production: aucune ligne `payment_intents`; le chemin `createMockPaymentIntent` reste une dette de code a desactiver avant livraison.
- Transporteurs: Guepex 2/2 et Yalidine 2/2 OK en lecture seule; ZR 1/2 invalide; Ecotrack 2/2 en 404 sur l'hote/endpoints generiques, a aligner avec l'URL/tenant de chaque societe. La normalisation Yalidine existante est a conserver.
- Conversations: l'offre annulee ou vide ne cree pas de salon dans le chemin actuel; le contact vendeur cree toutefois un salon avant le premier message. Ne pas supprimer automatiquement les 19 salons vides.
- Rapport detaille: `docs/agent/admin-couriers-cod-audit-2026-09-08.md`. Aucun changement applicatif.

### 2026-09-08 — Claude — kit visuels réseaux (mode marketing)
- Nouveau dossier `marketing/social-kit/` : 7 visuels **SVG** on-brand (FR + AR) pour
  @dzmarketpro — posts 1080×1080, stories 1080×1920, image lien FB 1200×630, bannière
  LinkedIn 1128×191, cover TikTok 1080×1920 + `README.md` (charte, légendes, export PNG).
- Ajout `marketing/social-kit/posts/` : 12 visuels **SVG** à publier (feed, sans
  couverture/photo de profil), angles marché algérien — paiement à la livraison,
  58 wilayas (Yalidine/Ecotrack/ZR Express/Guepex), 0 commission, « fini le prix inbox »,
  tout-en-un, comparatif, rapidité 90 s ; FR + darija AR + `README.md` (rotation, légendes).
  Faits recoupés dans le repo : `payment method: cod`, transporteurs (dossier projet),
  offre « 100 premiers vendeurs ». ~27 Ko au total.
- Export **PNG** des 12 posts dans `marketing/social-kit/posts/png/` (1080×1080 ;
  story 1080×1920) via Chrome headless (`--headless --screenshot --window-size`),
  aucune install. Total ~1,24 Mo. Chaque PNG vérifié visuellement.
- Correctif RTL sur les 5 fichiers `_ar` : avec `direction="rtl"` sur `<svg>`,
  `text-anchor="end"` faisait déborder le texte hors cadre à droite au rendu Chrome ;
  passé à `text-anchor="start"` (bord droit ancré, flux vers la gauche). p06 : titre
  ré-espacé. Procédure de régénération ajoutée dans `posts/README.md`.
- Recon @dzmarketpro relancée : IG confirme le style poster à plat, bilingue FR/AR,
  bandeau transporteurs, CTA « TÉLÉCHARGEZ DZMARKET » (déjà présents dans le kit) ;
  Facebook et TikTok toujours inaccessibles au fetch (JS). Le résumé IG évoque des
  accents rouge/blanc — la charte du repo est verte : à trancher avec le user si la
  palette social a divergé.
- Base : recon @dzmarketpro (bio IG + page LinkedIn) + `MARKETING_PLAN_DZMARKET_12M.md`
  + charte repo (`assets/branding/`, `lib/src/theme.dart`).
- Convention posée par le user : « mode marketing » = produire des visuels dans
  `C:\src\dzmarket\marketing`, format léger (SVG, pas de cache / PNG lourds).
- **Aucune modification de code / config / prod / app.** Fichiers non commités.

### 2026-09-08 — Codex — vérification locale et coordination
- Lecture de `AGENTS.md`, index agent, fiches projet/QA/risques/workflow, `lib/main.dart`, `lib/src/router.dart` et des sources citées ; aucun ancien JSONL chargé.
- `main` distant vérifié en HTTPS au commit de code `0a009f0`. Journal auparavant non suivi et absent du routage agent ; ajout du lien dans l'index.
- `flutter test --no-pub --reporter expanded` : **135 OK, 2 ignorés** (flow ajout annonce désactivé ; Yalidine live sans credentials). Aucun accès de test à la production.
- `flutter analyze --no-pub` : **échec (code 1), 0 erreur, 2 warnings** `unawaited_return_in_try_block` dans `auth_service.dart:457` et `:459`. Le contrôle analyze de la CI reste donc à corriger et vérifier.
- Findings #1/#2/#3/#4/#6 précisés ci-dessus. Aucun correctif applicatif ni déploiement ; grants/policies live, état des serveurs et erreurs runtime non vérifiés.
- Prochaine action : vérifier les accès publics à `profiles` sans exporter de données personnelles, puis concevoir et tester la séparation public/privé en staging.

### 2026-09-08 — Claude — résumé consolidé dans la fiche
- Ajout du « Résumé par priorité » (🔴 urgent / 🟠 moyen / 🟢 normal) en tête de la
  section findings, au-dessus du tableau détaillé.
- Nouvelle section « Table des erreurs runtime » : schéma `app_errors`, RLS, filtres
  client, 3 voies de lecture read-only + requête SQL de synthèse.
- Toujours aucune modification de code / config / prod — fiche uniquement.

### 2026-09-07 — Claude — fiche + audit lecture seule
- Création de ce `JOURNAL-IA.md`.
- Audit read-only via skills (repo-continuation-brief, env-secrets-ci-audit, skill-scout,
  security-review baseline) + relecture ciblée des chats Codex DZMarket (avr.→sept. 2026).
- 9 findings ouverts consignés ci-dessus. **Aucune modification de code / config / prod.**
- Prochaine étape à décider par le user (remédiation secrets, policy `profiles`, revue Edge Functions…).
