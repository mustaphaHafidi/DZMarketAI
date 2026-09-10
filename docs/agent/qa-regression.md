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
- iOS TestFlight: verify exact version/build, Google sign-in, push permission, background push, chat/order flows.
- For push, test app in background or locked state; foreground behavior can differ.

## Release Gate

Before store submission:

- tests pass or skipped tests are explained
- correct build number selected
- Firebase native config present
- APNs key configured for iOS production push
- Play/App Store status checked externally
