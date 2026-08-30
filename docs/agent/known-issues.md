# Known Issues And Cautions

Read this when investigating regressions or recent release bugs.

## Recent iOS Push Path

- iOS token registration was fixed by waiting for APNs token before FCM token and registering for remote notifications in `AppDelegate.swift`.
- If iOS token exists but delivery fails with `THIRD_PARTY_AUTH_ERROR`, check Firebase Console APNs production auth key.
- Android push can work while iOS push fails because APNs is a separate Apple/Firebase channel.

## Google Sign-In iOS

- iOS Google sign-in requires both iOS and web client IDs in Codemagic env vars.
- Supabase self-host Google provider may need provider-specific nonce handling depending on auth server version/config.
- Do not compare Android success as proof that iOS redirect/client config is correct.

## Chat And Orders

- Contact seller should create/open a conversation without creating empty unread message noise.
- Arranged delivery should create chat/system guidance, not decrement stock automatically unless a real order reserve/purchase flow requires it.
- Any stock mutation needs a test proving arranged delivery does not reserve or decrement unexpectedly.

## Documentation Drift

- Older docs from February-April are often stale after release work.
- Live code and production state win over `PROJECT_CONTEXT.md`, `NEXT_STEPS.md`, and `docs/HANDOVER_PC2.md`.
- Keep old docs only as archives or references, not as default agent context.

