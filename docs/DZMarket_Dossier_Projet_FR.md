# DZMarket - Dossier Projet Complet (Version Presentation)

Date: 12 fevrier 2026
Version: 1.0
Audience: actionnaires, collaborateurs, partenaires techniques

## 1. Resume executif

DZMarket est une marketplace mobile-first pour le marche algerien.
La plateforme couvre tout le cycle e-commerce local:
- publication d'annonces
- recherche et filtres
- negociations via offres
- commande et livraison multi-transporteurs
- chat vendeur/acheteur integre
- moderation et supervision superadmin

Objectif principal:
- une application simple pour l'utilisateur final
- une logique metier robuste pour la scalabilite
- une exploitation operationnelle propre pour un usage grand public

## 2. Positionnement produit

DZMarket cible:
- particuliers qui vendent/achetent localement
- vendeurs reguliers avec besoin de logistique integree
- equipe centrale qui supervise qualite, abus et fiabilite

Valeur ajoutee:
- UX simple FR/AR
- transporteurs integres (Yalidine, Ecotrack, ZR Express)
- processus commande bout en bout sans sortir de l'app
- moderation et controle qualite avec role superadmin

## 3. Acteurs et droits

Acteurs metier actifs:
- buyer
- seller
- superadmin

Points importants:
- le role legacy `admin` est mappe vers `superadmin` dans l'app pour compatibilite.
- les regles d'acces sont renforcees par RLS cote base de donnees.

## 4. Parcours utilisateur end-to-end

### 4.1 Parcours acheteur

1. Authentification email/mot de passe.
2. Navigation dans Parcourir avec recherche et filtres rapides.
3. Consultation fiche produit.
4. Contact vendeur via chat ou achat direct.
5. Choix livraison et transporteur selon options autorisees.
6. Confirmation commande.
7. Suivi statut commande et suivi transporteur.
8. Echange dans chat jusqu'a livraison.

### 4.2 Parcours vendeur

1. Activation mode vendeur.
2. Creation d'annonce par etapes:
   photos, categorie, details, prix/stock, localisation, livraison.
3. Reception commandes dans Mes ventes.
4. Generation bordereau depuis l'ecran d'expedition.
5. Suivi logistique et communication acheteur en chat.
6. Gestion cycle de vie annonce (active, archivee, vendue).

### 4.3 Parcours superadmin

1. Acces ecran moderation.
2. Suivi utilisateurs (actif/suspendu/banni).
3. Suivi annonces (approved/masked/blocked).
4. Gestion signalements.
5. Consultation erreurs applicatives (actuelles + archive).
6. Pilotage de la qualite et reduction des risques operationnels.

## 5. UX et principes produit

Principes UX appliques:
- parcours courts
- feedback clair sur erreurs
- localisation FR/AR
- action principale evidente
- reduction des ecrans surcharges

Choix UX structurant:
- une seule room de chat par thread metier:
  `buyer + seller + product`
  quel que soit le mode de livraison, le transporteur ou le nombre de commandes.

Impact:
- moins de confusion utilisateur
- historique conversation centralise
- meilleure lisibilite pour le support et la moderation

## 6. Fonctionnalites detaillees

### 6.1 Authentification et compte

- login email/password
- gestion erreurs:
  email/mot de passe incorrect
  compte suspendu
  compte banni
- reset mot de passe
- pages legales accessibles depuis auth

### 6.2 Profil

- infos personnelles
- avatar
- langue FR/AR
- wilaya/daira par selecteurs (pas saisie libre)
- option profil public
- bascule mode vendeur

### 6.3 Parcourir

- recherche texte
- chips rapides:
  categorie, prix, proximite
- panneau "tous les filtres"
- sauvegarde et suppression de filtres enregistres
- favoris

### 6.4 Produit et annonce

- fiche produit complete
- affichage vendeur public
- offre de prix
- signalement annonce
- creation annonce guidee
- validations livraison et dimensions

### 6.5 Logique grand volume

Pour limiter les erreurs logistiques:
- detection produits grands volumes par poids/dimensions/mots-cles
- forcer le mode pickup/main propre si produit volumineux

### 6.6 Commande et checkout

- creation commande atomique via RPC
- reservation stock immediate
- anti-achat de son propre produit
- anti-duplicate commande sur fenetre courte
- support commandes multiples tant que stock disponible

### 6.7 Livraison

- transporteurs integres:
  Yalidine, Ecotrack, ZR Express
- generation bordereau cote vendeur
- tracking mis a jour dans commandes et chat

### 6.8 Chat

- messagerie buyer/seller temps reel
- messages systeme de cycle commande
- deduplication anti doublons
- masquage/restauration conversation
- unread tracking

### 6.9 Moderation

- statuts utilisateur:
  active, suspended, banned
- statuts annonce:
  approved, masked, blocked
- file signalements
- seuil de signalements pour masquage automatique

### 6.10 Erreurs app et observabilite

- journalisation erreurs client
- vue "Actuelles" et "Archive"
- historique exploitable pour correction rapide

## 7. Logique metier critique

### 7.1 Chat unique par thread

Regle:
- un seul thread conversationnel pour un couple buyer/seller sur un produit.

But:
- eviter fragmentation conversations
- conserver contexte unique des echanges

### 7.2 Stock et commandes

Regle:
- stock decremente a creation de commande (reservation).
- commande refusee si stock nul.

But:
- eviter survente
- garantir coherence de l'etat produit

### 7.3 Anti-duplicate commande

Regle:
- blocage uniquement pour tentative quasi identique dans une fenetre courte.
- une nouvelle commande differente (courier/mode/adresse) est autorisee si stock disponible.

But:
- bloquer double clic involontaire
- ne pas casser les cas legitimes

### 7.4 Auto-cancel commande stale

Regle:
- commande en attente sans bordereau apres delai cible: annulation automatique.
- message systeme dans chat pour informer les deux parties.

But:
- maintenir hygiene operationnelle
- limiter commandes "zombies"

## 8. Architecture technique

Front:
- Flutter (Android, iOS, Web, Desktop)

Backend:
- Supabase:
  Postgres, Auth, RLS, Realtime, Storage, Edge Functions

Fonctions Edge cle:
- create_shipment
- job-runner
- courier-locations
- validate-courier

## 9. Securite et conformite

Mesures structurelles:
- RLS sur tables sensibles
- separation anon key / service role key
- tokens transporteurs uniquement cote backend
- bucket labels prive
- audit et abuse logs

Moderation:
- blocage contenus non conformes
- suspension/bannissement utilisateur
- signalements traces

## 10. Fiabilite et operations

CI:
- analyse + tests automatiques

Cron ops:
- workflow job-runner quotidien
- detection anomalies (echecs API courier, erreurs jobs, anomalie retours)
- creation/mise a jour d'issues GitHub ops-monitor

## 11. Scalabilite

Strategie de progression:
- phase 1: architecture stable et economique
- phase 2: separation charge lecture/ecriture
- phase 3: haute disponibilite

Principes:
- pagination stricte
- limites d'affichage par defaut
- cache intelligent
- index DB cibles

## 12. KPIs a suivre

KPIs produit:
- taux conversion visite -> commande
- temps moyen creation annonce
- taux abandon checkout

KPIs operations:
- commandes stale annulees
- taux echec bordereau par transporteur
- temps median resolution erreur critique

KPIs qualite:
- taux signalement annonces
- taux faux positifs moderation
- stabilite chat (duplication/perte room)

## 13. Risques et mitigation

Risque:
- echec API transporteur.
Mitigation:
- retries, logs, alertes cron.

Risque:
- surcharge moderation.
Mitigation:
- files priorisees, regles automatiques, statut clair.

Risque:
- confusion utilisateur sur livraison.
Mitigation:
- UX simplifiee, champs lockes selon contexte, textes explicites.

## 14. Plan 90 jours recommande

Mois 1:
- stabilite flows critiques
- QA manuel complet (FR/AR)
- reduction erreurs P0/P1

Mois 2:
- optimisation UX vendeur expedition
- amelioration monitoring ops
- automatisation cas de regression

Mois 3:
- renforcement scalabilite
- consolidation KPI business/ops
- preparation extension marche

## 15. Annexes projet

Documents de reference:
- README.md
- PLAN_1M_USERS.md
- SKILL_DZmarketAI.md
- Skill_DB.md
- E2E_MANUAL_TEST_CASES.md
- E2E_MANUAL_TEST_CASES_AR.md
- infra/SELF_HOST_SUPABASE_PLAN.md

Conclusion:
DZMarket dispose d'une base produit et technique solide, avec une logique metier deja orientee exploitation reelle. Le plan de travail priorise la fiabilite, la clarte UX et la scalabilite progressive, ce qui est adapte a une presentation actionnaires et a une execution terrain.

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

