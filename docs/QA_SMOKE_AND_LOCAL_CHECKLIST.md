# QA Smoke and Local Test Checklist

## Scope
- Smoke test on `https://app.dzmarket.pro` and `https://api.dzmarket.pro`
- Local quality gate (`flutter test`, `flutter analyze`, staged integration)
- SLI quick check against production thresholds

## Preconditions
- Prod web deployed from latest `main`
- Test seller account available (example: `test2@gmail.com`)
- Browser cache and service worker cleared before web validation

## 1) Step 1 - Quality Gate (automated)

Run from repo root:

```powershell
.\scripts\run_quality_gate.ps1
```

Optional with integration + remote auth smoke:

```powershell
.\scripts\run_quality_gate.ps1 `
  -RunIntegration `
  -DeviceId <DEVICE_ID> `
  -IntegrationPhase smoke `
  -RunAuthSmoke `
  -AuthSmokeTestEmail <TEST_EMAIL>
```

What it executes:
- `flutter test` on core local suites
- `flutter analyze` on critical listing/i18n files
- optional staged integration phase (`scripts/run_integration_staged.ps1`)
- optional remote auth/API smoke (`scripts/auth_smoke_check.ps1`)

Pass criteria:
- All steps `PASS`
- No local test/analyze failures
- No auth template parsing errors in logs (if auth smoke enabled)

## 2) Step 2 - SLI Quick Check (automated)

Run from repo root:

```powershell
.\scripts\sli_quick_check.ps1
```

Custom window/threshold example:

```powershell
.\scripts\sli_quick_check.ps1 `
  -WindowMinutes 10 `
  -SampleCount 30 `
  -MaxP95AuthMs 450 `
  -MaxDbActivePct 80
```

What it validates:
- HTTP sample p95/error rate for:
  - `app_home`
  - `api_root`
  - `auth_health`
  - `storage_status`
- DB active connections ratio (`pg_stat_activity`)
- unhealthy Docker containers count
- Caddy 5xx rate over the selected window

Pass criteria:
- All checks `PASS`

## 3) Prod Smoke Checklist (manual)

### 3.1 Auth FR/AR
- Open sign-in page in FR, verify labels are translated (no `auth.*` keys).
- Switch to AR, verify labels and direction/spacing.
- Login and logout in FR and AR.

### 3.2 Password reset flow
- Trigger `mot de passe oublié`.
- Confirm reset email is received.
- Click reset link from email.
- Verify reset screen appears (new password + confirm password), update password, then sign in.

### 3.3 Seller create listing (8 steps)
- Login as seller.
- Complete steps 1..8 and publish.
- Verify listing appears in `Mes annonces` and browse list.

### 3.4 Notifications FR/AR
- Open `Profil -> Notifications` in FR then AR.
- Verify tabs/chips/labels/rows are translated.

### 3.5 Shipping label flow
- Open `Mes ventes`.
- Generate bordereau for target order.
- Click `Ouvrir label`.
- Verify URL is public (`https://api.dzmarket.pro/...`) and label opens.

## 4) Integration tests (USB, staged)

Do not run `flutter test integration_test -d <device>` directly.
Run phased batches:

```powershell
flutter devices
.\scripts\run_integration_staged.ps1 -DeviceId <DEVICE_ID> -Phase smoke
.\scripts\run_integration_staged.ps1 -DeviceId <DEVICE_ID> -Phase core
.\scripts\run_integration_staged.ps1 -DeviceId <DEVICE_ID> -Phase orders
.\scripts\run_integration_staged.ps1 -DeviceId <DEVICE_ID> -Phase chat
```

## 5) Sign-off Template
- Date:
- Commit:
- Tester:
- Step 1 Quality Gate: PASS/FAIL
- Step 2 SLI Quick Check: PASS/FAIL
- Auth FR/AR: PASS/FAIL
- Reset password: PASS/FAIL
- Seller listing flow: PASS/FAIL
- Notifications FR/AR: PASS/FAIL
- Label open flow: PASS/FAIL
- Blocking issues:
