$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
  Write-Host "Running flutter analyze..."
  flutter analyze

  Write-Host "Running flutter test..."
  flutter test
} finally {
  Pop-Location
}
