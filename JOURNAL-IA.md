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

### 2026-11-12 - Codex - Search Console verifiee, sans code

- La propriete de domaine `dzmarket.pro` est maintenant verifiee dans Google
  Search Console via l'enregistrement TXT OVH. Le token de verification et les
  informations de compte ne sont pas consignes dans le depot.
- Le sitemap officiel `https://www.dzmarket.pro/sitemap.xml` etait deja soumis,
  avec le statut `Success`, lu le 2026-11-11 et cinq pages decouvertes. Aucune
  soumission en doublon ni deploiement n'a ete fait.
- Search Console indique que les donnees de la nouvelle propriete sont en cours
  de traitement. Attendre environ 24 h avant toute analyse de performance ou
  d'indexation. Les anciennes entrees de sitemap en echec ont ete laissees
  intactes, sans nettoyage non demande.

### 2026-11-12 - Codex - prochaines evolutions acquisition, sans code

- Ajout documentaire uniquement dans `next-release-follow-ups.md` et
  `marketing-seo.md`: audit du lien et de l'apercu de partage d'annonce
  WhatsApp/Facebook, puis mise en place de Google Search Console pour mesurer
  les requetes FR/AR, clics, impressions et pages indexees.
- Aucun code, donnee, configuration Google, configuration serveur ou deploiement
  ne sont modifies. Les donnees Search Console devront guider toute priorite SEO.
- La propriete de domaine `dzmarket.pro` est preparee dans Search Console sous
  le compte Google deja connecte. La verification reste en attente du TXT DNS
  chez OVH; aucun token de verification, mot de passe ou autre secret n'est
  consigne dans le depot.
- Tentative de configuration DNS le meme jour: le compte OVH connecte ne donne
  pas acces a la zone `dzmarket.pro` (aucun domaine disponible dans la console).
  Aucun enregistrement DNS ni validation Search Console n'a ete effectue.

### 2026-11-12 - Codex - evolution reponse vendeur, sans code

- Audit live agrege des conversations: 125 demarrees par un acheteur, dont 65
  sans reponse vendeur; 68 conversations ont eu des messages des deux cotes.
- Le backlog suivante est ajoute a `next-release-follow-ups.md`: accompagnement
  manuel cible, rappel limite et desactivable, badge calcule sur 30 jours, puis
  mise en avant reversible sans retrait automatique d'annonce.
- Aucune conversation, donnee personnelle, code ou configuration de production
  n'est modifiee.

### 2026-11-09 - Codex - lecture seule des erreurs Android recentes

- Controle live de `public.app_errors` et des URLs publiques, sans ecriture.
  Les trois domaines `www`, `app` et `api` repondent HTTP 200; aucun 5xx Caddy
  n'a ete observe sur les sept derniers jours et les conteneurs Supabase sont en
  service.
- Les quatre nouveaux enregistrements des 7-8 novembre sont Android et reseau:
  trois echecs de resolution DNS de `api.dzmarket.pro` et un delai de connexion.
  Ils ne prouvent pas une panne serveur. Sur 30 jours: 12 erreurs, dont 11
  reseau/horloge terminal et une double ouverture du selecteur d'images, deja
  corrigee et publiee dans la release 1.0.9 (44).
- La table ne stocke pas la version/build de l'application dans `context`; ne
  pas attribuer ces erreurs a une release sans telemetrie supplementaire. Aucune
  correction ou migration declenchee par cet audit.

### 2026-11-05 (suite 2) - Claude - release 1.0.9 (44) Android+iOS + ASO arabe, via navigateur piloté (session déjà connectée)

Suite du correctif web : version mobile 1.0.9+44 (`pubspec.yaml`, `codemagic.yaml`,
commit `b86dd24`, poussé) car le build 43 était déjà distribué sur les deux
stores (Play production 1.0.7/43, App Store 1.0.8/43).

- **Android** : AAB buildé (`scripts/build_android_prod.ps1`), uploadé en
  production via `tools/upload_play_bundle.py` (service account
  `C:\Users\ssloc\Secrets\dzmarket-play-service-account.json`, déjà en
  place). Confirmé par l'API Play : `production completed 1.0.9 (44)`.
- **iOS** : build Codemagic déclenché via l'API (`CODEMAGIC_API_TOKEN` déjà
  en variable d'environnement, app id récupéré via l'API Codemagic
  elle-même) — succès de bout en bout, build 44 livré sur TestFlight.
- **ASO arabe appliqué** (texte déjà préparé dans
  `docs/agent/store-aso-dzmarket.md`) via navigateur piloté (Playwright),
  session Google/Apple déjà connectée dans ce profil navigateur :
  - Play Console : titre/description courte FR mis à jour, fiche arabe
    ajoutée (titre, description courte, description complète) — API Play
    directe refusée (403, permission "Store presence" absente du service
    account), donc fait via l'interface web ; soumis pour révision Google
    (délai habituel jusqu'à 7 jours).
  - App Store Connect : nouvelle version App Store 1.0.9 créée (manquait,
    Codemagic n'uploade que vers TestFlight), build 44 attaché, notes de
    version FR+AR renseignées, localisation arabe ajoutée (description,
    mots-clés) à la page produit. Questionnaire de classification par âge
    (nouveau, obligatoire, 7 étapes) rempli selon le contenu réel de l'app
    (marketplace + chat, aucun contenu sensible) — résultat 4+, cohérent
    avec la classification existante. Soumis pour vérification Apple
    (délai annoncé jusqu'à 48h).
- **Non fait** : `Nom`/`Sous-titre` arabe au niveau "Informations sur
  l'app" (partagé entre versions) — Apple les a listés comme inclus dans
  la soumission mais ils n'ont pas été explicitement saisis dans cette
  session ; à vérifier une fois la version 1.0.9 traitée.

### 2026-11-05 (suite) - Claude - correctif prod : templates mot de passe oublié/confirmation 404 + permissions

Demande fondateur : avant de préparer une nouvelle version iOS/Android/web,
vérifier la table d'anomalies (`public.app_errors`, lecture seule via
`docker exec -i supabase-db psql ...` sur `dzm-app-01`, méthode déjà
documentée plus bas) et tester même le parcours « mot de passe oublié »,
sans risque ni régression.

- **Anomalies des 14 derniers jours** : 3 seulement, aucune critique —
  sélecteur d'images Android déclenché en double-tap (04/11, déjà corrigé
  par le commit `64716b0`, testé), coupure réseau client (30/10), horloge
  téléphone en avance `JWT issued at future` (29/10, jamais revu). `www`/
  `app`/`api` → 200. Livraison (`public.seller_delivery_settings`) :
  Yalidine/Ecotrack/Guepex valides, 1 config ZR Express invalide depuis le
  30/06 — propre à un vendeur, pas un bug plateforme.
- **Tests** : `dart analyze` propre (2 avertissements de style
  préexistants, sans rapport), `flutter test` 151/151 verts, phase smoke
  `integration_test` (auth, RLS, ZR Express E.164) rejouée en réel sur le
  Samsung branché en USB (`R5CNC13Y7WN`) via
  `scripts/run_quality_gate.ps1 -RunIntegration` — tout vert.
- **Anomalie réelle trouvée en testant le mot de passe oublié** (invisible
  dans `app_errors`, car côté serveur GoTrue, pas côté client) : les
  templates e-mail personnalisés `auth-email/confirmation.html` et
  `auth-email/recovery.html` (configurés dans
  `GOTRUE_MAILER_TEMPLATES_CONFIRMATION`/`RECOVERY`, requis par GoTrue
  pour l'envoi) répondaient **404** en prod sur `app.dzmarket.pro`. Vérifié
  présent dans le rollback précédent aussi (`dzmarket-web-rollback-
  20261103-122702`) : régression antérieure à cette session, pas introduite
  aujourd'hui — jamais détectée car `verify_web_artifact.ps1` ne vérifiait
  que favicon/polices, pas ce dossier.
- **Corrigé** : rebuild propre (`flutter build web --release
  --no-tree-shake-icons --dart-define-from-file=test/test_env.json`,
  confirmé nécessaire : sans ce flag, les polices d'icônes repartent en
  quasi-zéro octet) ; `auth-email/*.html` bien présents dans ce build.
  `scripts/verify_web_artifact.ps1` étendu pour vérifier aussi
  `auth-email/confirmation.html`/`recovery.html` (évite la régression
  silencieuse à l'avenir). `README.md` corrigé : la commande de build web
  documentée omettait `--no-tree-shake-icons`.
- **Incident rencontré pendant le déploiement et corrigé** : l'archive
  zip créée par `Compress-Archive` (PowerShell) stocke les chemins avec
  des barres obliques inverses ; `unzip` côté Linux a extrait les fichiers
  correctement mais a laissé 7 répertoires sans bit d'exécution (`assets/
  packages`, `assets/packages/cupertino_icons`, `assets/marketing/*`,
  `assets/assets`) — Caddy renvoyait alors **403** sur
  `CupertinoIcons.ttf` (fichier présent, répertoire parent non
  traversable). Corrigé par `chmod 755` récursif sur tous les répertoires
  du déploiement actif ; plus aucun répertoire sans bit d'exécution après
  vérification.
- **Déployé** : bascule atomique habituelle (nouvelle release
  `/var/www/dzmarket-web-releases/20261105-172631` → `config.json` prod
  copié sans affichage → ancien actif renommé en rollback, nouvelle
  release promue active). Ancien rollback `dzmarket-web-rollback-
  20261103-122702` supprimé avant la bascule pour rester à « actif +
  exactement un rollback » ; nouveau rollback conservé :
  `dzmarket-web-rollback-20261105-172631`.
- **Vérifié après coup** : `www`/`app`/`api` → 200 ; favicon, les deux
  polices d'icônes et les deux templates `auth-email` → 200 publiquement ;
  page d'accueil chargée en Playwright, 0 erreur/avertissement console ;
  13 conteneurs Supabase toujours actifs (compte inchangé).
- **Hors périmètre cette fois** (signalé, pas corrigé) : config ZR Express
  invalide d'un vendeur précis depuis le 30/06 — décision vendeur, pas
  correctif plateforme. Préparation ASO (textes Play/App Store) déjà prête
  dans `docs/agent/store-aso-dzmarket.md` (travail du même jour) ; bump de
  version mobile (build 43 déjà distribué en 1.0.8) et déclenchement
  Codemagic/Play restent à faire — en attente des accès (JSON compte de
  service Play, déclenchement Codemagic) avant de poursuivre.

### 2026-11-03 - Claude - nettoyage serveur/local autorisé (safe-space-cleanup)

- Suite au déploiement du correctif polices/favicon (entrée précédente), le fondateur a explicitement autorisé le nettoyage disque multi-serveurs ("/safe-space-cleanup", puis précision "tout les serveurs sans rien casser de mihna et elhimma, nettoie les anciens build et fichiers non utilisés dzmarket").
- Baseline relevée sur les 3 serveurs DZMarket avant toute suppression : `dzm-app-01` 88% utilisé (9.0G libre), `dzm-db-01` 4% (70G libre, rien à nettoyer), `dzm-storage-01` 3% (141G libre, 1 image Docker 100% active, rien à nettoyer).
- `dzm-app-01` : supprimé les dossiers devenus orphelins après vérification de taille/contenu (tous 53M, aucun n'est le rollback le plus récent) — `dzmarket-web.release.20260914-121425`, `dzmarket-web.rollback.20260914-1327-admin-phone`, `dzmarket-web-rollback-20261009-1554`, `dzmarket-web-rollback-20261103-113936` (rollback de l'ancien déploiement SEO, confirmé vide de besoin puisque le rollback `dzmarket-web-rollback-20261103-122702` du déploiement du jour reste disponible), le dossier vide `dzmarket-web-rollbacks`, et l'archive `/tmp/dzmarket-web-seo-20261103-113936.zip` déjà extraite. ~212 Mo libérés ; conforme à la règle "actif + exactement un rollback" de `docs/agent/server-ops.md`.
- Local (`C:\src\dzmarket`) : supprimé 4 anciennes archives de packaging web (`dzmarket-web-ba7aeca.zip`, `dzmarket-web-deploy-20261009-1430.tar.gz`/`.zip`, `dzmarket-web.zip`) et les caches de build non suivis par git `.codex-tmp/` (219 Mo — `gradle-8.14-all.zip` + `gen_snapshot-copy.EXE`, régénérables) et `android/build/` (132K).
- Vérification après coup : `www`/`app`/`api` + les 2 URLs de polices + favicon toujours HTTP 200 ; conteneurs Supabase sur `dzm-app-01` inchangés (13/13 actifs).
- Hors périmètre, non touché : le serveur partagé Mihna/El-Himma (`mihna.pro`) a reçu un nettoyage séparé et strictement conservateur (cache de build Docker + 2 images orphelines + archives `/tmp` déjà extraites) — journalisé côté El-Himma, pas dans ce dépôt.

### 2026-11-03 - Claude - finalise le correctif polices/favicon web et deploie

- Reprise d'une tache commencee par Codex (quota epuise avant la bascule) : le commit `f97dfe4` (garde `scripts/verify_web_artifact.ps1` + `docs/agent/web-release.md`) etait deja pousse sur `origin/main`, et `build/web` contenait deja les 3 ressources manquantes (favicon, MaterialIcons, CupertinoIcons) suite au rebuild sans tree-shaking d'icones.
- Verification locale : `verify_web_artifact.ps1` passe sur `build/web` ; `version.json` confirme `1.0.7 / build 43`.
- Acces SSH `dzm-app-01` : la cle `dzmarket_hetzner` est deja chargee dans l'agent SSH natif Windows (service `ssh-agent`), inutilisable depuis Git Bash (pas le meme canal d'agent) mais fonctionnelle depuis PowerShell.
- Deploiement : archive `build/web` -> `/tmp` -> nouvelle release `/var/www/dzmarket-web-releases/20261103-122702` -> `config.json` prod copie depuis l'actif -> bascule atomique (`mv` ancien actif en rollback `dzmarket-web-rollback-20261103-122702`, nouvelle release renommee en actif). `dzmarket-web-releases/` confirme vide apres.
- Verification finale : `www`, `app`, `api` HTTP 200 ; les 2 URLs de polices d'icones et le favicon renvoient maintenant 200 (etaient en 404). Archive `/tmp` de ce deploiement supprimee.
- Non touche (hors perimetre de cette tache) : les rollbacks/releases orphelins plus anciens deja releves par l'audit du 2026-10-13/2026-11-03 (`dzmarket-web.release.20260914-121425`, `dzmarket-web.rollback.20260914-1327-admin-phone`, `dzmarket-web-rollback-20261009-1554`, `dzmarket-web-rollbacks`, et l'archive `dzmarket-web-seo-20261103-113936.zip` restee dans `/tmp`) — leur suppression reste une action a part, non autorisee dans cette session.

### 2026-10-24 - Codex - audit lecture seule livraisons, chat et abus

- Livraison: 8 configurations pour 2 vendeurs (Yalidine, Ecotrack, Guepex, ZR Express); 7 valides et 1 ZR Express invalide avec un echec, dernier controle le 2026-06-30. Aucune cle ou identite exposee.
- Echanges: 141 conversations, dont 122 avec message; 512 messages approuves. Activite recente faible mais reelle (3 conversations, 8 messages sur 7 jours). Aucun emetteur a 50 messages ou plus sur 24 h.
- Revue des 3 conversations recentes: aucun abus ni partage de coordonnees observe; un message systeme `Nouveau contact` est double dans un echange, a verifier plus tard sans correction automatique.
- Moderation: aucun signalement sur 30 jours; historique de 4 signalements annonce, 1 signalement utilisateur et 3 blocages. 12 annonces masquees et 1 bloquee. Anomalies a examiner manuellement: 19 conversations vides et 73 commandes ouvertes depuis plus de 30 jours (46 `shipped`, 27 `pending`); aucune action automatique appliquee.

### 2026-10-24 - Codex - nettoyage prudent espace disque

- Apres controles HTTP 200 et conteneurs actifs, suppression des deux rollbacks web excedentaires, d'une release staged orpheline, de deux archives deploiement et de journaux archives de plus de 14 jours (~290 Mo).
- Release active et rollback `20261009-1554` conserves. Aucun volume, DB, upload, bucket, secret, configuration ou conteneur actif touche. `docker image prune -af` et `docker builder prune -af` n'ont rien trouve a recuperer.
- `app.dzmarket.pro`, `www.dzmarket.pro` et `api.dzmarket.pro` verifies HTTP 200 apres nettoyage. Le disque reste a 83% car `/opt/supabase/docker/volumes` occupe ~40 Go: donnees actives, volontairement non touchees.

### 2026-10-24 - Codex - audit reseau et runtime lecture seule

- Disponibilite publique verifiee: `www.dzmarket.pro`, `app.dzmarket.pro` et `api.dzmarket.pro` repondent HTTP 200. Stack Supabase, PostgreSQL et MinIO actifs; aucune erreur client dans `public.app_errors` sur les 7 derniers jours.
- Surface publique verifiee depuis l'exterieur: seuls SSH, HTTP et HTTPS sont accessibles; ports internes analytics, PostgreSQL, pooler, Kong et MinIO filtres. Aucun changement prod, code ou configuration.
- Point de surveillance: disque `dzm-app-01` a 83% (13 Go libres), sans saturation. Logs Caddy: quelques deconnexions clients et un message ponctuel de motif glob invalide le 22 octobre; configuration actuelle valide et services fonctionnels.

### 2026-10-09 - Claude - push main + tentative déploiement web/mobile

- Vérifications avant push : `git status --short --branch`, `git log --oneline -5`
  confirmés (commits `0455048`/`3672620`/`9b71233` seuls en avance) ; `git show
  --stat` sur chacun confirme aucun fichier hors sujet (`analysis_options.yaml`,
  `android/gradle.properties`, `.codex-tmp/`, `android/build/`,
  `marketing/social-kit/` toujours non commités, intacts) ; `flutter analyze
  --no-pub` → 2 warnings historiques seulement ; `flutter test --no-pub
  --reporter expanded` → **142 OK, 2 skipped**, 0 régression.
- **Push effectué** : `git push origin main` → `d54f0e2..9b71233 main -> main`.
  `main` est maintenant à jour avec `origin/main`.
- **Déploiement web NON fait** : la lecture SSH en lecture seule sur
  `dzm-app-01` (`91.107.239.5`) a été refusée par le classifieur auto-mode de
  l'environnement (catégorie "Production Reads"). Pas de contournement tenté
  (ni autre outil, ni autre host/encodage) — conforme à la consigne de
  l'environnement. Nécessite soit un run en mode autorisant les accès
  production, soit une action manuelle de l'utilisateur.
- **Build Android AAB bloqué** : `test/test_env.json` toujours absent de ce PC
  (blocage déjà documenté le 2026-09-10, non résolu depuis). Signature release
  et `google-services.json` prod sont bien présents ; seul le fichier d'env
  manque. Aucun AAB généré. Upload Play Console : aucun identifiant/outil
  d'automatisation (pas de compte de service, pas de fastlane) présent sur ce
  PC — upload manuel requis de toute façon.
- **iOS Codemagic NON déclenché** : aucun `CM_API_TOKEN`/CLI Codemagic
  configuré sur ce PC pour déclencher le workflow `DZMarket iOS TestFlight` à
  distance ; les secrets iOS vivent dans le groupe Codemagic `dzmarket_secrets`
  (pas affectés par le blocage `test_env.json` local, mais le déclenchement
  lui-même doit se faire depuis le dashboard Codemagic ou avec un token API).
- Aucune modification de code ce tour-ci ; seulement vérification + push +
  journal.

### 2026-10-09 - Claude - section découverte "Selon vos intérêts" (MVP)

- Nouvelle rangée optionnelle au-dessus de la grille d'annonces
  (`_InterestsSection` dans `listings_page.dart`), **code uniquement, rien
  déployé ni poussé** : montre jusqu'à 10 annonces d'une catégorie déduite
  des signaux déjà disponibles — catégorie de la recherche sauvegardée la
  plus récente, sinon catégorie la plus fréquente parmi les favoris
  (requête `products.category_id` bornée aux 50 derniers favoris). **Aucun
  signal connu → la section ne s'affiche pas du tout**, donc le comportement
  par défaut (annonces récentes dans la grille) reste identique à avant pour
  tout visiteur sans historique ou déconnecté.
- Pas de géolocalisation, pas de scoring IA, pas de mélange avec du contenu
  sponsorisé (aucun concept de sponsoring dans le repo) ; la grille et les
  filtres existants ne sont pas touchés — section strictement additive,
  bouton "Masquer" pour la désactiver pour la session en cours (réversible,
  ne supprime ni recherche sauvegardée ni favori).
- Réutilise `_ProductCard`, `FavoriteService`, `SavedSearchService`,
  `ProductService.fetchProducts` existants ; nouvelles clés FR/AR
  `listing.interests.title` / `listing.interests.dismiss` dans `i18n.dart`.
- Test ciblé ajouté `test/listings_interests_test.dart` : vérifie qu'un
  visiteur déconnecté ne voit jamais la section et que la bannière invité
  existante s'affiche inchangée.
- Vérification : `flutter analyze --no-pub` → 2 warnings historiques
  uniquement ; `flutter test --no-pub test/i18n_runtime_sanity_test.dart` →
  2/2 OK ; suite complète → **142 OK, 2 ignorés, 0 régression**.
  `analysis_options.yaml`/`android/gradle.properties` toujours exclus du
  commit (hors sujet, cf. entrée précédente). Commit `3672620`, local
  uniquement, pas de push.

### 2026-10-09 - Claude - complète les garde-fous Codex + commit vérifié

- Suite à l'audit Codex du 2026-10-08 (priorité: annonces complètes/localisables/
  fiables avant nouvelles fonctions), ajout de 3 compléments ciblés, **code
  uniquement, rien déployé ni poussé** :
  1. `ProductService.createProduct` : détection de doublon avant insertion
     (même `owner_id` + titre identique insensible à la casse + même prix) ;
     bloque avec `listing.add.error_duplicate` si trouvé. Étend le garde-fou
     Codex (images/catégorie/état/wilaya) sans toucher son comportement existant.
  2. `ListingsPage` : nouveau chip de filtre rapide "Livraison à convenir"
     (`_quickPickupOnly`, filtre client sur `deliveryOptions.contains('pickup')`),
     câblé dans `_queryKey`, `_applyClientFilters`, `_currentFilters`,
     `_applySavedSearch`, `resetLocal` (x2) et `_clearFilters` — même traitement
     que `_quickDeliveryOnly` existant.
  3. `PublicProfilePage` : badge "N annonces actives" à côté de la note moyenne,
     basé sur `_products.length` déjà chargé (aucun nouveau champ BDD, aucune
     requête supplémentaire).
  - Nouvelles clés FR/AR dans `i18n.dart` : `listing.add.error_duplicate`,
    `profile.listing_count_one`, `profile.listing_count_other`. Le chip pickup
    réutilise la clé existante `listing.add.delivery_pickup`.
- Vérification de clôture (sur ce PC, Flutter non bloqué) : `flutter analyze
  --no-pub` → 2 issues, uniquement les warnings historiques
  `auth_service.dart:457/459` déjà documentés depuis le 2026-09-08 ; `flutter
  test --no-pub test/i18n_runtime_sanity_test.dart` → 2/2 OK ; `flutter test
  --no-pub --reporter expanded` (suite complète) → **141 OK, 2 ignorés, 0
  régression**. `pubspec.lock` : touché une fois par un `flutter run` local
  (bump de versions transitives), restauré via `git checkout --` avant de
  continuer — aucun changement de dépendance committé.
- Migration `supabase/migrations/20261008120000_fix_category_labels_fr_ar.sql`
  (déjà appliquée en prod par Codex le 2026-10-08, fichier jusque-là non
  committé) vérifiée : `charset=utf-8` confirmé, 0 caractère de remplacement,
  contient bien les échantillons attendus (`Beauté & Santé`, `Électronique`,
  `Téléphones`, `الجمال والصحة`, `إلكترونيات`). **Ne pas la réappliquer en
  prod** — elle est idempotente mais déjà live ; ce commit ne fait que
  l'ajouter à l'historique git.
- `analysis_options.yaml` et `android/gradle.properties` restent modifiés dans
  le worktree (exclusions analyzer + flags migrateur Flutter, déjà notés dans
  l'entrée du 2026-09-10) mais **exclus de ce commit** : aucun rapport avec les
  catégories/qualité annonces, décision produit Android séparée à prendre par
  le user plus tard.
- Commit préparé avec uniquement : `JOURNAL-IA.md`,
  `docs/agent/db-and-migrations.md`, `lib/src/services/product_service.dart`,
  `lib/src/features/listings/listings_page.dart`,
  `lib/src/features/profile/public_profile_page.dart`,
  `lib/src/services/i18n.dart`, `test/i18n_runtime_sanity_test.dart`,
  `supabase/migrations/20261008120000_fix_category_labels_fr_ar.sql`. Pas de
  push — à faire seulement sur validation explicite du user.

### 2026-10-08 - Codex - audit BDD et garde-fous qualité annonces

- Audit production DZMarket en lecture seule: stack app/API OK, `app_errors` récent vide, anomalies principales identifiées sur profils incomplets, annonces sans image/localisation/catégorie, quelques doublons et catégories mojibake.
- Ajout d'une migration idempotente limitée à `public.categories` pour restaurer les libellés FR/AR propres par `slug`, avec accents français et orthographe arabe vérifiés depuis les clés runtime.
- Production: sauvegarde `supabase_migrations.categories_backup_20261008_before_label_fix`, migration appliquée via transfert base64 UTF-8, vérification hex OK (`?`/replacement char = 0).
- Ajout d'un garde-fou applicatif dans `ProductService.createProduct`: les nouvelles annonces doivent conserver au moins 2 images, une catégorie, un état et une wilaya avant insertion.
- Test i18n renforcé pour couvrir les libellés de recherche locale, erreurs de publication et catégories FR/AR critiques.

### 2026-09-30 — Claude — token API Hetzner Cloud créé (diagnostic blocage IP)

- User a un serveur `mihna-app-01` (CX23, IP `167.233.139.38`) bloqué par Hetzner
  (page Console : "IP address of this server is blocked" → flux d'abus réseau,
  pas une suspension pour impayé). Ce serveur vit dans le projet Hetzner
  **DZMarket-Prod** mais **n'est pas** l'un des 3 hôtes DZMarket documentés
  (`dzm-app-01` 91.107.239.5 / `dzm-db-01` 46.225.88.249 / `dzm-storage-01`
  91.98.227.237) — son rôle réel reste à confirmer par le user avant toute action
  dessus.
- Aucun connecteur MCP Hetzner disponible côté Claude. Le user a créé un **token
  API Hetzner Cloud** dans Console → DZMarket-Prod → Security → API tokens :
  nom `IA-diagnostic`, portée **Read+Write** (choix explicite du user, pas le
  Read-only initialement suggéré — donc capable de créer/redémarrer/reconstruire/
  supprimer n'importe quelle ressource du projet DZMarket-Prod, pas seulement lire).
- Convention à réutiliser par Claude **et Codex** : le token est stocké en variable
  d'environnement Windows **`HETZNER_CLOUD_TOKEN`** (persistant via `setx`, pas
  `$env:` qui ne survit pas à un nouveau process). **Ne jamais** redemander sa
  valeur en chat, ne jamais l'afficher, ne jamais le committer — le traiter comme
  un mot de passe, au même titre que les clés SSH `dzmarket_hetzner`.
- Portée Read+Write = même règle « aucune modif à risque / aucune régression »
  que pour SSH/déploiement : toute action d'écriture via ce token sur une
  ressource de prod (reboot, resize, delete, rebuild) doit suivre la même
  prudence que documentée plus haut dans ce journal, pas être traitée comme un
  simple appel API de confort.
- Statut à la clôture de cette entrée : token créé, **pas encore utilisé** —
  `setx` en cours côté user, aucune requête API lancée, aucune cause du blocage
  identifiée, aucune action de déblocage effectuée.

### 2026-09-14 - Codex - admin telephones utilisateurs + deploy web Hetzner

- Claude avait compris "vrai numero des users" comme **nombre total** d'utilisateurs
  et avait ajoute un count best-effort. Ce count est conserve car non bloquant, mais
  le besoin metier etait surtout: afficher le **telephone reel** des utilisateurs
  dans l'onglet admin moderation.
- Correctif web/admin: `lib/src/features/admin/moderation_admin_page.dart` charge
  maintenant `profiles.phone`, l'affiche dans la fiche utilisateur admin, et la
  recherche admin matche aussi le telephone. Aucun changement public/RLS, aucun
  secret, aucune migration.
- Verification locale: `flutter test test\admin_owner_display_test.dart --no-test-assets`
  OK; `flutter test --no-test-assets` OK (`141 OK, 2 skipped`); `flutter analyze
  --no-pub` garde seulement les 2 warnings historiques `auth_service.dart:457/459`.
- Deploy web effectue sur `dzm-app-01` (`91.107.239.5`) avec la cle attendue
  `C:\dzm-deploy\dzmarket_hetzner`. Ne pas redemander au user si cette cle existe:
  verifier en lecture seule puis deployer. Toujours utiliser Caddy/Hetzner, pas nginx.
- Flow web a reutiliser par Claude/Codex:
  1. `flutter build web --release --no-pub` si le PC a deja ses deps et qu'il faut
     eviter de modifier `pubspec.lock`; sinon `flutter build web --release`.
  2. Uploader l'artefact vers `/tmp`, extraire dans
     `/var/www/dzmarket-web.release.<timestamp>`.
  3. Copier **sans afficher** `/var/www/dzmarket-web/config.json` vers la release
     avant bascule; ne jamais remplacer par `config.example.json`.
  4. Renommer l'actif en `/var/www/dzmarket-web.rollback.<timestamp>`, puis la release
     en `/var/www/dzmarket-web`.
  5. Verifier `https://app.dzmarket.pro`, `https://www.dzmarket.pro`,
     `https://api.dzmarket.pro`, presence de `config.json`, containers Supabase.
  6. Garder l'actif + un rollback recent; nettoyer seulement archives `/tmp` et
     vieux rollbacks inactifs. Ne jamais supprimer volumes, DB, buckets, secrets,
     `/opt/supabase/docker/volumes`, ou containers actifs.
- Deploiement verifie: `app.dzmarket.pro`, `www.dzmarket.pro` et `api.dzmarket.pro`
  repondent HTTP 200; `config.json` prod conserve; rollback
  `/var/www/dzmarket-web.rollback.20260914-1327-admin-phone` conserve.

### 2026-09-10 — Claude — build AAB Android demandé (post-changements Codex)

- Contexte : Codex a modifié le code Android récemment — commits `ced9e3a`
  (plugin Kotlin), `15f5d37` (alignement outillage Android + build number iOS),
  `17529c0` (build number → 40) ; + non commité dans le worktree :
  `analysis_options.yaml` (exclusions analyzer), `android/gradle.properties`
  (flags migrator `android.builtInKotlin=false` / `android.newDsl=false`),
  `pubspec.lock`. Version courante `1.0.7+40`.
- **Prêt pour le build** : Flutter 3.47.2 / Dart 3.13.2, JDK 21, Android SDK
  `C:\src\tools\android-sdk` ; signature release câblée (`android/key.properties`
  + `android/app/upload-keystore.jks`) ; `google-services.json` par flavor présent
  (`android/app/src/prod/`).
- **Bloqueur** : `test/test_env.json` absent de ce PC (fichier gitignoré, non
  repris lors de la migration PC ; introuvable dans Documents/Desktop/Downloads/
  `C:\src`/`Historique`). Le build prod lit ses `--dart-define` via ce fichier.
  Sans lui : `lib/main.dart:44` lève `StateError('Supabase URL/anon key
  manquants')` → l'app ne démarre pas ; `auth_service.dart:28` → bouton Google
  masqué. Un AAB généré maintenant serait signé mais **non fonctionnel**.
- Clés minimales requises par `flutter build appbundle` (pas les secrets
  transporteurs/comptes de test, qui ne servent qu'aux tests d'intégration) :
  `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_WEB_CLIENT_ID`
  (+ `GOOGLE_IOS_CLIENT_ID`, ignoré sur Android). Ces 3 valeurs sont **publiques**
  (déjà embarquées dans chaque APK/web en prod) — dispo aussi dans Codemagic →
  groupe `dzmarket_secrets`. Repartir de `test/test_env.example.json`.
- Commande de build (une fois `test/test_env.json` restauré) :
  ```powershell
  cd C:\src\dzmarket
  flutter pub get
  flutter build appbundle --release --flavor prod -t lib/main.dart --dart-define-from-file=test/test_env.json
  ```
  Sortie : `build\app\outputs\bundle\prodRelease\app-prod-release.aab`.
- À vérifier avant upload Play : que le build **40** n'est pas déjà utilisé sur la
  Play Console (sinon passer `1.0.7+41` dans `pubspec.yaml`). CI `flutter analyze`
  toujours en échec (2 warnings `unawaited_return_in_try_block`
  `auth_service.dart:457/459`) — n'empêche pas le build, à corriger à part.
- **Aucune modification de code / config / prod / app.** Rien commité.

### 2026-09-09 - Codex - livraison web et nettoyage controle

- Commit `ba7aeca` deploye sur le web; `app.dzmarket.pro` ouvre maintenant l'onglet annonces avec recherche, filtres et consultation anonyme.
- Les fonctions `validate-courier` et `create_shipment` ont ete remplacees avec rollback conserve et le conteneur Edge Functions est reste `running`.
- Le `config.json` runtime existant a ete preserve; son BOM UTF-8 a ete retire sans afficher ni modifier ses valeurs.
- Smoke final: app/www/api HTTP 200; auth, Kong, DB, storage et Edge Functions actifs.
- Nettoyage: anciens dossiers web, anciennes archives rollback et temporaires supprimes; actif et rollback `20260909-133524` conserves. `marketing/social-kit/` reste local et non suivi.

### 2026-09-09 - Codex - URL Ecotrack par vendeur et affichage admin

- Ajout d'une URL HTTPS Ecotrack par compte vendeur, validation serveur avec hôtes autorisés et utilisation de cette URL pour l'expédition et l'étiquette.
- L'admin affiche maintenant le nom complet ou l'email du vendeur, avec son identifiant conservé pour audit, dans les annonces et signalements.
- La séparation `www` marketing / `app` annonces reste protégée par le test de routage existant; aucun changement de navigation globale.
- Tests ciblés ajoutés pour URL Ecotrack et résolution du nom vendeur; nettoyage production prévu seulement après build sain et rollback conservé.
- Aucun secret ajouté au dépôt; les anciens artefacts serveur ne seront supprimés qu'après vérification de la version active.

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

### 2026-10-09 - Codex - Android Play production 1.0.7+42
- Recreated local-only `test/test_env.json` without printing values: Supabase public runtime config from `app.dzmarket.pro/config.json`, Google OAuth web client from `ios/Runner/Info.plist`; file remains gitignored.
- Android release identity: package `com.dzmarket.app`, version `1.0.7+42`; release signing, prod Firebase config and Play service account path present.
- Checks: `flutter analyze --no-pub` = only 2 historical warnings in `auth_service.dart:457/459`; full `flutter test --no-pub --reporter expanded` = 142 OK, 2 skipped; targeted i18n/interests tests OK after lockfile refresh.
- Build: `.\scripts\build_android_prod.ps1` generated `build/app/outputs/bundle/prodRelease/app-prod-release.aab`; script now uses locked deps, `--no-pub`, sanitized logs, and Flutter dependency validation bypass for current AGP 8.9.1 hotfix.
- Play upload: first attempt with versionCode 41 rejected because already used; bumped build number only to 42 and uploaded versionCode 42 to production as `completed`.
- Tooling notes: Gradle wrapper moved from 8.12 to 8.14 for Flutter 3.47.2; AGP/Kotlin upgrade intentionally deferred. No secrets printed.

### 2026-10-13 - Codex - nettoyage prudent serveurs DZMarket

- Nettoyage effectue sur les 3 serveurs `dzm` apres verification sante, sans redemarrer de service et sans toucher DB, volumes, uploads, buckets, `.env`, cles, containers actifs ou release active.
- `dzm-app-01`: `app.dzmarket.pro` et `api.dzmarket.pro` HTTP 200 avant/apres; disque 84% -> 83%; suppression d'un conteneur arrete, d'une image Docker inutilisee `minio/mc`, et des journaux systeme archives de plus de 14 jours (~1 Go libere).
- `dzm-db-01`: PostgreSQL actif et port 5432 en ecoute; disque 5% -> 4%; nettoyage uniquement des journaux anciens (~922 Mo liberes).
- `dzm-storage-01`: MinIO actif et health OK; disque 4% -> 3%; suppression d'une image Docker inutilisee `minio/mc` et journaux anciens (~1.5 Go + 22 Mo liberes).
- Instruction renforcee: `docs/agent/server-ops.md` garde la checklist de nettoyage safe post-build/deploy; `docs/agent/workflow-rules.md` impose maintenant de mettre a jour `JOURNAL-IA.md` apres toute operation prod/deploy/cleanup/audit/handoff significatif.

### 2026-11-01 - Codex - audit lecture seule des anomalies app

- Controle live de `app_errors`, des conteneurs Supabase, de Caddy et des URLs publiques; aucune ecriture, aucun changement de code ou de donnees.
- Les 10 erreurs conservees sont toutes anciennes; aucune erreur enregistree dans les dernieres 48 h. L'archive admin contient aussi les erreurs de plus de 48 h et les doublons: elle ne signifie donc pas qu'une erreur est resolue.
- Le 30 octobre, une seule erreur Android a touche un seul utilisateur: interruption reseau vers `api.dzmarket.pro` a 13:19 UTC. Aucun incident Caddy/Kong correle; ce n'est pas une panne serveur confirmee.
- Verification finale: stack en service; `app.dzmarket.pro`, `www.dzmarket.pro` et `api.dzmarket.pro` repondent HTTP 200.

### 2026-11-03 - Codex - renforcement SEO public et comprehension IA

- `web/index.html` renforce le site officiel `www.dzmarket.pro` avec des donnees structurees statiques `Organization`/`OnlineStore` et `WebSite`, liees aux stores et profils officiels.
- Ajout d'une section publique FR/AR factuelle qui distingue le site officiel de l'application et rend le support joignable; aucune annonce, base de donnees, authentification ou application mobile n'est modifiee.
- `docs/agent/marketing-seo.md` documente la regle durable: contenu exact, pas de promesse de classement Google ou de citation par une IA, verification Search Console avant toute suite.
- Deploiement web du commit `120d4ba`: build release valide, bascule atomique avec conservation de `config.json`, puis `www`, `app` et `api` verifies HTTP 200. Le nouveau rollback `dzmarket-web-rollback-20261103-113936` est conserve; le nettoyage des rollbacks plus anciens et de l'archive temporaire a ete refuse avant execution par la protection de l'environnement, donc rien n'a ete supprime.

### 2026-11-05 - Codex - garde-fou image et preparation ASO FR/AR

- Une erreur Android confirmee du 4 novembre (`File picker is already active`)
  est corrigee localement: l'ajout d'images ignore les doubles appuis pendant
  l'ouverture du selecteur et redevient disponible dans `finally`. Aucun
  changement de donnees, de schema, d'authentification ou de configuration.
- Un test widget couvre le double-appui; `flutter analyze --no-pub` garde les
  deux warnings historiques dans `auth_service.dart`, et la suite complete est
  verte (`151 OK, 2 ignores`). Le correctif n'est pas encore deploye ni publie
  dans les stores.
- Audit public: Play et App Store sont accessibles; l'arabe est deja visible
  dans la description Play, mais les champs d'indexation arabe/francais sont
  prepares dans `docs/agent/store-aso-dzmarket.md`. App Store exige une nouvelle
  version avec un build frais pour ces changements de nom/sous-titre/mots-cles.
- `robots.txt` et `sitemap.xml` existent dans le depot mais repondaient 404 en
  production au controle. Le gate web exige maintenant leur presence dans tout
  futur artefact; aucune bascule web n'a ete faite dans cette intervention.
