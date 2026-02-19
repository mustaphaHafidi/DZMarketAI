# UI UX Release Checklist

Owner: Product + QA + Dev  
Scope: Flutter app pages  
Mode: UI/UX quality only (no business logic change)

## How to use

- Use this checklist before each release.
- Validate on real Android device and low network conditions.
- Mark each item `[x]` only after manual verification.

## Global checks (all pages)

- [ ] Loading state is clear and clean.
- [ ] Empty state has useful text + action.
- [ ] Error state has user-friendly message + Retry.
- [ ] No raw technical error text shown to end user.
- [ ] Buttons are consistent (size, radius, style).
- [ ] Spacing and alignment are visually consistent.
- [ ] Safe-area is respected (no hidden CTA behind system nav bar).
- [ ] Offline mode is graceful and understandable.

## Auth pages

### `lib/src/features/auth/sign_in_page.dart`
- [ ] Form validation is immediate and clear.
- [ ] Primary CTA disabled when form invalid.
- [ ] Reset password action is visible.
- [ ] No double-submit behavior.

### `lib/src/features/auth/sign_up_page.dart`
- [ ] Field labels and helper texts are clear.
- [ ] Validation messages are actionable.
- [ ] Success feedback after signup is explicit.
- [ ] Terms/Legal access is easy.

### `lib/src/features/auth/reset_password_page.dart`
- [ ] Flow is short and focused.
- [ ] Success state is clear.
- [ ] Error text is not technical.
- [ ] Return to login path is obvious.

## Browse and listing pages

### `lib/src/features/listings/listings_page.dart`
- [ ] Search is always visible.
- [ ] Filters are easy to reset.
- [ ] Product cards are visually consistent.
- [ ] List remains smooth on low-end devices.

### `lib/src/features/listings/product_detail_page.dart`
- [ ] Gallery supports swipe + fullscreen zoom.
- [ ] Header actions remain visible on all image colors.
- [ ] Price/stock/availability are visible quickly.
- [ ] Bottom CTAs are clear and stable.

### `lib/src/features/listings/add_listing_page.dart`
- [ ] Step flow is clear and progressive.
- [ ] Image rules are enforced (min/max) with friendly messages.
- [ ] Category and delivery sections are easy to understand.
- [ ] Publish CTA is always visible and not blocked.

### `lib/src/features/profile/edit_product_page.dart`
- [ ] Existing values are correctly prefilled.
- [ ] Save feedback is immediate.
- [ ] Unsaved changes warning works.
- [ ] Validation messages are localized and clear.

### `lib/src/features/profile/my_listings_page.dart`
- [ ] Active/archive/stock statuses are obvious.
- [ ] Quick actions are accessible.
- [ ] Long lists remain performant.
- [ ] Empty state proposes next action.

## Chat pages

### `lib/src/features/chat/chat_hub_page.dart`
- [ ] Conversation list shows unread + last message + time.
- [ ] Search/filter in chat list is responsive.
- [ ] Offline state is user-friendly.
- [ ] Navigation to room is instant and stable.

### `lib/src/features/chat/chat_room_page.dart`
- [ ] Composer and keyboard behavior are stable.
- [ ] Offer cards are clean and not duplicated visually.
- [ ] Action buttons (accept/refuse/counter) are clear.
- [ ] System messages are distinguishable from user messages.

### `lib/src/features/chat/order_chat_gate_page.dart`
- [ ] Redirect to correct room is reliable.
- [ ] Permission errors are user-friendly.
- [ ] No visual flicker during gate loading.
- [ ] Back navigation works correctly.

## Orders and fulfillment pages

### `lib/src/features/orders/orders_page.dart`
- [ ] Order status is prominent and understandable.
- [ ] Allowed actions match actual status.
- [ ] Price/shipping/total are clear.
- [ ] Chat/track shortcuts are easy.

### `lib/src/features/orders/seller_orders_page.dart`
- [ ] No ghost orders from offer-only actions.
- [ ] Arranged delivery vs label flow is visually clear.
- [ ] Card actions are context-aware.
- [ ] Return-risk warning is visible but non-intrusive.

### `lib/src/features/orders/fulfillment_page.dart`
- [ ] Buyer-chosen courier is clearly shown.
- [ ] Required fields are validated early.
- [ ] API failure messages are translated to user language.
- [ ] Success state shows tracking + label access.

### `lib/src/features/orders/shipments_dashboard_page.dart`
- [ ] Critical KPIs are visible at top.
- [ ] Filters are practical (status/courier/date).
- [ ] Row actions are easy and safe.
- [ ] Table/list remains readable on mobile.

## Profile pages

### `lib/src/features/profile/profile_page.dart`
- [ ] Sections are grouped logically (account/sales/delivery/security).
- [ ] Important actions are easy to find.
- [ ] Sensitive actions have confirmation dialogs.
- [ ] Offline and error states are polished.

### `lib/src/features/profile/public_profile_page.dart`
- [ ] Trust signals are clear (rating, activity, etc.).
- [ ] Contact CTA is obvious.
- [ ] Private data remains protected.
- [ ] Layout remains clean on small screens.

### `lib/src/features/profile/courier_settings_page.dart`
- [ ] Credential status per courier is explicit.
- [ ] Validate/test action gives clear feedback.
- [ ] Error guidance is practical.
- [ ] Save/delete interactions are safe.

### `lib/src/features/profile/seller_dashboard_page.dart`
- [ ] 24h operational cards are readable.
- [ ] Urgent actions are prioritized.
- [ ] Work queue reflects actionable orders.
- [ ] Recent order quick filters are useful.

## Tracking and map page

### `lib/src/features/tracking/map_tracking_page.dart`
- [ ] Map state handles no-position scenario cleanly.
- [ ] Last update timestamp is visible.
- [ ] Track/chat/order navigation is easy.
- [ ] Rendering remains smooth.

## Admin pages

### `lib/src/features/admin/moderation_admin_page.dart`
- [ ] Moderation states are clear and filterable.
- [ ] Actions are explicit and auditable.
- [ ] Bulk operations are safe.
- [ ] No ambiguous status labels.

### `lib/src/features/admin/app_errors_page.dart`
- [ ] Errors are grouped by severity/date.
- [ ] Technical details are visible only for admin.
- [ ] Filters/search are practical.
- [ ] Handled vs open status is clear.

## Legal page

### `lib/src/features/legal/legal_page.dart`
- [ ] Content is readable on mobile.
- [ ] Last update date is shown.
- [ ] FR/AR texts are consistent.
- [ ] External links open correctly.

## Final pre-release gate

- [ ] End-to-end: buyer order COD + arranged delivery.
- [ ] End-to-end: offer -> accept/refuse/counter in single chat room.
- [ ] End-to-end: seller label generation for supported couriers.
- [ ] End-to-end: offline/online transition on Browse, Chat, Profile.
- [ ] No critical UI regressions on main user paths.

