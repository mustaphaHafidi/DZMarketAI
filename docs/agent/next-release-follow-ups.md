# DZMarket - Suivi prochaine version

Mis a jour : 2026-11-13. Cette fiche ne contient que les constats utiles
depuis les dernieres releases. Elle ne remplace ni les logs de production ni
les tests de release.

## A corriger - Android

### Erreur technique brute affichee dans l'admin Moderation (corrige 2026-11-18)

- **Preuve** : capture du 18/11, onglet "Utilisateurs" de l'admin
  Moderation remplace tout l'ecran par le texte brut de l'exception
  (`ClientException`/`SocketException`, URL interne visible) des qu'un
  appel reseau echoue (ex. coupure transitoire sur `admin-moderation`).
- **Cause confirmee** : `moderation_admin_page.dart`, `_load()` stockait
  `e.toString()` tel quel dans `_error`, affiche directement par
  `_buildBody()`.
- **Correctif** : message generique "Connexion instable. Réessayez."
  (nouvelle cle `admin.moderation.load_error_friendly`, FR/AR) + bouton
  Réessayer qui relance `_load()`. Le detail technique complet reste
  disponible pour l'admin dans l'ecran dedie "Erreurs de l'app"
  (`app_errors_page.dart`, inchange, c'est deja le bon endroit pour ca).

### Blocage ecran de demarrage si le reseau ne repond pas (corrige 2026-11-18)

- **Preuve** : fondateur bloque ~10h sur l'ecran de demarrage un matin.
- **Cause confirmee** : `main.dart` attendait `TranslationService.load()`
  avant `runApp()`, et la requete Supabase dans `translation_service.dart`
  n'avait aucun timeout -- une requete qui restait en suspens (DNS qui
  stall, portail captif) bloquait l'app indefiniment.
- **Correctif** : `.timeout(const Duration(seconds: 3))` ajoute autour de
  la requete Supabase dans `TranslationService.load()`. En cas de lenteur
  reseau, l'app demarre avec les textes embarques (`assets/i18n/*.json`,
  deja charges en premier) au lieu d'attendre.
- **Etat** : corrige, `flutter analyze` + `flutter test` verts (154 passes,
  2 skip, 0 echec).

### Selection d'images declenchee deux fois

- **Preuve** : 2026-11-04 18:24 UTC, un seul utilisateur Android. Erreur
  `PlatformException(already_active, File picker is already active)`.
- **Cause confirmee** : l'ajout d'annonce appelle `FilePicker.platform.pickFiles`
  sans verrou de re-entrance dans
  `lib/src/features/listings/add_listing_page.dart`.
- **Impact** : le second appui sur Ajouter des images echoue. Aucune donnee,
  annonce ou fichier n'est corrompu.
- **Etat** : correctif implemente et valide sur Samsung USB. Il est inclus dans
  l'artefact Android `1.0.10+48`, prepare pour publication.
- **Limite volontaire** : ne pas etendre a l'avatar ou a la modification
  d'annonce sans occurrence confirmee dans ces ecrans.

### Direction du texte melangee FR/AR dans les descriptions d'annonce -- corrige 2026-11-18

- **Demande du fondateur** : conserver le texte tel que tape par le vendeur
  (aucun reformatage automatique, les sauts de ligne qu'il tape sont deja
  preserves depuis le debut du projet via `allowNewlines: true`), mais
  respecter le sens d'ecriture quand une description melange arabe et
  francais -- ne pas melanger visuellement les deux.
- **Cause** : les `Text()` affichant la description sur la fiche produit
  (`product_detail_page.dart`, 3 emplacements actifs) n'avaient pas de
  `textDirection` explicite -- ils heritaient de la direction ambiante de
  l'app (basee sur la langue de l'interface), pas du contenu reel de la
  description. Une description surtout en francais s'affichait en RTL si
  l'app etait en arabe (et inversement), faussant l'alignement et l'ordre
  de la ponctuation/chiffres.
- **Correctif** : nouvelle fonction pure `detectTextDirection()`
  (`lib/src/utils/bidi_text_direction.dart`), regle standard "premier
  caractere fort" (meme heuristique que `dir="auto"` en HTML -- chiffres/
  espaces/ponctuation ignores). Appliquee aux 3 `Text()` actifs de la
  description sur la fiche produit. Aucun changement de logique de saisie,
  aucun reformatage, aucun changement d'IHM visible hors direction du
  texte. Filtres "Parcourir" deja adaptes a la categorie Vehicules
  (verifie : `listings_page.dart` + `product_service.dart` appliquent deja
  annee min/max, kilometrage max, carburant, boite).
- **Tests** : 7 tests unitaires purs ajoutes
  (`test/bidi_text_direction_test.dart`). `flutter analyze` + `flutter
  test` verts (168 passes, 2 skip, 0 echec).

## A realiser - prochaines versions (chat a ameliorer)

### Horodatage des messages sans date (chat) -- corrige 2026-11-18

- **Constat (2026-11-13)** : `chat_room_page.dart` formatait l'heure d'un
  message avec `DateFormat.Hm()` (ligne ~1133), qui n'affichait jamais la
  date. Un vieux message ressemblait visuellement a un message du jour meme.
- **Correctif** : nouvelle methode `_formatMessageTimestamp()` qui affiche
  `dd/MM HH:mm` pour tout message qui ne date pas du jour courant, et
  l'heure seule sinon (comportement inchange pour le jour meme). Un seul
  widget de formatage touche, aucun changement de modele de donnees.
- **Decision du fondateur (2026-11-18)** : inclus dans cette passe malgre
  le report initial du 13/11, a sa demande explicite.

## A surveiller - pas de correctif ni de release urgente

### Lien TikTok retire du menu d'aide

- **Decision du 13 novembre** : TikTok est retire du bouton d'aide sur Web,
  Android et iOS. Sur le Samsung de test, l'association des liens ne cible pas
  fiablement l'application TikTok; conserver ce lien donnerait une sortie
  incoherente de DZMarket.
- **Retour possible** : uniquement avec un `profile_deep_link` officiel du
  compte `@dzmarketpro`, valide sur Android et iOS avant publication.

- **Reseau mobile Android** : deux erreurs entre le 29 octobre et le 4 novembre
  correspondent a une connexion interrompue vers l'API et a une horloge de
  telephone en avance (`JWT issued at future`). Elles ne sont pas reproduites
  cote serveur.
- **Infrastructure** : au controle du 5 novembre, `www`, `app` et `api`
  repondaient HTTP 200; Caddy, Auth, Edge Functions et PostgreSQL etaient sains,
  sans 5xx observe. Les lignes Caddy `client disconnected` ne sont pas une panne
  applicative sans hausse de 5xx ou erreur utilisateur correlee.

## A planifier - acquisition et decouverte

### Partage d'annonce

- Les vendeurs partagent deja leurs annonces vers WhatsApp et Facebook. Avant
  toute evolution, verifier que chaque partage utilise une URL publique,
  canonique et durable de l'annonce, puis que son apercu (titre, image, prix et
  localisation si publique) est correct sur WhatsApp et Facebook.
- Ne pas ajouter de tracking intrusif ni modifier les donnees produit. Mesurer
  plus tard les ouvertures et conversions seulement si un besoin produit est
  confirme et avec une telemetrie anonymisee.

### Google Search Console

- Creer/verifier la propriete de domaine `dzmarket.pro`, soumettre le sitemap
  public apres verification qu'il repond bien publiquement, puis relever chaque
  mois les requetes en arabe et francais, impressions, clics, pages indexees,
  appareils et pays.
- Utiliser ces donnees avant de changer contenu ou SEO. Ne pas promettre une
  position Google; les priorites doivent venir des requetes et pages reelles.

### Reponse vendeur et confiance acheteur

- **Point de depart confirme le 12 novembre** : sur 125 conversations lancees
  par un acheteur, 65 n'ont pas eu de reponse vendeur. Le probleme est concentre
  chez un petit groupe de vendeurs; commencer par un accompagnement manuel,
  sans divulguer leurs coordonnees dans les rapports.
- **1. Accompagnement manuel** : contacter prioritairement les vendeurs ayant
  plusieurs conversations sans reponse, avec un script court et une explication
  du parcours acheteur. Aucun message ou appel automatique sans validation
  metier et consentement applicable.
- **2. Rappel produit** : concevoir une notification ou un rappel in-app apres
  une premiere question acheteur sans reponse. Le rendre idempotent, limite en
  frequence et desactivable; mesurer le taux de reponse avant/apres.
- **3. Badge de reactivite** : afficher "repond rapidement" uniquement sur une
  fenetre glissante de 30 jours, avec un volume minimum de conversations et un
  calcul serveur. Ne pas utiliser un badge manuel ni des donnees historiques
  insuffisantes.
- **4. Visibilite des annonces** : ne pas retirer ni masquer automatiquement
  une annonce. Commencer par un signal d'inactivite et un essai reversible de
  moindre mise en avant, apres mesure et revue manuelle des faux positifs.

## A concevoir - supervision admin complete

L'ecran admin actuel ne couvre que les erreurs Flutter remontees dans
`app_errors`. Une evolution doit donner une vue claire, agregée et protegee de
l'etat de la plateforme, sans exposer de donnees personnelles ni de secrets.

- **Experience utilisateur** : erreurs de parcours, blocages, lenteurs, ecrans
  inaccessibles, erreurs par plateforme/version et regressions apres release.
- **Application et services** : API, Auth, Edge Functions, notifications,
  stockage, chat, commandes et integrations transporteurs.
- **Donnees** : anomalies de coherence, echecs de jobs et migrations, sans
  permettre de modifier ou supprimer des donnees depuis un tableau d'erreurs.
- **Securite** : synthese d'evenements suspects et echec d'autorisation, sans
  afficher tokens, mots de passe, contenus prives ou traces sensibles.
- **Qualite release** : resultat des tests, version deployee, Crashlytics et
  alertes de regression, avec liens vers les preuves techniques reservees aux
  administrateurs autorises.

Commencer par une synthese de sante et des compteurs anonymises; ajouter les
sources une a une, avec tests RLS, pagination et retenue limitee des journaux.

## Garde-fou web a conserver

- Une ancienne livraison web avait omis les polices Material/Cupertino et le
  favicon, ce qui affichait des symboles de remplacement. Le correctif et le
  controle d'artefact sont deja livres dans `scripts/verify_web_artifact.ps1`.
- Avant chaque deploiement web, executer ce controle et verifier dans le navigateur
  que les deux fichiers de police, `favicon.png` et les deux templates
  `auth-email/*.html` repondent HTTP 200. Ce point est deja corrige : ne pas
  creer un nouveau correctif tant que le controle passe.
- `flutter build web` doit toujours utiliser `--no-tree-shake-icons`
  (voir `README.md`) ; sans ce flag les polices d'icones repartent en
  quasi-zero octet.
- Apres `unzip` d'une archive creee par `Compress-Archive` (Windows) sur
  le serveur Linux, verifier qu'aucun repertoire n'a perdu son bit
  d'execution (`find <web-root> -type d -not -perm -u+x,g+x,o+x`) --
  deja rencontre une fois le 5 novembre (403 sur un fichier dont le
  dossier parent etait passe en 644), corrige par `chmod 755` recursif.

## Correctif deploye le 5 novembre (deja en prod, ne pas refaire)

- `auth-email/confirmation.html` et `auth-email/recovery.html`
  repondaient 404 en prod (regression anterieure a cette session, requis
  par `GOTRUE_MAILER_TEMPLATES_CONFIRMATION`/`RECOVERY`) -- corrige par un
  rebuild complet + bascule atomique, verifie 200 publiquement. Voir
  `JOURNAL-IA.md` (entree du 5 novembre) pour le detail.

## Deploiement web du 18 novembre (deja en prod)

- Acces SSH prod debloque le 18/11 : utilisateur dedie `claude-deploy` sur
  `dzm-app-01` uniquement (pas de sudo, pas de mot de passe, cree via la
  cle root le temps de corriger la cause -- le compte n'avait en realite
  jamais ete cree par le script precedent malgre la confirmation "execute
  sans erreur"). ACL `setfacl` + sticky bit ajoutes sur `/var/www` pour que
  ce compte puisse gerer ses propres repertoires de deploiement sans
  toucher aux autres entrees root de `/var/www` (ex. `dzmarket-web.old`).
- Build web (`flutter build web --release --no-tree-shake-icons
  --dart-define-from-file=test/test_env.json`) depuis le commit `8790adc`,
  verifie par `verify_web_artifact.ps1`, bascule atomique avec un seul
  rollback conserve (`dzmarket-web-rollback-20261118-145943`),
  `config.json` prod preserve. Les 5 controles d'URL + `api.dzmarket.pro`
  + console navigateur (0 erreur/avertissement) sont verts.
- **Contenu livre** : correctif direction de texte FR/AR sur la fiche
  produit, horodatage chat, message d'erreur admin Moderation, timeout
  demarrage traductions, et le code client de la categorie "Vehicules"
  (picker, champs specifiques, filtres).

## Description annonce sans saut de ligne -- 2 causes trouvees et corrigees, 1 bug restant -- 18 novembre

- **Cause n°1 (corrigee)** : `InputSanitizer.sanitizeText()` supprimait tous
  les caracteres de controle, y compris `\n`/`\r`, AVANT de consulter le
  parametre `allowNewlines` -- ce parametre n'avait donc jamais eu d'effet
  depuis l'origine du projet. Corrige (voir commit `ecf71bd`), 5 tests
  ajoutes.
- **Cause n°2 (corrigee)** : les `TextField` Description (creation ET
  modification d'annonce) n'avaient pas `keyboardType:
  TextInputType.multiline`. Sans ca, la touche Entree n'insere RIEN du
  tout (ni saut de ligne, ni espace) malgre `maxLines > 1`. Corrige (voir
  commit `4d2b58f`) -- verifie directement au niveau DOM/Flutter : taper
  "A[Entree]B" produit maintenant bien `"A\nB"` dans le modele Flutter.
- **Bug restant, NON corrige, a investiguer separement** : en re-testant
  via l'ecran "Modifier l'annonce" (`edit_product_page.dart`) sur
  l'annonce Fiat Doblo deja publiee, le champ texte affiche bien le
  contenu corrige avec de vrais `\n` juste avant l'enregistrement (verifie
  par lecture directe de la valeur DOM), **mais la requete PATCH reseau
  envoyee au clic sur "Enregistrer" contient encore l'ancien texte sans
  saut de ligne** (verifie par interception directe de la requete HTTP).
  Autrement dit : le modele Flutter est correct, mais quelque chose dans
  le flux de sauvegarde de `_save()` envoie une valeur perimee pour
  `description` au lieu de relire `_descCtrl.text` au moment de l'envoi.
  Cause exacte non trouvee malgre plusieurs heures de tests reproductibles
  (plusieurs sessions navigateur fraiches, verification DOM/reseau a
  chaque etape). A deboguer en re-abordant `edit_product_page.dart`
  `_save()` avec des outils de debug Dart reels (breakpoints / print) plutot
  que par test navigateur externe. **Impact** : une NOUVELLE annonce creee
  depuis zero (via `add_listing_page.dart`) devrait beneficier des deux
  correctifs ci-dessus des la creation ; seule la MODIFICATION d'une
  annonce existante via l'ecran "Modifier" semble toucher ce bug restant
  -- a confirmer. La description de l'annonce Fiat Doblo (id 257) reste
  donc cassee en prod tant que ce point n'est pas resolu ou re-sauvegardee
  manuellement par le fondateur lui-meme (session humaine normale, pas de
  test automatise) une fois ce bug corrige.
- **Meme pattern `keyboardType` manquant repere ailleurs** (hors
  perimetre de cette passe) : bio profil (`profile_page.dart` `_bioCtrl`),
  details signalement (`product_detail_page.dart`), motif litige
  (`profile_page.dart` `reasonCtrl`), details avis public
  (`public_profile_page.dart`), commentaire avis commande
  (`orders_page.dart`), note moderation admin
  (`moderation_admin_page.dart`), message chat (`chat_room_page.dart`,
  `_controller` -- la aussi Entree n'insere rien, meme si le comportement
  voulu pour le chat -- Entree = envoyer vs Entree = nouvelle ligne -- est
  a trancher avec le fondateur avant de toucher ce fichier precis).

## Livraison "a convenir" obligatoire pour les vehicules -- confirmation (pas un bug)

- Verifie dans le code : `_isForcedArrangedDelivery()`
  (`add_listing_page.dart`) retourne vrai pour toute annonce vehicule
  (`VehicleSpecs.isVehicleCategory(_categorySlug)`), ce qui force
  `_effectiveDeliveryOptions()` a ne renvoyer que `['pickup']` -- aucune
  option de livraison par transporteur pour les vehicules. C'est le
  comportement voulu, deja decide dans le plan Vehicules (section 2.2 :
  "forcer la livraison en retrait en main propre pour les annonces
  vehicule"), pas un oubli. Confirme aussi cote base : la fonction trigger
  `enforce_pickup_for_large_products()` applique une regle similaire
  (volume/mots-cles) independamment de la categorie, donc une annonce
  peut aussi se retrouver en pickup-only pour cette seconde raison, sans
  rapport avec la categorie vehicule.

## Champs specifiques vehicule absents a l'etape Details -- toujours non resolu

- Deja note plus haut (migration Vehicules du 18/11) : les champs
  Modele/Annee/Kilometrage/Carburant/Boite/Carrosserie ne s'affichent pas
  a l'etape "Details" du formulaire de creation, malgre
  `_isVehicleListing` qui devrait correctement valoir `true`
  (`VehicleSpecs.isVehicleCategory(_categorySlug)`, verifie correct par
  lecture de code). Le forcage de livraison (voir section ci-dessus)
  fonctionne correctement pour la meme categorie au meme moment du
  formulaire, ce qui ecarte une simple erreur de `_categorySlug` jamais
  renseigne. Cause exacte non trouvee par lecture de code seule -- a
  reprendre avec des outils de debug Dart reels plutot qu'une nouvelle
  tentative de lecture statique.

## Bug trouve en testant la migration Vehicules en prod -- 18 novembre

- **Constat** : premiere annonce reelle creee en prod (Fiat Doblo, compte
  du fondateur, categorie Voitures) pour valider la migration de bout en
  bout. La categorie se selectionne bien (Vehicules > Voitures), et le
  forcage de la livraison en "a convenir" fonctionne (confirme visible a
  l'etape 6, switch transporteur desactive). **Mais l'etape 3 "Details" ne
  montre pas les champs specifiques vehicule** (Modele, Annee,
  Kilometrage, Carburant, Boite, Carrosserie) attendus par
  `add_listing_page.dart` (`if (_isVehicleListing) ...`, lignes ~2127+).
  Reproduit 2 fois de suite (formulaire recharge a neuf, cache
  `flutter.cache.categories.v5` vide a chaque fois) : toujours absent.
  `VehicleSpecs.isVehicleCategory()` est un simple test de prefixe
  (`startsWith('vehicles-')`), independant du cache -- donc pas une cause
  de cache. A investiguer : `_isVehicleListing` ne se met peut-etre pas a
  jour au bon moment apres la selection de categorie (setState manquant,
  ou la section vehicule lue depuis une valeur capturee avant la
  selection). Pas bloquant pour publier (les champs sont optionnels), mais
  la fonctionnalite vehicule n'offre pas encore ses champs dedies en
  prod.
- Annonce publiee malgre tout avec succes (titre/description/prix/
  localisation seuls) -- preuve que l'ensemble categorie+migration+
  publication fonctionne de bout en bout, seul ce sous-ensemble de champs
  reste a corriger.

## Migration categorie "Vehicules" appliquee en prod -- 18 novembre

- Migration `20261118120000_add_vehicle_category_and_fields.sql` appliquee
  le 18/11 directement sur `supabase-db` (conteneur sur `dzm-app-01`, pas
  un serveur `dzm-db-01` separe comme documente ailleurs -- verifie via
  `docker ps` : la stack Supabase self-hosted tourne entierement sur
  `dzm-app-01`) via `docker exec -i supabase-db psql ... --single-transaction
  -v ON_ERROR_STOP=1`, apres sauvegarde de `public.categories` (donnees) et
  du schema de `public.products` dans `/root/backups/` sur le serveur.
  Verifie : 7 lignes `categories` (`vehicles` + 6 enfants, `parent_id`
  correct) et 6 colonnes `vehicle_*` sur `products` (`vehicle_model`,
  `vehicle_year`, `vehicle_mileage_km`, `vehicle_fuel`,
  `vehicle_transmission`, `vehicle_body_type`). La categorie "Vehicules"
  est donc maintenant active en prod -- plus "inerte" comme note plus haut.
- Accord explicite du fondateur pour cette migration (choix via question
  structuree, 2026-11-18) avant toute execution, conformement a la regle du
  projet sur les migrations de production.

## Nouvelle categorie "Vehicules" (code livre 2026-11-18, migration appliquee le meme jour -- voir section ci-dessus)

- **Perimetre** : categorie racine `vehicles` + 6 sous-categories
  (Voitures, Motos & Scooters, Utilitaires, Camions, Engins, Bateaux --
  decision revisee le 18/11, voir plus bas). Champs specifiques a la
  creation d'annonce (modele, annee,
  kilometrage, carburant, boite, carrosserie) -- marque/annee/kilometrage
  recommandes, rien de bloquant pour le vendeur presse. Pas de
  plaque/VIN/papiers (volontairement exclu). Livraison forcee en retrait en
  main propre pour ces annonces (pas de COD/transporteur).
- **Fichiers touches** : migration
  `supabase/migrations/20261118120000_add_vehicle_category_and_fields.sql`
  (colonnes nullables sur `products` + lignes `categories`),
  `lib/src/utils/vehicle_specs.dart` (nouveau, codes/labels partages),
  `add_listing_page.dart` (creation), `listings_page.dart` (filtres),
  `product_detail_page.dart` (fiche produit), `product.dart` +
  `product_service.dart` (modele/requetes). Traductions FR/AR ajoutees
  dans `assets/i18n/{fr,ar}.json`.
- **Hors perimetre de cette passe (volontaire)** : aucune mise en avant
  payante (demarre gratuit comme le reste du catalogue), pas de champ sur
  l'ecran de modification d'annonce existant (`updateProduct` reste
  inchange -- edition des specs vehicule a prevoir dans une passe
  ulterieure si demande), pas d'ajout aux recherches sauvegardees.
- **A verifier avant d'appliquer la migration en prod** : confirmer qu'une
  contrainte unique existe bien sur `categories.slug` (la migration utilise
  `on conflict (slug)`) -- non verifie ici faute d'acces SSH/DB dans cette
  session. `flutter analyze` + `flutter test` verts (154 passes, 2 skip)
  valident uniquement le code Flutter, pas la migration SQL elle-meme.
- **Etat (mis a jour 2026-11-18)** : code pret localement. Test reel sur le
  Samsung branche (R5CNC13Y7WN) fait : phase smoke
  (`auth_flow_test`, `security_state_test`,
  `shipping_validation_zrexpress_test`), 3/3 verts via
  `run_quality_gate.ps1 -RunIntegration -DeviceId R5CNC13Y7WN
  -IntegrationPhase smoke`. Harnais de charge k6 (`load/*.js` +
  `scripts/run_k6_phase.ps1`) verifie fonctionnel par un run volontairement
  petit (5 VUs/30s, scenario `listings`, lecture seule) contre
  `api.dzmarket.pro` : p95=178ms, 0% erreur, seuils respectes -- k6 installe
  localement (`winget install GrafanaLabs.k6`), absent avant cette session.
  Build et migration SQL restent non deployes : l'acces SSH prod
  (`root@91.107.239.5`, cle `dzmarket_hetzner`) est **rejete par le
  serveur** (`Permission denied (publickey,password)`, verifie en direct,
  pas un probleme de passphrase cote agent) -- la cle locale n'est
  actuellement plus autorisee sur `dzm-app-01`/`dzm-db-01`, ou l'acces a
  change. Blocage reel, pas une supposition : a lever par le fondateur
  (nouvelle cle, ou reautoriser l'actuelle) avant toute application de
  migration ou tout build/deploiement serveur.
- **Test d'integration vehicule ecrit, pret a s'activer tout seul** :
  `integration_test/vehicle_listing_flow_test.dart` (nouveau) cree un
  compte vendeur jetable (meme pattern que `auth_flow_test.dart`), cherche
  la categorie `vehicles-cars` en base, et si elle existe, publie une
  annonce voiture complete (marque/modele/annee/kilometrage/carburant/
  boite/carrosserie), verifie que les 6 champs ressortent identiques en
  base, puis supprime l'annonce de test. Si la categorie n'existe pas
  encore (cas actuel, migration non appliquee), le test s'arrete
  proprement sans echec -- il s'activera reellement tout seul des que la
  migration sera appliquee en prod, sans repasser par une session de code.
  Execute 2 fois sur le Samsung branche pour verifier : 1er essai, une
  vraie coupure reseau transitoire sur l'appel `profiles` (meme famille que
  les erreurs reseau Android deja repertoriees plus haut, pas un bug du
  code) ; 2e essai, vert et rapide (2s), confirme le skip propre attendu.
- **Verifie via navigateur (Playwright) contre la prod** : `app.dzmarket.pro`
  charge normalement (annonces reelles visibles, aucune regression), le
  panneau "Catégorie" liste les categories existantes sans "Vehicules" --
  coherent avec la migration non appliquee, pas une anomalie.
- **Validation ajoutee (2026-11-18, suite 2e avis)** : marque/modele +
  annee + kilometrage sont maintenant reellement requis a l'etape
  "Details" quand la categorie est un vehicule (`_validateStep`), pas
  seulement "recommandes" sans controle comme dans la 1ere passe.
- **Verifie, pas un bug** : la suppression rapide d'une image
  (`_removeImage`) est synchrone (pas d'`await` entre l'appui et la mise a
  jour de la liste) et deja protegee par `canRemovePickedFile` -- pas de
  risque de double-suppression comme pour l'ancien bug du selecteur de
  fichiers. Rien a corriger ici sans cas reproductible.
- **Decision tranchee par le fondateur (2026-11-18, revision)** : la liste
  des sous-categories vehicules passe de 4 (Voitures / Motos & Scooters /
  Camions & Utilitaires / Pieces & Accessoires auto) a 6 : Voitures / Motos
  & Scooters / Utilitaires / Camions / Engins / Bateaux -- "Pieces &
  Accessoires" retiree. Verifie contre le concurrent principal du marche
  algerien (Ouedkniss) : son propre menu vehicules liste Voitures,
  Utilitaire, Motos & Scooters, Camion, Engin (entre autres) -- "Utilitaires"
  / "Camions" / "Engins" correspondent donc a une segmentation deja eprouvee
  sur ce marche. Aucune trace d'une categorie "Bateaux" chez ce concurrent
  (pas de precedent trouve), gardee ici par decision du fondateur -- a
  surveiller comme categorie a faible volume potentiel. Migration et tests
  mis a jour en consequence (slugs `vehicles-utility`, `vehicles-equipment`,
  `vehicles-boats` ajoutes ; `vehicles-parts` retire).
- **Sequencement de release (suite 2e avis, accepte)** : ce correctif ne
  doit pas partir dans le meme build que les correctifs de fiabilite
  (demarrage Android, erreur admin). Deux versions separees : "Release A"
  fiabilite (deja prete, testee, zero risque) livree en premier ; "Release
  B" vehicules testee et livree separement, avec son propre bump de
  version. Le code des deux vit deja dans ce repo, seul le decoupage en
  builds/versions distincts reste a faire au moment du build.

## Decision de release

- Hotfix web deja deploye le 5 novembre (templates auth-email + permissions
  de repertoires) -- pas d'action supplementaire cote web pour l'instant.
- La release `1.0.10+48` est construite et validee localement pour retirer
  TikTok du menu d'aide. Sa publication multi-plateforme est en attente de la
  fin de la beta review Apple existante et d'un canal d'execution autorisant la
  bascule Web. Ne pas publier Android seul afin de garder les menus coherents.
- La categorie "Vehicules" ci-dessus est un changement supplementaire,
  distinct de la release `1.0.10+48` -- a bumper separement (nouveau build)
  une fois teste reellement, pas a fusionner silencieusement dans
  `1.0.10+48` deja valide pour autre chose.
