# NEXT_STEPS

Last updated: 2026-03-03

## 1) Snapshot actuel
- Release web publique en production.
- Pipeline Android Google Play (internal testing) en cours.
- Pipeline iOS en preparation (Apple Developer en attente de validation complete).
- Load/perf valide en mode mixte:
  - PASS: `220 listings + 5 auth` (30m/60m/120m)
  - FAIL observe: `240 listings + 5 auth`
  - budget recommande: `195 listings + 4 auth`

## 2) Ce qui est termine
- Auth reset/password callback stabilise (URL web propres, sans page blanche).
- Correctifs i18n majeurs (fallback et resolution de cles) sur parcours critiques.
- Ouverture label PDF corrigee (URL publique, pas d'URL interne Kong/localhost).
- `job-runner` renforce:
  - compatibilite schema legacy `shipments`
  - envoi reminders `label_reminder` et `carrier_scan_reminder`
  - compteurs debug pour diagnostic.
- Runbooks de lancement + scripts QA/load en place.

## 3) Priorites immediates (J+7)
### P0
- Finaliser publication Android production (depuis internal testing -> production).
- Fermer la verification i18n FR/AR sur tous ecrans vendeur:
  - notifications
  - mes ventes
  - dashboard vendeur
  - mes annonces
  - transporteurs.
- Verifier en continu le flux retour vendeur (`historique retours`) sur commandes reelles.

### P1
- Stabiliser flux reminder transporteur sur les 4 transporteurs en production reel.
- Completer dossier publication iOS/TestFlight (des que compte Apple actif).
- Pack communication lancement (FR/AR): post, video courte, FAQ support.

### P2
- Optimisations read-path pour tenter `230+5` stable avec marge.
- Ajouter reporting hebdomadaire automatise (capacity tracker + synthese CSV).

## 4) Checklist execution quotidienne
```powershell
.\scripts\sli_quick_check.ps1 -WindowMinutes 10 -SampleCount 30
.\scripts\auth_smoke_check.ps1 -AppServerIp 91.107.239.5 -SshKeyPath "$env:USERPROFILE\.ssh\dzmarket_hetzner"
```

## 5) Criteria de passage "Scale +"
Autoriser augmentation trafic seulement si:
- 72h consecutives sans incident P1/P2
- SLI quick check PASS sur toutes fenetres de suivi
- auth smoke PASS
- flux e-commerce critiques PASS (achat -> ventes -> bordereau -> label)

## 6) Decision actuelle
- Production large: OK maintenue.
- Scale supplementaire: NON tant que `230+5` n'est pas valide en charge mixte avec marge.
