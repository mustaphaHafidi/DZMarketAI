# PC2 Mobile Deploy

Use this when a second PC or agent prepares a DZMarket mobile release.

## Strict PC2 Contract

PC2 must treat mobile deployment as a production operation:

- Do not deploy from a dirty worktree. Run `git status --short --branch` first.
- Do not deploy from a local-only commit. Push the exact commit before store upload.
- Do not upgrade Flutter, Xcode, Gradle, Android Gradle Plugin, or Kotlin during a hotfix.
- Do not change app ids, bundle ids, signing files, Firebase projects, or Supabase URLs.
- Do not build production Android with plain `flutter build appbundle`.
- Do not pass `test/test_env.json` directly to Flutter production builds.
- Do not print secret values, raw plist content, service account JSON, `.p8`, `.p12`, or dart-defines.
- Stop if a required secret/file is missing. Report the missing name only.

The only approved Android production build entrypoint on PC2 is
`.\scripts\build_android_prod.ps1`.

## Golden Rule

Never build Android or iOS without production dart defines. A build without
`SUPABASE_URL` and `SUPABASE_ANON_KEY` starts with the bootstrap error
`Configuration manquante`.

Do not upgrade release tooling during a store hotfix unless the release task
explicitly requires it. Tooling-only upgrades must be tested separately.

## Android From Windows

1. Pull the latest repository state.
2. Verify the worktree is clean:

```powershell
git status --short --branch
```

3. Verify `test/test_env.json` exists locally and is not committed.
4. Verify these keys are present, without printing values:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `GOOGLE_WEB_CLIENT_ID`
5. Increment the build number only. Keep the marketing version unless requested.
6. Run checks:

```powershell
dart analyze
flutter test
```

7. Build with the guarded script:

```powershell
.\scripts\build_android_prod.ps1
```

The script creates and clears a temporary whitelisted dart-define file under
`build/`, excluding test users, test passwords, courier test secrets, and other
fixtures.

8. Upload the generated AAB with the Play service account JSON stored outside
   the repo:

```powershell
python .\tools\upload_play_bundle.py `
  --package-name com.dzmarket.app `
  --aab .\build\app\outputs\bundle\prodRelease\app-prod-release.aab `
  --service-account-json C:\Users\ssloc\Secrets\dzmarket-play-service-account.json `
  --track production `
  --status completed
```

If Python Google libraries are missing, install them locally:

```powershell
python -m pip install --user google-api-python-client google-auth
```

9. Verify Google Play reports the new version code on the intended track before
   telling the user Android is deployed.

## iOS From Codemagic

1. Do not try to build the final App Store IPA locally on Windows.
2. Keep the same marketing version as Android unless App Store requires more.
3. Increment `APP_BUILD_NUMBER` in `codemagic.yaml`.
4. Commit and push the exact source state.
5. Confirm Codemagic group `dzmarket_secrets` has non-empty values for:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `FIREBASE_IOS_PLIST_BASE64`
   - `GOOGLE_WEB_CLIENT_ID`
   - `GOOGLE_IOS_CLIENT_ID`
6. Confirm iOS signing still has Push Notifications entitlement and a valid
   App Store provisioning profile.
7. Start workflow `DZMarket iOS TestFlight` from `main`.
8. Wait for Codemagic upload to finish, then verify the build in TestFlight.

If triggering through Codemagic API, store the token in a local environment
variable and never paste it in logs or docs:

```powershell
$headers = @{ "x-auth-token" = $env:CODEMAGIC_API_TOKEN }
$body = @{
  appId = "<CODEMAGIC_APP_ID>"
  workflowId = "ios-testflight"
  branch = "main"
} | ConvertTo-Json
Invoke-RestMethod -Method Post `
  -Uri "https://api.codemagic.io/builds" `
  -Headers $headers `
  -ContentType "application/json" `
  -Body $body
```

## Required Secrets Checklist

Check presence only, never values:

- Android Play service account JSON outside the repo.
- Android keystore and `key.properties` outside commits unless already ignored.
- `test/test_env.json` local-only source for production-safe whitelisted values.
- Codemagic API token local-only if API triggering is needed.
- App Store Connect integration already configured in Codemagic.
- Firebase iOS plist base64 stored in Codemagic, not committed.

## Go / No-Go

GO only when all are true:

- `dart analyze` passes.
- `flutter test` passes.
- Android was built with `.\scripts\build_android_prod.ps1`.
- Play upload confirms the expected new version code.
- Codemagic validation, signing, IPA build, and publishing steps succeed.
- Android or iOS opens past bootstrap after install/update.

NO-GO if any are true:

- `Configuration manquante` appears on Android or iOS.
- A required env var or signing file is missing.
- Store rejects a reused version code/build number.
- PC2 changed tooling versions during the release.
- Raw secrets appeared in logs. Rotate exposed secrets before continuing.

## Manual Smoke Test

After Android install/update, verify the app opens past bootstrap. Then test:

- Google login.
- Home listing load.
- Contact seller with an actual message.
- Order with delivery choice.
- Chat room and automatic order message.
- Push notification on Android and iOS physical devices.

If any smoke test fails, stop release rollout and document the exact build
number, device, and failing action.
