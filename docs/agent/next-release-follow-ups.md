# DZMarket - Suivi prochaine version

Mis a jour : 2026-11-13. Cette fiche ne contient que les constats utiles
depuis les dernieres releases. Elle ne remplace ni les logs de production ni
les tests de release.

## A corriger - Android

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

## Decision de release

- Hotfix web deja deploye le 5 novembre (templates auth-email + permissions
  de repertoires) -- pas d'action supplementaire cote web pour l'instant.
- Preparer une petite release Android/iOS (build 44) pour le correctif du
  selecteur d'images, deja valide en reel sur appareil -- publication
  (Play Console / Codemagic) en attente des acces necessaires.
