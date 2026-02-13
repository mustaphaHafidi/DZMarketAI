# DZMarket Branding Usage

This project separates branding assets by purpose.

## UI (in-app screens)

- Use: `assets/branding/dzmarket_logo_ui.svg`
- Rule: no square background card in UI.
- Current usage:
  - `lib/src/features/auth/sign_in_page.dart`
  - `lib/src/features/auth/sign_up_page.dart`

## Communication visuals (marketing/social/slide)

- Use square-background logo variants from `logos/`:
  - `logos/Logo_DZM2.png` (left variant)
  - `logos/Logo_DZM1.png` (legacy square variant)

## Notes

- Keep communication logos out of app UI widgets.
- If a new UI logo is introduced, place it under `assets/branding/` and wire it from code.
