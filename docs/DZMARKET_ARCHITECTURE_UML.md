# DZMarket - Architecture et Conception UML

Date: 2026-03-03
Portee: Flutter (Android/Web) + Supabase self-host + Hetzner

## 1) Vue contexte
Acteurs:
- Acheteur
- Vendeur
- Superadmin
- Transporteurs (Yalidine, Ecotrack, ZR Express, Guepex)

Systemes:
- App DZMarket (Flutter)
- API DZMarket (Supabase/Kong)
- Data DZMarket (PostgreSQL + Storage)

## 2) Vue containers
- Caddy (TLS + reverse proxy)
- Kong (gateway)
- GoTrue (auth)
- PostgREST
- Realtime
- Storage
- Edge Functions
- PostgreSQL
- MinIO

## 3) Topologie deploiement
- `dzm-app-01`: Caddy + stack Supabase
- `dzm-db-01`: PostgreSQL
- `dzm-storage-01`: MinIO

Domaines:
- `app.dzmarket.pro`
- `api.dzmarket.pro`
- `www.dzmarket.pro` / `dzmarket.pro` -> app

## 4) Architecture Flutter
- `lib/src/features/*` : UI par domaine
- `lib/src/services/*` : logique metier
- `lib/src/models/*` : modeles
- `lib/src/router.dart` : routing + guards
- `lib/src/widgets/web_frame.dart` : adaptation layout web

## 5) Sequences UML critiques

### Auth reset
1. utilisateur demande reset
2. email recovery envoye
3. callback `/auth/callback`
4. redirection reset-password
5. mot de passe mis a jour

### Achat -> livraison
1. buyer passe commande
2. seller genere bordereau
3. label stocke + URL resolue publique
4. buyer/seller suivent le statut en chat/notifications

### Reliability jobs
1. `job-runner` scanne commandes
2. reminders (`label_reminder`, `carrier_scan_reminder`)
3. stale orders annulees selon regles
4. messages systeme publies

## 6) Decisions techniques
- Une room chat canonique par `buyer + seller + product`.
- Validation livraison cote backend (edge functions + SQL guards).
- Compatibilite schema legacy preservee dans `job-runner`.
- i18n FR/AR avec fallback durci.

## 7) Points de vigilance
- charge browse (read-path)
- latence auth sous charge
- fiabilite APIs transporteurs
- gestion secrets et rotation cles

## 8) Documents relies
- `docs/SLO_SLI_DZMARKET.md`
- `docs/LOAD_TEST_PLAN_1M.md`
- `docs/QA_SMOKE_AND_LOCAL_CHECKLIST.md`
- `docs/GO_NO_GO_PUBLIC_LAUNCH.md`
