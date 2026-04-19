# DZMarket - Handover PC2

Updated: 2026-04-18

## 1) Current status

### Web
- Production URL: `https://app.dzmarket.pro`
- Redirects:
  - `https://www.dzmarket.pro` -> `https://app.dzmarket.pro`
  - `https://dzmarket.pro` -> `https://app.dzmarket.pro`
- Bug identified in production:
  - AR/FR switch on `sign-in` and `sign-up` does **not** update the UI
  - localStorage changes, but the page stays in French
- Code fix already committed:
  - `e8c1be8 fix(auth): apply locale switch on web auth screens`
- Local clean web build was generated successfully from `origin/main`
- Production web is **not updated yet**
- Current deployment blocker:
  - SSH access to `root@91.107.239.5` from this PC fails with `Permission denied (publickey,password)`
  - the valid SSH key is on PC 2

### iOS
- Current version under review: `1.0.1`
- Current tested build: `1.0.1 (14)`
- Build `14` opens correctly on iPhone
- App Store Connect status:
  - `Waiting for Review`
- Apple review package already provided:
  - review notes
  - buyer/seller credentials
  - screen recording from physical iPhone
- Do **not** change the current iOS submission unless Apple replies again or you explicitly decide to remove it from review

### Android
- Public production is still blocked by Google Play rules
- Required before production access:
  - at least `12 testers opted-in`
  - `14 days` of continuous closed testing
- Current closed testing issue:
  - not enough testers yet

## 2) Latest important commits

- `e8c1be8` - `fix(auth): apply locale switch on web auth screens`
- `9cae45b` - `fix(ios): fail fast on missing Codemagic env`
- `6a053dc` - `fix(ios): add privacy purpose strings for TestFlight`
- `3ab5280` - `ci(codemagic): fetch signing files for iOS export`

## 3) Repo state

Current worktree is **dirty**.

Uncommitted changes exist in:
- docs
- i18n assets
- `lib/src/services/i18n.dart`
- PDFs
- `automation/`
- `marketing/`
- `tools/generate_play_store_assets.py`

Before switching machine:
- either commit/push what must be kept
- or copy these local files manually to PC 2

Do not assume `git clone` on PC 2 will contain all current local work.

## 4) Web fix details

Files already changed in code for the auth locale bug:
- `lib/src/services/locale_service.dart`
- `lib/src/features/auth/sign_in_page.dart`
- `lib/src/features/auth/sign_up_page.dart`

Expected result after deployment:
- `sign-in` switches correctly between FR and AR
- `sign-up` switches correctly between FR and AR
- Arabic view becomes RTL

## 5) Web deployment from PC 2

### Prerequisites
- repo available on PC 2
- Flutter installed
- valid SSH private key on PC 2 for server `91.107.239.5`

### Recommended deploy commands
```powershell
cd C:\src\IA\dzmarket
git pull
flutter clean
flutter pub get
flutter build web --release --dart-define-from-file=test/test_env.json
powershell -NoProfile -Command "Compress-Archive -Path '.\build\web\*' -DestinationPath '.\dzmarket-web.zip' -Force"
scp -i "$env:USERPROFILE\.ssh\<BONNE_CLE_PRIVEE>" -o IdentitiesOnly=yes .\dzmarket-web.zip root@91.107.239.5:/tmp/dzmarket-web.zip
ssh -i "$env:USERPROFILE\.ssh\<BONNE_CLE_PRIVEE>" -o IdentitiesOnly=yes root@91.107.239.5 "rm -rf /var/www/dzmarket-web/* && unzip -oq /tmp/dzmarket-web.zip -d /var/www/dzmarket-web"
curl.exe -I https://app.dzmarket.pro
```

### Post-deploy checks
Test in browser:
- `https://www.dzmarket.pro/sign-in`
- `https://www.dzmarket.pro/sign-up`

Validation:
- click `Français`
- click `Arabe (Algérie)`
- verify texts change immediately
- verify Arabic is RTL

## 6) iOS operational notes

### Codemagic
- Workflow: `DZMarket iOS TestFlight`
- `codemagic.yaml` already imports:
  - `dzmarket_secrets`
- Required env vars:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`

### Current iOS review note context
- Buyer:
  - `test@gmail.com`
  - `2As369369`
- Seller:
  - `test2@gmail.com`
  - `2As369369`

### What to do now
- wait for Apple review response
- do not resubmit unless Apple answers or you choose to replace the build

## 7) Android next steps

1. Create/add at least `12` real testers in `Closed testing - Alpha`
2. Share tester link:
   - `https://play.google.com/apps/testing/com.dzmarket.app`
3. Testers must:
   - opt in
   - install the app
   - remain in the test for `14 days`
4. After that:
   - apply for production access in Play Console

## 8) Useful links

- Web app: `https://app.dzmarket.pro`
- Web root redirect: `https://www.dzmarket.pro`
- API: `https://api.dzmarket.pro`
- Android tester link: `https://play.google.com/apps/testing/com.dzmarket.app`
- Android store link: `https://play.google.com/store/apps/details?id=com.dzmarket.app`

## 9) Immediate priorities on PC 2

1. Restore full working repo on PC 2
2. Confirm valid SSH access to `91.107.239.5`
3. Deploy latest web build
4. Re-test AR/FR on auth pages in production
5. Continue waiting for Apple review
6. Recruit Android testers for closed testing
