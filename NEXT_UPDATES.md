# NEXT_UPDATES

Last update: 2026-02-13

## Objectif
Centraliser les priorites de delivery produit/technique avant le prochain release candidate.

## Etat courant
- Guepex integre dans le meme pipeline que Yalidine, EcoTrack, ZR Express.
- Moderation image/texte active dans la creation annonce.
- Politique moderation stricte active (`MODERATION_FAIL_OPEN=false`).
- Chat UX modernise (hub plus lisible, badge discret hors ligne).
- Offre en chat stabilisee avec dedupe des actions visibles.

## P0 - Blocants release
- Valider E2E complet "offre -> reponse vendeur -> re-offre" dans une seule chat room.
- Verifier "livraison a convenir" sans faux flux bordereau cote vendeur.
- Rejouer `supabase.sql` sur base legacy et base neuve (zero erreur bloquante).
- Verifier que `mes ventes` ne cree pas de ligne expedition sur simple proposition d'offre.

## P1 - Qualite UX et fiabilite
- Ajuster fiche produit (hierarchie visuelle, tags, prix, CTA) sans casser logique.
- Finaliser textes FR/AR pour transport, moderation et offres.
- Ajouter tableau de bord minimal pour echec API transporteur par run cron.

## P2 - Post RC
- Dashboards conversion (vue produit -> offre -> commande).
- Optimisation media reseau faible.
- Nettoyage final Firebase config (google_app_id) par flavor.

## Actions recentes confirmees
- `supabase functions deploy moderate-content` effectue.
- Secret `MODERATION_FAIL_OPEN=false` configure.
- Guards SQL offers ajoutes pour compatibilite des schemas existants.
- Support Guepex ajoute dans:
- `create_shipment`
- `courier-locations`
- `validate-courier`
- `job-runner`

## Definition of Done (release gate)
- Tous les tests P0 passes.
- Aucun bug bloquant ouvert sur Auth, Listing publish, Offer, Order, Shipment, Chat.
- Functions critiques deployees et verifiees sur projet Supabase cible.
- QA FR/AR validee sur device reel USB.
