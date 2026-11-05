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
- **Etat** : correctif implemente localement le 5 novembre : etat local de
  selection en cours, action desactivee pendant l'attente, reinitialisation dans
  `finally`, test widget de double appui vert. Il reste la verification manuelle
  Android et la publication d'une nouvelle version mobile.
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

## Garde-fou web a conserver

- Une ancienne livraison web avait omis les polices Material/Cupertino et le
  favicon, ce qui affichait des symboles de remplacement. Le correctif et le
  controle d'artefact sont deja livres dans `scripts/verify_web_artifact.ps1`.
- Avant chaque deploiement web, executer ce controle et verifier dans le navigateur
  que les deux fichiers de police et `favicon.png` repondent HTTP 200. Ce point
  est deja corrige : ne pas creer un nouveau correctif tant que le controle passe.

## Decision de release

- Pas de hotfix ni de deploiement web justifie par les erreurs actuelles.
- Preparer une petite release Android seulement si l'erreur de selection d'images
  se reproduit, ou apres validation du correctif cible ci-dessus.
