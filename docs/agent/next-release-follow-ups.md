# DZMarket - Suivi prochaine version

Mis a jour : 2026-11-05. Cette fiche ne contient que les constats utiles
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
- **Etat** : correctif implemente et verifie en reel sur appareil Android
  (Samsung USB, phase smoke `integration_test`) le 5 novembre. Il reste la
  publication d'une nouvelle version mobile (build 44, le build 43 est deja
  distribue en 1.0.8).
- **Limite volontaire** : ne pas etendre a l'avatar ou a la modification
  d'annonce sans occurrence confirmee dans ces ecrans.

## A surveiller - pas de correctif ni de release urgente

- **Reseau mobile Android** : deux erreurs entre le 29 octobre et le 4 novembre
  correspondent a une connexion interrompue vers l'API et a une horloge de
  telephone en avance (`JWT issued at future`). Elles ne sont pas reproduites
  cote serveur.
- **Infrastructure** : au controle du 5 novembre, `www`, `app` et `api`
  repondaient HTTP 200; Caddy, Auth, Edge Functions et PostgreSQL etaient sains,
  sans 5xx observe. Les lignes Caddy `client disconnected` ne sont pas une panne
  applicative sans hausse de 5xx ou erreur utilisateur correlee.

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
