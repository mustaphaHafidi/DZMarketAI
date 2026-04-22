# DZMarket 1.0.3 Stability Update

Updated: 2026-04-22
Status: proposed next release
Scope: web + android + ios + admin

## 1) Objectif

La version `1.0.3` doit etre une release de stabilisation et d'alignement mobile.

Ce n'est pas une release de grosse nouveaute produit.

Elle sert a:

- consolider les correctifs deja faits sur le web
- reduire les erreurs utiles restantes en prod
- aligner Android et iOS avec le web
- fiabiliser les parcours seller, buyer et superadmin

## 2) Positionnement

Nom recommande:

- `DZMarket 1.0.3 - Stability Update`

Promesse produit:

- experience FR/AR plus propre
- auth et profils plus fiables
- suivi vendeur/chat plus coherent
- back-office admin plus solide
- build mobile aligne avec la prod web

## 3) In Scope

### 3.1 Stabilisation produit

- auth FR/AR
- champs email des ecrans auth
- profils publics
- avatars upload/delete/fallback
- favoris web/mobile
- detail annonce web
- livraison a convenir
- tableau de livraisons vendeur
- notifications simplifiees

### 3.2 Stabilisation admin

- demandes de suppression
- moderation
- journal d'erreurs

### 3.3 Stabilisation technique

- medias legacy
- bruit realtime utile
- dernieres erreurs RLS/profils
- pack QA release

## 4) Hors Scope

- nouveau paiement en ligne
- refonte majeure catalog/recherche
- nouveau systeme d'avis
- refonte chat complete
- nouvelle architecture backend
- hard delete automatique des comptes

## 5) Travaux Exactes

### 5.1 Workstream A - Error Triage et Fixes

Objectif:

- traiter les erreurs encore actionnables dans le journal superadmin

Checklist:

- corriger les derniers cas de medias legacy non normalises
- verifier les avatars encore cassables en lecture
- reduire les erreurs realtime non actionnables
- verifier qu'aucun flux profil n'ecrit encore un role invalide
- verifier qu'aucune image critique buyer/seller ne casse le rendu principal

Critere de sortie:

- plus aucune erreur critique repetee liee aux medias legacy
- plus aucune erreur RLS profil reproductible

### 5.2 Workstream B - Account Deletion V2

Objectif:

- rendre le workflow de demande de suppression coherent et exploitable

Checklist:

- verifier la file superadmin `pending / processing / completed / rejected`
- verifier les actions `restreindre`, `reactiver`, `cloturer`
- definir la regle manuelle de traitement final
- verifier la trace admin:
  - `processed_by`
  - `processed_at`
  - `admin_note`
  - `account_status_before`
  - `account_status_after`

Critere de sortie:

- une demande user peut etre creee, traitee, cloturee et tracee sans ambiguite

### 5.3 Workstream C - Web/Mobile Parity

Objectif:

- embarquer dans Android/iOS les correctifs deja valides sur le web

Checklist:

- auth email FR/AR
- icones/champs auth cohérents en RTL
- profil public selon `is_public`
- avatars fallback 2 initiales
- upload/suppression avatar
- chat livraison a convenir
- tableau vendeur livraisons
- notifications simplifiees
- demandes de suppression visibles/correctes

Critere de sortie:

- aucun ecart critique connu entre web et mobile sur les parcours principaux

### 5.4 Workstream D - Seller Reliability

Objectif:

- rendre les ecrans vendeur plus fiables et coherents

Checklist:

- verifier `Mes ventes`
- verifier `Tableau de livraisons`
- verifier ouverture bordereau depuis dashboard
- verifier ouverture bordereau depuis chat
- verifier profils publics depuis annonce et chat
- verifier `livraison a convenir` sans faux tracking

Critere de sortie:

- les flux seller passent sans ecran vide, faux wording, ou faux tracking

### 5.5 Workstream E - Release QA

Objectif:

- executer un vrai pack de regression avant republication mobile

Checklist:

- buyer FR
- buyer AR
- seller FR
- seller AR
- superadmin FR
- superadmin AR
- login / logout
- switch langue
- parcourir
- detail annonce
- favoris
- chat
- profil public
- avatar
- notifications
- tableau de livraisons
- moderation
- demandes de suppression

Critere de sortie:

- pack regression passe
- aucun blocage P0/P1 ouvert au moment du go/no-go

## 6) Definition of Done

La `1.0.3` est consideree prete si:

- le web est stable en prod
- `flutter test` passe
- `flutter analyze` passe
- `flutter build web` passe
- `flutter build appbundle` passe
- le build iOS Codemagic passe
- le smoke FR/AR buyer/seller/superadmin passe
- aucun bug bloquant n'est ouvert sur auth, chat, livraisons, profil, admin

## 7) Checklist Publication

### 7.1 Web

- build web release
- deploy prod
- hard refresh et smoke MCP

### 7.2 Android

- increment `versionCode`
- build AAB
- upload track cible
- review Play Console
- verification closed testing / production selon contexte

### 7.3 iOS

- increment build number
- lancer Codemagic
- verifier upload App Store Connect
- verifier TestFlight
- verifier Distribution si App Store submission

## 8) Risques Connus

- service worker Flutter web pouvant servir un ancien bundle
- medias legacy encore presents en base
- differents comportements web/mobile sur Flutter web et champs RTL
- bruit realtime pouvant polluer la lecture du journal d'erreurs

## 9) Priorite Recomandee

Ordre de travail recommande:

1. erreurs critiques utiles
2. workflow suppression de compte
3. parity mobile
4. seller reliability
5. regression pack
6. republication Android/iOS

## 10) Decision Go/No-Go

Go si:

- aucun P0/P1 ouvert
- auth FR/AR stable
- seller dashboard stable
- chat stable
- deletion workflow stable
- build Android et iOS valides

No-Go si:

- login FR/AR casse
- ecrans vendeur critiques cassent
- profils publics exposent mal les regles de confidentialite
- admin suppression/moderation est incoherent
- build mobile final echoue
