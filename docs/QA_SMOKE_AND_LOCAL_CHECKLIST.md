# QA Smoke and Local Test Checklist

## Scope
- Smoke test on `https://app.dzmarket.pro` and `https://api.dzmarket.pro`
- Local quality gates (`flutter test`, `flutter analyze`)

## Preconditions
- Prod web is deployed from latest `main`
- Test seller account available (example: `test2@gmail.com`)
- Browser cache and service worker cleared before web validation

## A) Prod Smoke Checklist (manual)

### A1. Auth FR/AR
- Open sign-in page in FR, verify labels are translated (no `auth.*` keys).
- Switch to AR, verify labels are translated and direction/spacing are correct.
- Login and logout in both FR and AR.

Pass criteria:
- No i18n key leaks.
- No mojibake/corrupted text.

### A2. Password reset flow
- Trigger "mot de passe oublié".
- Confirm reset email is received.
- Click reset link from email.
- Verify reset screen appears (new password + confirm password), update password, then sign in.

Pass criteria:
- No blank page.
- Reset completes and new password works.

### A3. Seller create listing (8 steps)
- Login as seller.
- Complete steps 1..8 and publish.
- Verify listing appears in `Mes annonces` and browse list.

Pass criteria:
- Publish succeeds.
- No spinner stuck/error toast.
- No i18n key leaks during wizard.

### A4. Notifications FR/AR
- Open `Profil -> Notifications` in FR then AR.
- Verify all tabs, chips, labels, and row titles are translated.

Pass criteria:
- No `notifications.*` keys shown.

### A5. Shipping label flow
- Open `Mes ventes`.
- Generate bordereau for target order.
- Click `Ouvrir label`.

Pass criteria:
- Label opens/downloads with public URL (no internal host leakage).

## B) Local Automated Gates

Run from repo root:

```powershell
flutter test test/tmp_translation_test.dart test/add_listing_form_test.dart test/orders_page_test.dart test/status_labels_test.dart
flutter analyze lib/src/features/listings/add_listing_page.dart lib/src/features/listings/listings_page.dart lib/src/services/i18n.dart
```

Pass criteria:
- Tests: all passed.
- Analyze: no issues found.

## C) Web Build Sanity

```powershell
flutter build web --release --dart-define-from-file=test/test_env.json
```

Pass criteria:
- Build successful.
- `build/web/config.json` points to `https://api.dzmarket.pro`.

## D) Sign-off Template

- Date:
- Commit:
- Tester:
- A1 Auth FR/AR: PASS/FAIL
- A2 Reset password: PASS/FAIL
- A3 Seller listing: PASS/FAIL
- A4 Notifications FR/AR: PASS/FAIL
- A5 Label open: PASS/FAIL
- B Local tests/analyze: PASS/FAIL
- C Web build sanity: PASS/FAIL
- Blocking issues:
