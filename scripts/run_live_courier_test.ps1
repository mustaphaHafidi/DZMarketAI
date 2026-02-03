$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $projectRoot 'test\test_env.json'
$selectionKey = 'TEST_SHIPMENT_SELECTION_JSON'

if (-not (Test-Path $envFile)) {
  throw "Missing env file: $envFile"
}

Write-Host "Using env file: $envFile"

$raw = Get-Content -Raw -Path $envFile
try {
  $envData = $raw | ConvertFrom-Json
} catch {
  throw "Invalid JSON in $envFile. Ensure it is a valid JSON object."
}

$required = @(
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'TEST_USER_EMAIL',
  'TEST_USER_PASSWORD',
  'TEST_COURIER_NAME',
  'TEST_COURIER_API_KEY',
  'TEST_COURIER_CREATE_PARCEL'
)

foreach ($key in $required) {
  if (-not $envData.$key) {
    throw "Missing required key: $key"
  }
}

if (-not $envData.$selectionKey) {
  throw "Missing required key: $selectionKey"
}

if ($envData.TEST_COURIER_CREATE_PARCEL -ne "true") {
  Write-Warning "TEST_COURIER_CREATE_PARCEL is not 'true'; the live test will likely skip."
}

$hasSeller = ($envData.TEST_SELLER_USER_EMAIL -and $envData.TEST_SELLER_USER_PASSWORD) -or
  ($envData.TEST_OTHER_USER_EMAIL -and $envData.TEST_OTHER_USER_PASSWORD)
if (-not $hasSeller) {
  throw "Missing seller creds: TEST_SELLER_USER_EMAIL/TEST_SELLER_USER_PASSWORD (or TEST_OTHER_*)"
}

if (-not $envData.TEST_PRODUCT_ID -and -not $envData.TEST_ORDER_ID) {
  throw "Missing TEST_PRODUCT_ID or TEST_ORDER_ID"
}

Write-Host "Env OK. Running live courier test..."
Push-Location $projectRoot
try {
  flutter test integration_test/courier_flow_test.dart --plain-name "Couriers: create parcel + label (live)" -d emulator-5556 --dart-define-from-file test\test_env.json
} finally {
  Pop-Location
}
