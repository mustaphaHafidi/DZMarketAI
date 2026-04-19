# QA Smoke & Local Checklist - DZMarket

Last update: 2026-03-03

## 1) Portee
Checklist de validation release pour:
- qualite locale (tests + analyze)
- smoke production (FR/AR)
- controle auth/mail/labels
- verifications post-deploiement

## 2) Preconditions
- Web prod deploye (`https://app.dzmarket.pro`).
- API prod accessible (`https://api.dzmarket.pro`).
- Acces SSH app server avec cle valide.
- Comptes test buyer/seller disponibles.

## 3) Qualite locale (automatique)
```powershell
.\scripts\run_quality_gate.ps1
```

Option integration par phases:
```powershell
flutter devices
.\scripts\run_integration_staged.ps1 -DeviceId <DEVICE_ID> -Phase smoke
.\scripts\run_integration_staged.ps1 -DeviceId <DEVICE_ID> -Phase core
.\scripts\run_integration_staged.ps1 -DeviceId <DEVICE_ID> -Phase orders
.\scripts\run_integration_staged.ps1 -DeviceId <DEVICE_ID> -Phase chat
```

## 4) Smoke production (automatique)

### SLI quick check
```powershell
.\scripts\sli_quick_check.ps1 -WindowMinutes 10 -SampleCount 30 -SshKeyPath "$env:USERPROFILE\.ssh\dzmarket_hetzner"
```

### Auth/API/templates check
```powershell
.\scripts\auth_smoke_check.ps1 -AppServerIp 91.107.239.5 -SshKeyPath "$env:USERPROFILE\.ssh\dzmarket_hetzner"
```

Important:
- `-SendRecoveryTest` peut retourner `429` si relance trop rapide; a utiliser uniquement pour un test ponctuel de l'envoi recovery.

## 5) Smoke manuel critique (P0)
1. Auth FR/AR:
   - login/logout
   - reset password via email
   - aucun ecran blanc
2. Creation annonce vendeur:
   - etapes 1->8
   - publication visible dans `Mes annonces`
3. Achat buyer:
   - checkout complet
   - commande visible buyer/seller
4. Mes ventes vendeur:
   - generation bordereau
   - `Ouvrir label` ouvre PDF
5. Notifications/chat:
   - messages systeme commande visibles
   - traduction FR/AR OK
6. Retours:
   - ecran historique retours charge sans erreur

## 6) Cas recents a rejouer obligatoirement
- Ouverture label commande (pas de page noire).
- Flux callback auth/reset sans `#` parasite.
- Reminders job-runner (`label_reminder`, `carrier_scan_reminder`) visibles cote messages.
- Affichage i18n sans cles brutes (`auth.*`, `listing.*`, `shipments.*`).

## 7) Sign-off template
- Date:
- Commit SHA:
- Tester:
- run_quality_gate: PASS/FAIL
- sli_quick_check: PASS/FAIL
- auth_smoke_check: PASS/FAIL
- Smoke manuel P0: PASS/FAIL
- Bloquants ouverts:

## 8) Rule go/no-go
GO seulement si:
- 100% P0 PASS
- scripts automatiques PASS
- aucun bloquant auth/order/label/chat
