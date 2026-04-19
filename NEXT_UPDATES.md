# NEXT_UPDATES

Last update: 2026-03-03

## Objectif
Suivre les updates produit/ops post-lancement avec priorisation claire.

## Changements recents confirmes
- Correctif `job-runner` de compatibilite schema `shipments` legacy (`updated_at/events` absents).
- Ajout compteurs debug reminders (`carrier_scan_reminder_debug`) pour diagnostic rapide.
- Correctif URL labels (suppression fuites d'hotes internes, ouverture PDF fiable).
- Stabilisation PathUrlStrategy web et callback auth/reset.
- Validation charge mixte et budget d'exploitation defini.

## P0 - A faire maintenant
- Validation finale i18n FR/AR des ecrans vendeur a fort impact:
  - notifications
  - mes ventes
  - tableau de bord
  - mes annonces
  - parametres transporteur
- Publication Android production apres validation internal track.
- Validation reminder transporteur en conditions reelles sur les 4 carriers.

## P1 - Prochain sprint
- Optimisations read-path listings pour `230+5` stable.
- Ajout auto-export des resultats k6 + SLI dans `k6-results` (rapport unifie).
- Documentation de support utilisateur (FAQ incidents login/livraison/label).

## P2 - Suivant
- Pipeline iOS/TestFlight complet (quand Apple Developer actif).
- Dashboard metier compact (conversion browse->achat, bordereaux, retours).
- Reduction cout infra (cache + index + compression assets).

## DoD release patch
- Tests automatiques: PASS
- Smoke manuel P0: PASS
- SLI quick check: PASS
- Auth smoke: PASS
- Aucun bug bloquant ouvert sur Auth/Order/Shipment/Label/Chat.
