# QA And Regression Notes

Read this before changing code or preparing a release.

## Baseline

- Keep changes narrow.
- Check dirty worktree first.
- Do not revert unrelated user changes.
- Use targeted tests for the touched area, then broader tests when preparing release.

## Common Commands

```powershell
git status --short
dart analyze
flutter test
```

Use `--no-test-assets` only for pure targeted unit tests that do not load app
assets. Do not use it as the global release gate because several UI and i18n
tests require the Flutter asset manifest.

Targeted examples:

```powershell
flutter test test\push_notification_service_test.dart --no-test-assets
flutter test test\auth_service_redirect_test.dart --no-test-assets
flutter test test\app_error_service_test.dart --no-test-assets
```

## Manual Mobile Checks

- Android USB: install/run intended flavor and verify login, browse, chat, order, push.
- Vehicle release: select `Vehicules`, confirm the subtype picker is shown,
  check generic parcel/delivery and size filters are absent, then apply and
  reset price plus vehicle filters in both French and Arabic.
- Vehicle edit: open one owned vehicle listing, change model or mileage, save
  and reopen it. Confirm its technical values persist and that parcel,
  delivery, stock and insurance controls are absent. Repeat a small standard
  listing edit to confirm its parcel controls remain unchanged.
- Browse grid: on a narrow Android phone, confirm two-column cards show title
  and location without a Flutter `BOTTOM OVERFLOW`; delivery badges must not
  render in that compact card variant.
- Admin moderation: confirm the exact global profile count is shown, first
  page loads promptly, search/status resets the list, and another page loads
  only after scrolling. Never load every profile before first render.
- Support social: on Browse only, open and close the icon menu, verify its
  opposite placement from the sell button in FR and Arabic RTL, then open one
  official external link. It must not appear on Chat, Profile, listing form,
  checkout, or tracking.
- iOS TestFlight: verify exact version/build, Google sign-in, push permission, background push, chat/order flows.
- For push, test app in background or locked state; foreground behavior can differ.

## Release Gate

Before store submission:

- tests pass or skipped tests are explained
- correct build number selected
- Firebase native config present
- APNs key configured for iOS production push
- Play/App Store status checked externally
