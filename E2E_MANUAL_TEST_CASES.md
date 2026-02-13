# DZMarket - Cas de test E2E manuel (version complete)

## 1) Objectif
Ce fichier sert de reference unique pour le test manuel end-to-end de DZMarket.
Il couvre:
- specs fonctionnelles
- UX
- securite fonctionnelle (RLS visible via UI)
- role buyer/seller/superadmin
- workflows critiques commande/livraison/chat/moderation
- Total IDs uniques: 291

## 2) Regles d execution
- Executer sur `dev` en priorite, puis spot-check sur `staging/prod`.
- Pour chaque cas: noter `PASS/FAIL`, capture ecran, logs, et build SHA.
- Si `FAIL`: joindre etape exacte + message erreur + compte teste + horodatage.
- Toujours tester FR puis AR pour les ecrans critiques.

## 3) Comptes de test recommandes
- `buyer_1` (actif)
- `seller_1` (actif + transporteurs configures)
- `superadmin_1` (superadmin)
- `buyer_suspended`
- `buyer_banned`

Ne pas stocker les mots de passe dans ce fichier. Les garder dans un coffre securise.

## 4) Matrice E2E exhaustive
Format:
- `ID | Etapes | Resultat attendu | Priorite`

---

## A. Auth, session, legal, i18n (30 cas)

- [ ] `TC-AUTH-001 | Ouvrir app sans session | Redirection automatique vers Sign-in | P0`
- [ ] `TC-AUTH-002 | Sign-in email+mdp valides | Redirection Home, session active | P0`
- [ ] `TC-AUTH-003 | Sign-in email vide + submit | Message "email requis" localise | P0`
- [ ] `TC-AUTH-004 | Sign-in mdp vide + submit | Message "mot de passe requis" localise | P0`
- [ ] `TC-AUTH-005 | Sign-in email invalide (format) | Message "email invalide" localise | P0`
- [ ] `TC-AUTH-006 | Sign-in mauvais mdp | Message "email ou mot de passe incorrect" | P0`
- [ ] `TC-AUTH-007 | Sign-in compte suspendu | Login refuse + message suspendu | P0`
- [ ] `TC-AUTH-008 | Sign-in compte banni | Login refuse + message banni | P0`
- [ ] `TC-AUTH-009 | Cliquer "Mot de passe oublie?" (centre) | Ouvre ecran reset password | P0`
- [ ] `TC-AUTH-010 | Reset email valide | Message email envoye | P1`
- [ ] `TC-AUTH-011 | Reset email invalide | Message erreur propre et localise | P1`
- [ ] `TC-AUTH-012 | Sign-up valide | Compte cree + profil auto cree | P0`
- [ ] `TC-AUTH-013 | Sign-up avec email deja utilise | Message duplication clair | P1`
- [ ] `TC-AUTH-014 | Switch langue FR->AR sur Sign-in | Tous labels changent sans glitch UI | P0`
- [ ] `TC-AUTH-015 | Switch langue AR->FR sur Sign-up | Tous labels changent sans glitch UI | P0`
- [ ] `TC-AUTH-016 | Quitter/reouvrir app avec session active | Session restauree | P0`
- [ ] `TC-AUTH-017 | Logout depuis profil | Retour Sign-in + session invalidee | P0`
- [ ] `TC-AUTH-018 | Acceder a route /legal/privacy sans session | Accessible | P1`
- [ ] `TC-AUTH-019 | Acceder a route /legal/terms sans session | Accessible | P1`
- [ ] `TC-AUTH-020 | Acceder a route /legal/imprint sans session | Accessible | P1`
- [ ] `TC-AUTH-021 | Depuis Sign-in cliquer Politique | Route ouvre sans GoException | P0`
- [ ] `TC-AUTH-022 | Depuis Sign-in cliquer Conditions | Route ouvre sans GoException | P0`
- [ ] `TC-AUTH-023 | Depuis Sign-in cliquer Mentions | Route ouvre sans GoException | P0`
- [ ] `TC-AUTH-024 | Saisie email avec espaces debut/fin | Trim applique, login OK si credentials valides | P1`
- [ ] `TC-AUTH-025 | Mdp trop court au sign-up | Message validation propre | P1`
- [ ] `TC-AUTH-026 | Sign-in avec trop de tentatives rapides | Message rate-limit propre | P1`
- [ ] `TC-AUTH-027 | Compte non confirme (si active) | Message email non confirme | P2`
- [ ] `TC-AUTH-028 | Retour Android depuis reset password | Retour Sign-in sans crash | P2`
- [ ] `TC-AUTH-029 | Theme clair: lisibilite labels Sign-in | Contraste suffisant | P1`
- [ ] `TC-AUTH-030 | Responsive web Sign-in mobile width | Aucun overlap/cut text | P1`

---

## B. Profil utilisateur et profil public (22 cas)

- [ ] `TC-PROF-001 | Ouvrir Profil (connecte) | Donnees profil chargees | P0`
- [ ] `TC-PROF-002 | Modifier nom+bio+tel puis Enregistrer | Donnees persistantes apres refresh | P0`
- [ ] `TC-PROF-003 | Changer langue FR/AR dans Profil | Langue appliquee globalement | P0`
- [ ] `TC-PROF-004 | Wilaya picker: choisir wilaya | Code+nom affiches correctement | P0`
- [ ] `TC-PROF-005 | Daira picker avant wilaya | Champ desactive tant que wilaya non choisie | P0`
- [ ] `TC-PROF-006 | Changer wilaya | Liste daira rechargee selon wilaya | P0`
- [ ] `TC-PROF-007 | Wilaya tri de 01 a 58 | Ordre numerique correct | P0`
- [ ] `TC-PROF-008 | Recherche wilaya dans picker | Filtrage instantane | P1`
- [ ] `TC-PROF-009 | Recherche daira dans picker | Filtrage instantane | P1`
- [ ] `TC-PROF-010 | Upload avatar image valide | Avatar mis a jour | P1`
- [ ] `TC-PROF-011 | Upload avatar fichier invalide | Message erreur propre | P1`
- [ ] `TC-PROF-012 | Toggle mode vendeur ON | Outils vendeur visibles | P0`
- [ ] `TC-PROF-013 | Toggle mode vendeur OFF | Outils vendeur caches | P0`
- [ ] `TC-PROF-014 | Toggle profil public ON | Profil vendeur consultable | P0`
- [ ] `TC-PROF-015 | Toggle profil public OFF | Profil vendeur masque | P0`
- [ ] `TC-PROF-016 | Depuis fiche produit, tap avatar vendeur public | Ouvre PublicProfilePage | P0`
- [ ] `TC-PROF-017 | Depuis fiche produit, vendeur prive | Action bloquee proprement | P1`
- [ ] `TC-PROF-018 | Public profile: voir annonces actives vendeur | Liste chargee et cliquable | P1`
- [ ] `TC-PROF-019 | Sauvegarde profil avec champs vides optionnels | Sauvegarde sans crash | P1`
- [ ] `TC-PROF-020 | Profil en AR (RTL) | Alignements RTL corrects | P1`
- [ ] `TC-PROF-021 | Deconnexion/reconnexion | Etat profil persiste | P0`
- [ ] `TC-PROF-022 | Refresh profil avec reseau lent | Loader + pas de freeze | P1`

---

## C. Parcourir, recherche, filtres, favoris, saved searches (24 cas)

- [ ] `TC-BROWSE-001 | Ouvrir Parcourir | Grille produits chargee | P0`
- [ ] `TC-BROWSE-002 | Scroll bas de liste | Pagination charge page suivante | P0`
- [ ] `TC-BROWSE-003 | Search text simple | Resultats filtres correctement | P0`
- [ ] `TC-BROWSE-004 | Debounce recherche (frappe rapide) | Pas de flood, resultats stables | P1`
- [ ] `TC-BROWSE-005 | Chip "Tous les filtres" | Ouvre panneau filtres complet | P0`
- [ ] `TC-BROWSE-006 | Quick chip categorie | Filtre applique et badge coherent | P0`
- [ ] `TC-BROWSE-007 | Quick chip prix | Filtre min/max applique | P0`
- [ ] `TC-BROWSE-008 | Quick chip proximite ON avec wilaya profil | Filtre wilaya actif | P0`
- [ ] `TC-BROWSE-009 | Proximite ON sans wilaya profil | Snackbar indisponible affichee | P0`
- [ ] `TC-BROWSE-010 | Bouton reset filtres | Tous filtres remis a zero | P0`
- [ ] `TC-BROWSE-011 | Favoris ON/OFF dans barre haute | Affiche uniquement favoris quand ON | P1`
- [ ] `TC-BROWSE-012 | Ajouter produit en favori | Coeur actif + persistance | P1`
- [ ] `TC-BROWSE-013 | Retirer favori | Coeur inactif + persistance | P1`
- [ ] `TC-BROWSE-014 | Enregistrer recherche | Chip saved search cree | P1`
- [ ] `TC-BROWSE-015 | Appliquer saved search | Champs/filters remplis automatiquement | P1`
- [ ] `TC-BROWSE-016 | Supprimer saved search via X | Confirmation + suppression effective | P1`
- [ ] `TC-BROWSE-017 | Tri newest -> oldest | Ordre change conforme | P1`
- [ ] `TC-BROWSE-018 | Filtre condition | Resultats respectent condition | P1`
- [ ] `TC-BROWSE-019 | Filtre marque/taille/couleur | Resultats conformes | P1`
- [ ] `TC-BROWSE-020 | Etat vide (aucun resultat) | Message empty propre + pas de crash | P1`
- [ ] `TC-BROWSE-021 | Erreur reseau fetch list | Message erreur et retry possible | P1`
- [ ] `TC-BROWSE-022 | Footer legal visible en bas | Texte lisible et non tronque | P2`
- [ ] `TC-BROWSE-023 | FAB "Vendre" ouvre AddListing | Navigation correcte | P0`
- [ ] `TC-BROWSE-024 | Badge non lu chat dans bottom nav | Badge update en temps reel | P1`

---

## D. Creation annonce vendeur (34 cas)

- [ ] `TC-LIST-001 | Ouvrir AddListing via FAB | Wizard etape 1 affiche | P0`
- [ ] `TC-LIST-002 | Etape photos sans image -> continuer | Erreur min photo | P0`
- [ ] `TC-LIST-003 | Ajouter 1+ image valide | Preview visible | P0`
- [ ] `TC-LIST-004 | Supprimer image de la liste | Image retiree immediatement | P1`
- [ ] `TC-LIST-005 | Etape categorie sans choix | Erreur choisir categorie | P0`
- [ ] `TC-LIST-006 | Choisir categorie | Valeur visible dans recap | P0`
- [ ] `TC-LIST-007 | Etape details sans titre | Erreur titre requis | P0`
- [ ] `TC-LIST-008 | Etape details sans description | Erreur description requise | P0`
- [ ] `TC-LIST-009 | Etape prix stock invalide (0) | Erreur stock invalide | P0`
- [ ] `TC-LIST-010 | Etape prix invalide | Erreur prix requise/invalide | P0`
- [ ] `TC-LIST-011 | Etape localisation sans wilaya/daira | Erreur localisation | P0`
- [ ] `TC-LIST-012 | Wilaya change -> daira reset | Daira vide apres changement | P0`
- [ ] `TC-LIST-013 | Etape livraison sans mode coche | Erreur choix livraison | P0`
- [ ] `TC-LIST-014 | Cocher COD uniquement | Valeur recap correcte | P1`
- [ ] `TC-LIST-015 | Cocher Pickup uniquement | Valeur recap correcte | P1`
- [ ] `TC-LIST-016 | Dimensions invalides (negatives/too high) | Erreurs hauteur/largeur/longueur | P0`
- [ ] `TC-LIST-017 | Poids hors plage (<1 ou >60) | Erreur weight range | P0`
- [ ] `TC-LIST-018 | Assurance ON sans valeur declaree | Erreur valeur requise | P0`
- [ ] `TC-LIST-019 | Assurance ON + valeur declaree | Validation OK | P1`
- [ ] `TC-LIST-020 | Stopdesk non supporte transporteur | Option auto desactivee | P1`
- [ ] `TC-LIST-021 | Exchange non supporte transporteur | Option auto desactivee | P1`
- [ ] `TC-LIST-022 | Produit grand volume (poids >15) | Pickup force automatiquement | P0`
- [ ] `TC-LIST-023 | Produit grand volume (dims > seuil) | Pickup force automatiquement | P0`
- [ ] `TC-LIST-024 | Produit type voiture/moto/meuble (texte) | Pickup force automatiquement | P0`
- [ ] `TC-LIST-025 | Validation anti-spam titre/desc | Donnees sanitizees | P1`
- [ ] `TC-LIST-026 | Moderation texte listing interdit | Annonce refusee/masquee selon policy | P0`
- [ ] `TC-LIST-027 | Moderation image non conforme | Annonce refusee/masquee selon policy | P0`
- [ ] `TC-LIST-028 | Publish annonce valide | Retour liste annonces + item visible | P0`
- [ ] `TC-LIST-029 | Publish avec reseau coupe pendant upload | Message erreur propre, pas de crash | P1`
- [ ] `TC-LIST-030 | Re-ouvrir brouillon apres erreur | Champs saisis conserves autant que possible | P2`
- [ ] `TC-LIST-031 | Preview recap annonce | Toutes sections coherentes | P1`
- [ ] `TC-LIST-032 | Edition annonce existante | Modifs persistees | P1`
- [ ] `TC-LIST-033 | Stock a 0 sur annonce | Passe en archive (UI) | P0`
- [ ] `TC-LIST-034 | Archive affiche max 30 | Limite appliquee | P1`

---

## E. Fiche produit, offre, signalement, checkout (34 cas)

- [ ] `TC-PROD-001 | Ouvrir fiche produit valide | Detail charge sans erreur | P0`
- [ ] `TC-PROD-002 | Produit inexistant | Etat d erreur propre | P1`
- [ ] `TC-PROD-003 | Produit owner = user courant | CTA acheter desactive | P0`
- [ ] `TC-PROD-004 | Produit stock 0/archived | CTA acheter bloque + message | P0`
- [ ] `TC-PROD-005 | Contact vendeur (connecte) | Conversation creee/ouverte | P0`
- [ ] `TC-PROD-006 | Contact vendeur (non connecte) | Message login required | P0`
- [ ] `TC-PROD-007 | Signaler annonce sans raison | Validation reason required | P0`
- [ ] `TC-PROD-008 | Signaler annonce raison valide | Confirmation envoi | P0`
- [ ] `TC-PROD-009 | Signaler meme annonce 2 fois meme user | Dedupe ou update, pas doublon abusif | P1`
- [ ] `TC-PROD-010 | Offre prix valide | Offre creee et visible | P1`
- [ ] `TC-PROD-011 | Offre acceptee vendeur | Prix agree applique checkout | P1`
- [ ] `TC-PROD-012 | Buy now choisir mode pickup | Resume pickup + commande creee | P0`
- [ ] `TC-PROD-013 | Buy now choisir mode COD home | Wizard livraison s ouvre | P0`
- [ ] `TC-PROD-014 | Checkout charge transporteurs seller | Liste transporteurs activee correctement | P0`
- [ ] `TC-PROD-015 | Courier Yalidine: charger wilayas | Donnees visibles, tri numerique | P0`
- [ ] `TC-PROD-016 | Courier Ecotrack: charger wilayas | Donnees visibles | P0`
- [ ] `TC-PROD-017 | Courier ZR Express: charger wilayas | Donnees visibles | P0`
- [ ] `TC-PROD-018 | Choisir wilaya -> daira dependante | Daira/communes mises a jour | P0`
- [ ] `TC-PROD-019 | M'Sila selection wilaya | Plusieurs dairas visibles (pas 1 seule) | P0`
- [ ] `TC-PROD-020 | Checkout tel non E.164 pour ZR | Validation refusee | P0`
- [ ] `TC-PROD-021 | Checkout tel E.164 +213 valide ZR | Validation OK | P0`
- [ ] `TC-PROD-022 | Stopdesk dispo transporteur -> visible | Option stopdesk utilisable | P1`
- [ ] `TC-PROD-023 | Stopdesk non supporte -> cache | Option absente | P1`
- [ ] `TC-PROD-024 | Envoi commande valide | Order creee status pending | P0`
- [ ] `TC-PROD-025 | Double clic meme commande (<20s, meme courier/mode/adresse) | Bloquee par anti-duplicate | P1`
- [ ] `TC-PROD-026 | Buy own product | Bloque avec message | P0`
- [ ] `TC-PROD-027 | Produit invalide en checkout | Erreur propre (invalid product) | P1`
- [ ] `TC-PROD-028 | Message systeme auto pour pickup | Message auto present dans chat order | P0`
- [ ] `TC-PROD-029 | Resume options livraison read-only buyer | Pas editable cote buyer | P1`
- [ ] `TC-PROD-030 | Persistence last checkout | Donnees adresse pre-remplies au prochain checkout | P1`
- [ ] `TC-PROD-031 | Seller public tap avatar/nom | Navigation profil public OK | P0`
- [ ] `TC-PROD-032 | Seller prive tap avatar/nom | Pas de fuite info privee | P1`
- [ ] `TC-PROD-033 | 2e commande meme produit avec courier/mode different et stock dispo | Commande autorisee | P0`
- [ ] `TC-PROD-034 | Repasser commandes jusqu a epuisement stock (ex: stock=3) | 3 commandes max puis out of stock | P0`

---

## F. Mes commandes (buyer) et ventes (seller) (26 cas)

- [ ] `TC-ORD-001 | Buyer Orders page sans session | Prompt sign-in | P0`
- [ ] `TC-ORD-002 | Buyer Orders liste | Affiche max 30 dernieres | P0`
- [ ] `TC-ORD-003 | Status chip localise FR | Label correct | P1`
- [ ] `TC-ORD-004 | Status chip localise AR | Label correct | P1`
- [ ] `TC-ORD-005 | Chip payment method | Label payment coherent | P1`
- [ ] `TC-ORD-006 | Ouvrir chat depuis order buyer | Ouvre /order/:id/chat | P0`
- [ ] `TC-ORD-007 | Ouvrir tracking depuis order buyer | Ouvre /order/:id/track | P0`
- [ ] `TC-ORD-008 | Paiement mock online order pending | Passage a paid | P1`
- [ ] `TC-ORD-009 | Review seller apres delivered | Form review visible, submit OK | P1`
- [ ] `TC-ORD-010 | Seller Orders liste | Affiche max 30 dernieres non cancelled | P0`
- [ ] `TC-ORD-011 | Generate label vendeur | Bordereau cree, URL label stockee | P0`
- [ ] `TC-ORD-012 | Open label vendeur | PDF/URL s ouvre | P1`
- [ ] `TC-ORD-013 | Cancel order seller (pending sans label) | Status cancelled | P0`
- [ ] `TC-ORD-014 | Cancel order non autorise | Action bloquee | P1`
- [ ] `TC-ORD-015 | Buyer return warning badge vendeur | Badge visible si returns_12m > 0 | P1`
- [ ] `TC-ORD-016 | Livraison dashboard | Charge donnees sans erreur | P1`
- [ ] `TC-ORD-017 | Shipment status update | Reflect dans order card | P1`
- [ ] `TC-ORD-018 | Timeline tracking events | Affiche events ordonnes | P1`
- [ ] `TC-ORD-019 | Refresh pull-to-refresh buyer orders | Reload correct + pas doublon | P1`
- [ ] `TC-ORD-020 | Refresh pull-to-refresh seller orders | Reload correct + pas doublon | P1`
- [ ] `TC-ORD-021 | Order stale sans label >3j (job) | Auto-cancel + message systeme | P2`
- [ ] `TC-ORD-022 | RLS: user A ne voit pas orders user B | Aucun leak de donnees | P0`
- [ ] `TC-ORD-023 | Stock decremente a creation order | Stock reserve immediatement | P0`
- [ ] `TC-ORD-024 | Stock a delivered + sold_count | Valeurs coherentes | P1`
- [ ] `TC-ORD-025 | Buyer return sync batch (100+ orders with tracking) | Job traite plusieurs lots sans stopper a 40 | P1`
- [ ] `TC-ORD-026 | Buyer return event data minimization | buyer_return_events ne contient que buyer_id/order_id/status/courier_id/returned_at | P0`

---

## G. Chat V2 (19 cas)

- [ ] `TC-CHAT-001 | Ouvrir hub chat | Conversations chargees | P0`
- [ ] `TC-CHAT-002 | Liste conversations limitee | 30 dernieres max | P0`
- [ ] `TC-CHAT-003 | Messages room limites | 30 derniers max affiches | P0`
- [ ] `TC-CHAT-004 | Room tri par last_message_at | Ordre stable | P1`
- [ ] `TC-CHAT-005 | Envoyer message texte normal | Message apparait instant | P0`
- [ ] `TC-CHAT-006 | Message > limite longueur | Refuse proprement | P1`
- [ ] `TC-CHAT-007 | Rate limit spam message | Refuse apres seuil | P1`
- [ ] `TC-CHAT-008 | Hide conversation utilisateur A | Disparait pour A uniquement | P0`
- [ ] `TC-CHAT-009 | Restore conversation | Reapparait | P0`
- [ ] `TC-CHAT-010 | New message apres hide (soft) | Conversation revient visible | P1`
- [ ] `TC-CHAT-011 | Marquer lu | Badge unread diminue | P1`
- [ ] `TC-CHAT-012 | Bloquer utilisateur | Send message bloque des 2 cotes selon policy | P1`
- [ ] `TC-CHAT-013 | Message systeme order_created | Present une seule fois (dedupe) | P0`
- [ ] `TC-CHAT-014 | Message systeme order_shipped/tracking | Present avec payload correct | P1`
- [ ] `TC-CHAT-015 | Label URL visible seller only | Buyer ne voit pas bouton label | P0`
- [ ] `TC-CHAT-016 | RLS room: user non participant | Acces refuse | P0`
- [ ] `TC-CHAT-017 | Meme buyer/seller/produit, commandes multiples (pickup+livraison+autre courier) | Une seule room conservee | P0`
- [ ] `TC-CHAT-018 | Hub chat apres commandes multiples meme thread | Pas de doublon de conversation | P0`
- [ ] `TC-CHAT-019 | Room archivee puis nouvelle commande meme thread | Room reactivatee, meme id conversation | P1`

---

## H. Superadmin moderation (28 cas)

- [ ] `TC-MOD-001 | Ouvrir Moderation (superadmin) | Ecran charge sans erreur SQL | P0`
- [ ] `TC-MOD-002 | Tab Users: recherche email/nom/id | Filtre fonctionne | P0`
- [ ] `TC-MOD-003 | Tab Users: filtre Tous/Actif/Suspendu/Banni | Compteurs+liste coherents | P0`
- [ ] `TC-MOD-004 | Action user -> Suspendre | Status profile passe a suspended | P0`
- [ ] `TC-MOD-005 | Action user -> Bannir | Status profile passe a banned | P0`
- [ ] `TC-MOD-006 | Action user -> Reactiver | Status profile passe a active | P0`
- [ ] `TC-MOD-007 | User suspendu tente login | Refuse avec message suspendu | P0`
- [ ] `TC-MOD-008 | User banni tente login | Refuse avec message banni | P0`
- [ ] `TC-MOD-009 | Superadmin ne peut pas se bannir lui-meme | Action refusee | P1`
- [ ] `TC-MOD-010 | Tab Annonces: recherche titre/id/vendeur | Filtre fonctionne | P0`
- [ ] `TC-MOD-011 | Tab Annonces: filtre approved | Liste conforme | P1`
- [ ] `TC-MOD-012 | Tab Annonces: filtre masked | Liste conforme | P1`
- [ ] `TC-MOD-013 | Tab Annonces: filtre blocked | Liste conforme | P1`
- [ ] `TC-MOD-014 | Action annonce -> Approver | moderation_status=approved | P0`
- [ ] `TC-MOD-015 | Action annonce -> Masquer | moderation_status=masked | P0`
- [ ] `TC-MOD-016 | Action annonce -> Bloquer | moderation_status=blocked + archive | P0`
- [ ] `TC-MOD-017 | Annonce blocked invisible en browse public | Non visible aux buyers | P0`
- [ ] `TC-MOD-018 | Tab Signalements: queue prioritaire >=10 uniques | Tri prioritaire correct | P0`
- [ ] `TC-MOD-019 | Toggle "prioritaire only" OFF | Tous signalements recents visibles | P1`
- [ ] `TC-MOD-020 | Signalement annonce 10 users distincts / 7j | Auto masked applique | P0`
- [ ] `TC-MOD-021 | Meme user signale repetitivement | Ne gonfle pas unique reporters | P1`
- [ ] `TC-MOD-022 | Message erreur function invoke admin-moderation | Snackbar explicite | P1`
- [ ] `TC-MOD-023 | Tab titles visibles (pas coupes) | UX propre sur petit ecran | P1`
- [ ] `TC-MOD-024 | Role non superadmin accede moderation | Acces bloque/caché | P0`
- [ ] `TC-MOD-025 | Update status user depuis menu card | Action persistante apres refresh | P0`
- [ ] `TC-MOD-026 | Update status annonce depuis menu card | Action persistante apres refresh | P0`
- [ ] `TC-MOD-027 | Pull-to-refresh moderation page | Donnees rechargees sans crash | P1`
- [ ] `TC-MOD-028 | Charge volumique (300+ items) | Scroll fluide, aucune freeze critique | P2`

---

## I. Erreurs de l app (superadmin) (14 cas)

- [ ] `TC-ERR-001 | Ouvrir "Erreurs de l'app" en superadmin | Page charge sans SQL error | P0`
- [ ] `TC-ERR-002 | Tab Actuelles | Affiche erreurs recentes dedupees | P0`
- [ ] `TC-ERR-003 | Tab Archive (30) | Affiche max 30 dernieres archivees | P0`
- [ ] `TC-ERR-004 | Compteur Actuelles dynamique | Nombre coherent avec liste | P1`
- [ ] `TC-ERR-005 | Compteur Archive dynamique | Nombre coherent avec liste | P1`
- [ ] `TC-ERR-006 | Ouvrir detail erreur | Message + contexte + stack visibles | P1`
- [ ] `TC-ERR-007 | Erreur fatal | Badge/indicateur fatal visible | P1`
- [ ] `TC-ERR-008 | Pull-to-refresh page erreurs | Recharge correcte | P1`
- [ ] `TC-ERR-009 | Role non superadmin accede page erreurs | Acces bloque/caché | P0`
- [ ] `TC-ERR-010 | Erreur avec context status=resolved | Classee en archive | P1`
- [ ] `TC-ERR-011 | Erreur ancienne >48h | Classee en archive | P1`
- [ ] `TC-ERR-012 | Erreurs identiques recentes | Une active + surplus archive | P1`
- [ ] `TC-ERR-013 | Verifier no crash UI si context vide | Affichage robuste | P2`
- [ ] `TC-ERR-014 | Long stack trace | Bottom sheet scrollable sans overflow | P2`

---

## J. UX transversale (16 cas)

- [ ] `TC-UX-001 | FR: textes non tronques (auth/home/profile) | Aucune coupure critique | P1`
- [ ] `TC-UX-002 | AR: textes non tronques (auth/home/profile) | Aucune coupure critique | P1`
- [ ] `TC-UX-003 | RTL AR sur formulaires | Alignement coherent | P1`
- [ ] `TC-UX-004 | Taille cible boutons >= touch friendly | Interactions confortables | P1`
- [ ] `TC-UX-005 | Loader visible pendant appels lents | Feedback utilisateur clair | P1`
- [ ] `TC-UX-006 | Messages erreur non techniques cote user | Texte compréhensible | P0`
- [ ] `TC-UX-007 | Snackbar erreurs action | Visible et non bloquant | P1`
- [ ] `TC-UX-008 | Navigation back Android | Pas de boucle ni ecran blanc | P1`
- [ ] `TC-UX-009 | Etat vide listes | Message + CTA utile | P1`
- [ ] `TC-UX-010 | Contraste couleurs theme clair | Lisibilite correcte | P1`
- [ ] `TC-UX-011 | Barres filtre Parcourir | Look pro, pas surcharge infos | P1`
- [ ] `TC-UX-012 | "Mot de passe oublie?" centre | Alignement centre stable | P0`
- [ ] `TC-UX-013 | "Pas de compte?" visible sous CTA | Lisibilite et spacing OK | P1`
- [ ] `TC-UX-014 | Public profile tap affordance (avatar/nom) | Interactif clair | P1`
- [ ] `TC-UX-015 | Modals/bottom sheets petite hauteur ecran | Scroll interne correct | P2`
- [ ] `TC-UX-016 | Rotation ecran (si active) | Pas de perte d etat critique | P2`

---

## K. Performance, reseau faible, resilence (14 cas)

- [ ] `TC-NFR-001 | 3G lente au login | Pas de freeze, timeout gere | P1`
- [ ] `TC-NFR-002 | 3G lente browse pagination | Loader visible + retry possible | P1`
- [ ] `TC-NFR-003 | Coupure reseau pendant creation annonce | Erreur propre, app stable | P0`
- [ ] `TC-NFR-004 | Coupure reseau pendant checkout | Erreur propre, pas commande fantome | P0`
- [ ] `TC-NFR-005 | Coupure reseau pendant chat send | Erreur propre, no duplicate | P1`
- [ ] `TC-NFR-006 | Reconnexion apres offline | Sync reprend correctement | P1`
- [ ] `TC-NFR-007 | RefreshController anti double run | Pas de double requetes concurrentes | P1`
- [ ] `TC-NFR-008 | Scroll long browse (200+ items cumules) | Pas de jank majeur | P2`
- [ ] `TC-NFR-009 | Images invalides decode error | UI ne crash pas, fallback affiche | P1`
- [ ] `TC-NFR-010 | Memoire: navigation intense 15 min | Pas de crash OOM | P2`
- [ ] `TC-NFR-011 | Chat stream long session | Pas de fuite visible | P2`
- [ ] `TC-NFR-012 | Update build sans clear data | Migration UI stable | P2`
- [ ] `TC-NFR-013 | Android backstack complet | Retour ecrans coherent | P1`
- [ ] `TC-NFR-014 | Device date/heure modifiee | Tri dates reste coherent | P2`

---

## L. Securite fonctionnelle et permissions (20 cas)

- [ ] `TC-SEC-001 | Buyer essaie voir orders autre user (UI) | Impossible via app | P0`
- [ ] `TC-SEC-002 | Buyer essaie update order seller (UI) | Action absente ou refusee | P0`
- [ ] `TC-SEC-003 | Buyer essaie generate label vendeur | Action inaccessible | P0`
- [ ] `TC-SEC-004 | Buyer essaie ouvrir label prive | Refusee | P0`
- [ ] `TC-SEC-005 | Non owner essaie edit annonce | Refusee | P0`
- [ ] `TC-SEC-006 | Non owner essaie delete annonce | Refusee | P0`
- [ ] `TC-SEC-007 | User non participant room chat | Ne voit pas la room | P0`
- [ ] `TC-SEC-008 | Block user puis send message | Refusee | P1`
- [ ] `TC-SEC-009 | Upload avatar path autre user | Refusee | P1`
- [ ] `TC-SEC-010 | Upload image produits non auth | Refusee | P1`
- [ ] `TC-SEC-011 | Rate limit orders (burst) | Neme commande refusee selon seuil | P1`
- [ ] `TC-SEC-012 | Duplicate order quasi identique <20s | Refusee | P1`
- [ ] `TC-SEC-013 | Input injection simple dans recherche | Sanitization, pas crash | P1`
- [ ] `TC-SEC-014 | Input injection simple dans chat | Sanitization, pas crash | P1`
- [ ] `TC-SEC-015 | Input injection simple dans profil | Sanitization, pas crash | P1`
- [ ] `TC-SEC-016 | Superadmin endpoint depuis non-superadmin | Refusee (forbidden) | P0`
- [ ] `TC-SEC-017 | App errors page depuis user standard | Refusee | P0`
- [ ] `TC-SEC-018 | Logout puis navigateur back | Pages protegees redirigent sign-in | P1`
- [ ] `TC-SEC-019 | Expiration session | Redirection propre sign-in | P1`
- [ ] `TC-SEC-020 | Token invalide au sign-in | Erreur claire, pas crash | P1`

---

## M. Offres et livraison a convenir (10 cas)

- [ ] `TC-OFFER-001 | Acheteur envoie une offre depuis fiche produit | Message offre auto publie dans la chat room unique buyer+seller+product | P0`
- [ ] `TC-OFFER-002 | Vendeur accepte offre depuis chat | Statut offre passe accepte + message systeme visible pour les 2 participants | P0`
- [ ] `TC-OFFER-003 | Vendeur refuse offre depuis chat | Statut offre passe refuse + message systeme visible pour les 2 participants | P0`
- [ ] `TC-OFFER-004 | Vendeur propose contre-offre depuis chat | Meme offer thread mis a jour sans duplication de room | P0`
- [ ] `TC-OFFER-005 | Acheteur renvoie une nouvelle offre apres refus | Nouvelle carte offre creee, historique conserve, une seule room | P1`
- [ ] `TC-OFFER-006 | Plusieurs updates sur la meme offre (contre-offre successives) | Seule la carte la plus recente reste actionnable | P0`
- [ ] `TC-OFFER-007 | Offre seule (sans achat) | Aucune ligne expedition creee dans Mes ventes | P0`
- [ ] `TC-OFFER-008 | Achat en mode livraison a convenir (vendeur avec transporteurs configures) | Message chat cree, aucune action bordereau forcee | P0`
- [ ] `TC-OFFER-009 | Achat livraison courier standard (non convenir) | Ligne vente expedition creee normalement, bouton bordereau present | P0`
- [ ] `TC-OFFER-010 | Reouverture chat apres offres + commandes multiples | Toujours meme conversation_id pour buyer+seller+product | P0`

---

## 5) Lot de regression rapide avant release (smoke P0)
Executer minimum:
- `TC-AUTH-002`
- `TC-AUTH-006`
- `TC-AUTH-007`
- `TC-PROF-004`
- `TC-BROWSE-005`
- `TC-LIST-028`
- `TC-PROD-024`
- `TC-PROD-033`
- `TC-ORD-011`
- `TC-CHAT-013`
- `TC-CHAT-017`
- `TC-OFFER-002`
- `TC-OFFER-008`
- `TC-MOD-004`
- `TC-MOD-015`
- `TC-MOD-020`
- `TC-ERR-001`
- `TC-ERR-003`
- `TC-SEC-016`

## 6) Definition de sortie QA
Go release seulement si:
- 100% des P0 en PASS
- >= 95% des P1 en PASS
- 0 bug bloqueur ouvert sur Auth/Order/Chat/Moderation
- aucune fuite de permission role-based observee

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

