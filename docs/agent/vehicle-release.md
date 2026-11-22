# Vehicle Release Gate

Use this gate for every change touching `vehicles` or `vehicles-*`.

## Product boundary

- A vehicle is a direct seller-to-buyer transaction: no courier, COD,
  parcel dimensions, stock, insurance or exchange-after-delivery controls.
- Required fields are brand and model. Year, mileage, fuel, gearbox, body,
  engine and horsepower stay optional.
- A vehicle may expose one optional contact number stored on the listing, never
  copied from the seller profile. Accept only Algerian mobile formats
  `05`/`06`/`07` or `+213`; display it in the listing contact block with chat
  and call actions.
- Do not collect registration, VIN, plate number or identity documents.
- Browse filters are hierarchical: a root category, then an optional
  sub-category. Vehicle-only fields appear only for `vehicles` selections;
  generic size, courier and delivery filters must stay hidden there.

## Required proof before release

1. Additive migration only. Never edit a migration already applied in
   production. Apply the new migration and verify the columns exist.
2. Run `flutter analyze --no-pub`, the full Flutter suite and vehicle-specific
   model/form tests.
3. On an authorized Android USB device, create a vehicle draft and verify:
   the vehicle details appear; parcel/delivery controls do not; FR and AR
   labels are readable; the listing detail has no stock chip.
4. On web, repeat the same creation and detail checks at mobile and desktop
   widths, then test the vehicle model/body/year/mileage/fuel/gearbox filters
   and the fixed action bar in the filter sheet.
5. Keep Android/iOS release builds and store uploads separate from the web
   deploy. Stop immediately if any gate fails; retain the current production
   release and one rollback.

No agent may call a deployment "finished" from a successful build alone.
