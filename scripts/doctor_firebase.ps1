$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot

$paths = @(
  "android\app\src\dev\google-services.json",
  "android\app\src\staging\google-services.json",
  "android\app\src\prod\google-services.json",
  "web\config.json"
)

function Get-PlaceholderStatus {
  param([string]$Path)
  try {
    $raw = Get-Content -Raw -Path $Path
    $data = $raw | ConvertFrom-Json
    if ($Path -like "*web\\config.json") {
      foreach ($env in @("dev", "staging", "prod")) {
        if ($data.$env -and $data.$env.__PLACEHOLDER__ -eq $true) {
          return "PLACEHOLDER"
        }
      }
      return "OK"
    }
    if ($data.__PLACEHOLDER__ -eq $true) { return "PLACEHOLDER" }
    return "OK"
  } catch {
    return "OK"
  }
}

Write-Host "Checking Firebase files..."
$missing = $false
foreach ($rel in $paths) {
  $full = Join-Path $projectRoot $rel
  if (Test-Path $full) {
    $status = Get-PlaceholderStatus -Path $full
    Write-Host ("{0}: {1}" -f $status, $rel)
  } else {
    Write-Host "MISSING: $rel"
    $missing = $true
  }
}

Write-Host ""
Write-Host "Commands:"
Write-Host "flutter run --flavor dev -t lib/main.dart --dart-define=APP_ENV=dev"
Write-Host "flutter run --flavor staging -t lib/main.dart --dart-define=APP_ENV=staging"
Write-Host "flutter run --flavor prod -t lib/main.dart --dart-define=APP_ENV=prod"
Write-Host "flutter run -d chrome --dart-define=APP_ENV=dev"
Write-Host "flutter build web --dart-define=APP_ENV=prod"

if ($missing) { exit 1 }
