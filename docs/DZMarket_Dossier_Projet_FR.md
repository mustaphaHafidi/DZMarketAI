# DZMarket - Dossier Projet (Version 2026)

Date: 2026-03-03
Version: 2.0
Audience: partenaires, investisseurs, equipe technique

## 1) Resume executif
DZMarket est une marketplace mobile/web orientee Algerie, avec parcours complet:
- publication annonce
- recherche/filtres
- offre et achat
- commande et livraison multi-transporteurs
- chat et notifications
- moderation et supervision superadmin

Le produit est en production web et en phase de publication mobile, avec un socle technique auto-heberge maitrise.

## 2) Positionnement produit
DZMarket cible:
- acheteurs et vendeurs particuliers
- vendeurs recurrents ayant besoin d'un flux logistique integre
- equipe operationnelle qui suit qualite, retours et incidents

Differenciation:
- UX FR/AR
- transporteurs integres (Yalidine, Ecotrack, ZR Express, Guepex)
- chat central dans le flux commande
- operations supervisees (runbooks, smoke, SLI, charge)

## 3) Parcours metier
### Acheteur
1. Login/sign-up
2. Recherche produit
3. Offre ou achat direct
4. Choix livraison
5. Suivi commande + chat

### Vendeur
1. Activation mode vendeur
2. Creation annonce (wizard 8 etapes)
3. Gestion `Mes ventes`
4. Generation bordereau
5. Ouverture label PDF

### Superadmin
1. Moderation utilisateurs/annonces
2. Supervision erreurs
3. Controle qualite des flux critiques

## 4) Architecture technique
- Frontend: Flutter (Android/Web; iOS pipeline en cours)
- Backend: Supabase self-host (Auth, PostgREST, Storage, Realtime, Edge Functions)
- Infra: Hetzner + Caddy + Kong + MinIO + PostgreSQL

Domaines:
- `app.dzmarket.pro`
- `api.dzmarket.pro`
- `www.dzmarket.pro` / `dzmarket.pro` -> redirect app

## 5) Corrections majeures recemment livrees
- Reset mot de passe / callback web stabilises.
- URL label publiques normalisees (`api.dzmarket.pro`) pour eviter pages noires.
- `job-runner` renforce:
  - compatibilite schema legacy `shipments`
  - reminders transporteur (`label_reminder`, `carrier_scan_reminder`)
  - compteurs debug pour diagnostic.
- i18n fallback durci (reduction des cles brutes affichees en UI).

## 6) Qualite et tests
Couverture active:
- tests unitaires Flutter
- tests integration par phases
- smoke manuel E2E
- scripts ops (`sli_quick_check`, `auth_smoke_check`)
- charge k6 (listings/auth/orders/shipments)

Reference test cases:
- `E2E_MANUAL_TEST_CASES.md`
- `E2E_MANUAL_TEST_CASES_AR.md`

## 7) Capacite validee
Campagnes de charge recentes:
- PASS: `220 listings + 5 auth` (60m et 120m)
- FAIL observe: `240 listings + 5 auth`

Decision exploitation:
- budget recommande: `195 listings + 4 auth` (marge de securite)

## 8) Runbook operations
Outils standards:
- `scripts/run_quality_gate.ps1`
- `scripts/sli_quick_check.ps1`
- `scripts/auth_smoke_check.ps1`
- `scripts/run_k6_mix_matrix.ps1`

Runbooks:
- `docs/GO_NO_GO_PUBLIC_LAUNCH.md`
- `docs/PUBLIC_LAUNCH_RUNBOOK_J0_J1.md`
- `docs/SLO_SLI_DZMARKET.md`
- `docs/LOAD_TEST_PLAN_1M.md`

## 9) Risques et maitrise
Risques principaux:
- surcharge browse
- timeouts auth sous charge
- incidents transporteur

Mesures:
- budget de trafic operational
- monitoring SLI periodique
- rollback documente
- reminders automatiques + supervision messages

## 10) Roadmap court terme (30 jours)
1. Finaliser publication Android production.
2. Finaliser publication iOS/TestFlight (Apple Developer).
3. Verrouiller i18n FR/AR sur ecrans vendeur critiques.
4. Optimiser read-path pour valider `230+5` stable.

## 11) Conclusion
DZMarket est operationnel, documente, et teste sur des parcours critiques concrets. La strategie actuelle privilegie la fiabilite et la progression controlee avant toute montee de charge supplementaire.
