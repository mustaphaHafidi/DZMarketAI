# NEXT_UPDATES

Last update: 2026-02-12

## Objectif
Centraliser les prochaines etapes prioritaires de DZMarket pour une mise en production fiable.

## Priorite P0 - Freeze Technique (Release Candidate)
- Stop nouvelles features pendant le freeze.
- Autoriser uniquement bugfixs bloquants.
- Aligner schema DB entre `supabase.sql` et `supabase/migrations/*`.
- Verifier un setup from-scratch (DB vide + migrations + app).
- Creer branche release: `release/0.9-rc1`.
- Tag candidate: `v0.9.0-rc1`.

## Priorite P1 - QA E2E 3 Acteurs
- Executer tous les cas manuels FR: `E2E_MANUAL_TEST_CASES.md`.
- Executer tous les cas manuels AR: `E2E_MANUAL_TEST_CASES_AR.md`.
- Parcours complets:
- Acheteur: annonce -> commande -> chat -> suivi.
- Vendeur: creation annonce -> bordereau -> statut commande.
- Superadmin: moderation users/annonces/signalements + erreurs app.
- Reseau faible/offline:
- Verifier retry, messages UX propres, zero crash.

## Priorite P2 - Fiabilite Production
- Corriger warning Firebase config (`google-services` / `google_app_id`).
- Valider job cron + alertes:
- Echec API transporteur.
- Hausse erreurs.
- Retour stats anormales.
- Verifier backup + restore DB.
- Verifier retention logs (`app_errors`) et cout stockage.

## Priorite P3 - Go-Live Controle
- Deploiement progressif:
- Lot pilote interne.
- Petit pourcentage utilisateurs.
- Generalisation.
- Dashboard de suivi go-live:
- Erreurs critiques.
- Latence.
- Taux commande echouee.
- Taux creation annonce echouee.
- Regle rollback:
- Seuils clairs pour revenir version precedente.

## Definition Of Done (RC -> Prod)
- `flutter analyze` sans erreur.
- Flux critiques valides E2E FR/AR.
- Aucune erreur bloquante ouverte (P0/P1).
- Monitoring et alertes actives.
- Build Android release testee sur appareils cibles.

## Backlog Apres Production (P4)
- Optimisation performance images et cache avance.
- Ameliorations funnel (conversion achat/vente).
- V2 paiement local (CIB/Edahabia, selon faisabilite legale/partenaires).
- Outils moderation assistes IA (image+texte) avec review humaine.

## Proprietaires
- Produit/UX: Mustapha
- Mobile app: DZMarket engineering
- Backend/Infra: Supabase + CI/CD owner
- QA: testeur manuel (FR/AR)
