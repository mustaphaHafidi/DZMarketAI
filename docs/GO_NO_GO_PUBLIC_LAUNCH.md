# DZMarket - Go / No-Go Public Launch

Last update: 2026-03-03

## 1) Gate technique (obligatoire)

```powershell
.\scripts\run_quality_gate.ps1
.\scripts\run_k6_mix_matrix.ps1 -EnvFile .\load\env.local -ListingsVus "220" -AuthVus 5 -Duration 60m -RunSliCheck
.\scripts\sli_quick_check.ps1 -WindowMinutes 10 -SampleCount 30 -SshKeyPath "$env:USERPROFILE\.ssh\dzmarket_hetzner"
.\scripts\auth_smoke_check.ps1 -AppServerIp 91.107.239.5 -SshKeyPath "$env:USERPROFILE\.ssh\dzmarket_hetzner"
```

Condition PASS:
- Tous les scripts PASS
- Aucun seuil critique casse

## 2) Gate fonctionnel (obligatoire)

Rejouer la smoke E2E P0:
- Auth/login/logout/reset
- i18n FR/AR ecrans critiques
- creation annonce vendeur
- achat buyer
- `Mes ventes` -> bordereau -> `Ouvrir label`
- notifications/chat/retours vendeur

Condition PASS:
- 100% P0 PASS
- Aucun ecran blanc
- Aucune cle i18n brute visible

## 3) Gate capacite
- Reference validee: `220 listings + 5 auth`.
- Budget prod recommande: `195 + 4` pour marge.

Condition PASS:
- scenario mixte PASS sur la fenetre cible
- SLI post-run PASS

## 4) Gate operations
- Rollback documente et teste (web + backend).
- Sauvegarde DB recente validee.
- Monitoring renforce (24h puis 48h).

## 5) Decision
- GO: toutes les gates PASS
- NO-GO: au moins une gate FAIL

## 6) Etat courant
- Lancement public web: GO maintenu.
- Android: track internal testing actif, publication production en cours de finalisation.
- iOS: preparation pipeline (Apple Developer requis).
