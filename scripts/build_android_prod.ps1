param(
  [string]$EnvJson = "test/test_env.json",
  [string]$BuildName = "",
  [string]$BuildNumber = "",
  [switch]$Clean
)

$ErrorActionPreference = "Stop"

function Get-PubspecVersion {
  $line = Select-String -Path "pubspec.yaml" -Pattern "^version:\s*(.+)$" | Select-Object -First 1
  if (-not $line) {
    throw "pubspec.yaml version is missing."
  }
  return $line.Matches[0].Groups[1].Value.Trim()
}

if (-not (Test-Path -LiteralPath $EnvJson)) {
  throw "Env JSON not found: $EnvJson"
}

if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
  $androidStudioJbr = "C:\Program Files\Android\Android Studio\jbr"
  if (Test-Path -LiteralPath (Join-Path $androidStudioJbr "bin\java.exe")) {
    $env:JAVA_HOME = $androidStudioJbr
  }
}

$source = Get-Content -Raw -LiteralPath $EnvJson | ConvertFrom-Json
$required = @("SUPABASE_URL", "SUPABASE_ANON_KEY", "GOOGLE_WEB_CLIENT_ID")
foreach ($key in $required) {
  $value = [string]$source.$key
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "$key is missing in $EnvJson"
  }
}

$version = Get-PubspecVersion
if ([string]::IsNullOrWhiteSpace($BuildName) -or [string]::IsNullOrWhiteSpace($BuildNumber)) {
  $parts = $version.Split("+", 2)
  if ([string]::IsNullOrWhiteSpace($BuildName)) {
    $BuildName = $parts[0]
  }
  if ([string]::IsNullOrWhiteSpace($BuildNumber)) {
    if ($parts.Count -lt 2 -or [string]::IsNullOrWhiteSpace($parts[1])) {
      throw "BuildNumber was not provided and pubspec.yaml has no +build suffix."
    }
    $BuildNumber = $parts[1]
  }
}

$definesDir = Join-Path "build" "release-dart-defines"
New-Item -ItemType Directory -Force -Path $definesDir | Out-Null
$definesPath = Join-Path $definesDir "android-prod.json"

$defines = [ordered]@{
  APP_FLAVOR = "prod"
  SUPABASE_URL = [string]$source.SUPABASE_URL
  SUPABASE_ANON_KEY = [string]$source.SUPABASE_ANON_KEY
  GOOGLE_WEB_CLIENT_ID = [string]$source.GOOGLE_WEB_CLIENT_ID
  ENABLE_ANALYTICS = "true"
  ENABLE_CRASHLYTICS = "true"
}

if ($source.PSObject.Properties.Name -contains "AUTH_REDIRECT_URL") {
  $authRedirectUrl = [string]$source.AUTH_REDIRECT_URL
  if (-not [string]::IsNullOrWhiteSpace($authRedirectUrl)) {
    $defines.AUTH_REDIRECT_URL = $authRedirectUrl
  }
}

$defines | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 -LiteralPath $definesPath

if ($Clean) {
  flutter clean
}

$env:GRADLE_OPTS = (($env:GRADLE_OPTS, "-Dkotlin.compiler.execution.strategy=in-process") -join " ").Trim()

flutter pub get

$logDir = Join-Path "build" "release-logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$rawLog = Join-Path $logDir "android-prod-build.raw.log"
$safeLog = Join-Path $logDir "android-prod-build.log"

$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
  & flutter build appbundle `
    --release `
    --flavor prod `
    -t lib/main.dart `
    --build-name $BuildName `
    --build-number $BuildNumber `
    --dart-define-from-file $definesPath *> $rawLog
  $buildExit = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $oldErrorActionPreference
}

$safeContent = Get-Content -Raw -LiteralPath $rawLog
$safeContent = $safeContent -replace "-Pdart-defines=.*?(?= -Pdart-obfuscation)", "-Pdart-defines=<redacted>"
$safeContent = $safeContent -replace "SUPABASE_URL=[^, `r`n]+", "SUPABASE_URL=<redacted>"
$safeContent = $safeContent -replace "SUPABASE_ANON_KEY=[^, `r`n]+", "SUPABASE_ANON_KEY=<redacted>"
$safeContent = $safeContent -replace "GOOGLE_WEB_CLIENT_ID=[^, `r`n]+", "GOOGLE_WEB_CLIENT_ID=<redacted>"
$safeContent | Set-Content -Encoding UTF8 -LiteralPath $safeLog
Remove-Item -LiteralPath $rawLog -Force -ErrorAction SilentlyContinue

if ($buildExit -ne 0) {
  Get-Content -LiteralPath $safeLog -Tail 80
  throw "Android build failed. See sanitized log: $safeLog"
}

$aab = "build/app/outputs/bundle/prodRelease/app-prod-release.aab"
if (-not (Test-Path -LiteralPath $aab)) {
  throw "AAB not generated: $aab"
}

Write-Host "AAB generated: $aab"
Write-Host "Build: $BuildName+$BuildNumber"
Write-Host "Sanitized build log: $safeLog"
