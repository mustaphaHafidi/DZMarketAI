# PC2 Mobile Deploy

Use this when a second PC or agent prepares a DZMarket mobile release.

## Golden Rule

Never build Android or iOS without production dart defines. A build without
`SUPABASE_URL` and `SUPABASE_ANON_KEY` starts with the bootstrap error
`Configuration manquante`.

Do not upgrade Gradle, Android Gradle Plugin, or Kotlin during a store hotfix
unless the release task explicitly requires it. Tooling-only upgrades can make
Windows release builds slow or unstable and should be tested separately.

## Android From Windows

1. Pull the latest repository state.
2. Verify `test/test_env.json` exists locally and is not committed.
3. Verify these keys are present, without printing values:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `GOOGLE_WEB_CLIENT_ID`
4. Increment the build number in `pubspec.yaml`.
5. Build with the guarded script:

```powershell
.\scripts\build_android_prod.ps1
```

The script creates and clears a temporary whitelisted dart-define file under `build/`,
excluding test users, test passwords, courier test secrets, and other fixtures.

6. Upload the generated AAB with the Play service account JSON stored outside
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

## iOS From Codemagic

1. Keep the same marketing version as Android unless App Store requires more.
2. Increment `APP_BUILD_NUMBER` in `codemagic.yaml`.
3. Confirm Codemagic group `dzmarket_secrets` has non-empty values for:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `FIREBASE_IOS_PLIST_BASE64`
   - `GOOGLE_WEB_CLIENT_ID`
   - `GOOGLE_IOS_CLIENT_ID`
4. Start workflow `DZMarket iOS TestFlight` from `main`.
5. Wait for Codemagic upload to finish, then verify the build in TestFlight.

## Required Checks

Run before deployment:

```powershell
dart analyze
flutter test
```

After Android install/update, verify the app opens past bootstrap. If it shows
`Configuration manquante`, the AAB was built without the guarded script.
