# BUSINESS PLAN DZMARKET (24 mois)

Date: 2026-02-12  
Portee: Algerie (DZ)  
Canal: Mobile-first + Web  
Roles produit: buyer, seller, superadmin

## 1. Resume executif

DZMarket est une marketplace locale orientee execution (annonce -> chat -> commande -> livraison -> suivi).  
La strategie recommandee est:
- Annee 1: acquisition massive avec coeur de service gratuit.
- Annee 2: monetisation progressive et propre (commission, options pro, promotion, paiement en ligne local).

Objectif business:
- Construire rapidement la liquidite du marche (offre + demande).
- Activer les revenus sans casser la croissance.
- Garder une UX simple, rapide, fiable.

## 2. Pourquoi "1 an gratuit" est pertinent en DZ

Oui, pour le marche algerien, une annee gratuite sur le coeur du service est pertinente si tu gardes une discipline KPI stricte.

Conditions pour que ce soit rentable:
- CAC bas (croissance organique, parrainage, contenu social).
- Frais infra maitrises.
- Taux de retention vendeur/acheteur qui monte chaque mois.
- Plan de monetisation deja prepare (pas improvise en annee 2).

## 3. Positionnement

Promesse utilisateur:
- "Vendre et acheter localement, simplement, avec livraison integree et chat propre."

Differentiateurs:
- Chat metier propre (thread unique buyer+seller+product).
- Integration transporteurs.
- Moderation superadmin + fiabilite operationnelle.
- UX FR/AR, contexte local DZ.

## 4. Strategie produit et revenus (par phases)

## 4.1 Phase A - Acquisition (M1 a M12)

Politique prix:
- Commission: 0%.
- Abonnement vendeur: 0 DZD.
- Publication annonce: gratuite.
- Chat / commande / suivi: gratuits.

Objectif phase A:
- Maximiser nombre d'annonces actives.
- Maximiser commandes reussies.
- Installer habitudes utilisateur.

Ce que tu peux monetiser legerement sans casser l'adoption:
- Boost annonce optionnel (petit prix), a activer seulement si traction stable.
- Service B2B optionnel pour vendeurs pro (support prioritaire), sans bloquer le coeur.

## 4.2 Phase B - Monetisation progressive (M13 a M24)

Activation revenus (ordre recommande):
1. Commission transaction livree: 2.5% puis 3.5% selon categorie.
2. Boost annonce (24h / 72h / 7j).
3. Packs vendeur pro (analytics, vitrines, outils bulk).
4. Services logistiques premium (selon marge reelle).

Regle:
- Jamais de frais sur commandes annulees.
- Facturation simple, lisible, previsible.

## 5. V2 Paiements locaux (Dahabia + CIB + autres)

Objectif:
- Ajouter paiement en ligne local sans casser COD.

Strategie:
- V2 garde COD actif.
- Ajout de paiement en ligne "opt-in" par vendeur.
- Rollout progressif par cohortes.

Perimetre V2:
- edahabia/carte CIB via PSP local/agregeur.
- event flow de paiement: intent -> authorize -> success/fail -> reconcile.
- gestion litiges/refunds minimale des le lancement.

Architecture metier:
- payment_intents et payment_events existent deja: exploiter ces tables.
- etats de commande alignes avec etats paiement.
- journalisation forte (audit logs) pour traçabilite.

Go-live V2 (recommande):
1. Beta interne (superadmin + testeurs).
2. Beta 5% vendeurs.
3. 25% vendeurs.
4. Activation generale.

## 6. Unit economics cible (modele simple)

Formule revenu mensuel:
- Revenu = (GMV_livree x take_rate) + revenus_boost + abonnements_pro + services

Repere prudent:
- take_rate moyen annee 2: 3.0% a 4.0%
- boost annonces: faible au debut, monte avec stock actif.
- abonnement pro: cible faible en % mais forte valeur par compte actif.

## 7. Projections 24 mois (scenarios)

Hypotheses communes:
- COD reste majoritaire au depart.
- Retours et annulations maitrisables via process.
- Infra self-host optimisee (cout fixe controle).

Scenario prudent (M24):
- MAU: 120k
- GMV mensuel: 120M DZD
- take_rate moyen: 3.0%
- revenu plateforme: 3.6M DZD/mois + options

Scenario central (M24):
- MAU: 220k
- GMV mensuel: 250M DZD
- take_rate moyen: 3.5%
- revenu plateforme: 8.75M DZD/mois + options

Scenario ambitieux (M24):
- MAU: 350k
- GMV mensuel: 420M DZD
- take_rate moyen: 4.0%
- revenu plateforme: 16.8M DZD/mois + options

Note:
- Ces chiffres sont des cibles de pilotage, pas des garanties.

## 8. KPIs de pilotage hebdo

Croissance:
- MAU buyer, MAU seller.
- Nouvelles annonces / annonces actives.
- Taux de reactivation a 30 jours.

Commerce:
- GMV, commandes creees, commandes livrees.
- Conversion vue produit -> commande.
- Annulation, retour, no-show.

Monetisation:
- take_rate effectif.
- revenu par commande livree.
- revenu boost / revenu abonnement.

Qualite operationnelle:
- temps moyen generation bordereau.
- echec API transporteur.
- incidents critiques app.

## 9. Plan go-to-market (12 mois)

Canaux prioritaires:
- social proof (TikTok/Instagram/Facebook local).
- referral in-app (parrainage vendeur + acheteur).
- communities locales par wilaya.

Execution:
1. M1-M3: traction localisee (wilayas pilotes).
2. M4-M6: extension categories fortes.
3. M7-M9: acceleration vendeurs semi-pro.
4. M10-M12: optimisation retention + pre-monetisation.

## 10. Politique de confiance et risque

Anti-abus:
- moderation annonces + signalements + masquage auto.
- suspension/bannissement en cas de fraude.

Risque paiement:
- anti-fraude basique en V2 (velocity, anomalies).
- reconciliation quotidienne des paiements.

Risque operationnel:
- cron reliability, alertes, runbooks incidents.
- fallback COD si incident PSP.

Risque legal/compliance:
- CGU/Confidentialite/Mentions legales a jour.
- gouvernance claire editeur legal (societe partenaire).

## 11. Roadmap business + produit

M1-M3:
- stabilite parcours commande/livraison/chat.
- dashboard pilotage KPI.

M4-M6:
- renforcer outils vendeur (stock/prix/perf).
- quality score acheteur/vendeur (non punitif).

M7-M9:
- prepa monetisation (boost infra, pricing tests).
- beta paiements en ligne local.

M10-M12:
- decision monetisation finale (tarifs).
- lancement offres payantes "soft".

M13-M18:
- commission faible + packs pro.
- extension paiements.

M19-M24:
- optimisation marge, segmentation categories.
- automatisation ops, baisse cout support.

## 12. Decision sur ta question (avis pro)

Oui:
- Annee 1 gratuite est un bon choix pour DZMarket.

Mais:
- Ce doit etre une gratuite "controlee par KPI", pas une gratuite sans limite.
- Le plan monetisation annee 2 doit etre pre-cable des maintenant.

Recommendation finale:
- Valider officiellement ce plan 24 mois.
- Geler les KPIs seuils (go/no-go) par trimestre.
- Garder COD + introduire Dahabia/CIB en V2 progressive.

## 13. Plan d'action immediat (30 jours)

1. Definir les seuils KPI trimestriels (croissance, qualite, cout).
2. Fixer grille tarifaire v2 draft (commission + boost + pro).
3. Spec produit "paiement en ligne v2" (etats, echec, remboursement).
4. Lancer dashboard unique business + ops (hebdo).
5. Preparer protocole beta vendeurs pour V2 paiements.


## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

