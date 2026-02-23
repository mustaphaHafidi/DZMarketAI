param(
  [ValidateSet("baseline", "step", "spike", "soak")]
  [string]$Phase = "baseline",
  [ValidateSet("listings", "auth", "orders", "shipments")]
  [string]$Scenario = "listings",
  [string]$BaseUrl = "https://api.dzmarket.pro",
  [string]$AnonKey = "",
  [int]$Vus = 0,
  [string]$Duration = "",
  [string]$EnvFile = "",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot

try {
  $scriptPath = "load/$Scenario.js"
  if (-not (Test-Path $scriptPath)) {
    throw "Scenario script not found: $scriptPath"
  }

  $phaseConfig = switch ($Phase) {
    "baseline" { @{ VUS = "200"; DURATION = "30m" } }
    "step"     { @{ VUS = "300"; DURATION = "60m" } }
    "spike"    { @{ VUS = "900"; DURATION = "15m" } }
    "soak"     { @{ VUS = "450"; DURATION = "8h" } }
  }
  if ($Vus -gt 0) {
    $phaseConfig["VUS"] = [string]$Vus
  }
  if (-not [string]::IsNullOrWhiteSpace($Duration)) {
    $phaseConfig["DURATION"] = $Duration
  }

  $envMap = [ordered]@{}

  if (-not [string]::IsNullOrWhiteSpace($EnvFile)) {
    if (-not (Test-Path $EnvFile)) {
      throw "Env file not found: $EnvFile"
    }
    $envLines = Get-Content $EnvFile | Where-Object {
      $_ -and ($_ -notmatch "^\s*#") -and ($_ -match "=")
    }
    foreach ($line in $envLines) {
      $pair = $line.Trim() -split "=", 2
      $envMap[$pair[0]] = $pair[1]
    }
  }

  $envMap["BASE_URL"] = $BaseUrl
  if (-not [string]::IsNullOrWhiteSpace($AnonKey)) {
    $envMap["ANON_KEY"] = $AnonKey
  }
  foreach ($k in $phaseConfig.Keys) {
    $envMap[$k] = $phaseConfig[$k]
  }

  $anonCandidate = if ($envMap.Contains("ANON_KEY")) { "$($envMap["ANON_KEY"])" } else { "" }
  if ([string]::IsNullOrWhiteSpace($anonCandidate) -or
      $anonCandidate -in @("replace_me", "TON_ANON_KEY", "<ANON_KEY>")) {
    throw "ANON_KEY missing/placeholder. Pass -AnonKey <real_key> or set ANON_KEY in -EnvFile."
  }

  $args = @("run", $scriptPath)
  $previewArgs = @("run", $scriptPath)
  $redactedKeys = @("ANON_KEY", "TEST_PASSWORD", "TEST_USERS_JSON", "TEST_BUYER_JWT", "TEST_SELLER_JWT", "TEST_LABEL_URL")
  foreach ($entry in $envMap.GetEnumerator()) {
    $args += @("-e", "$($entry.Key)=$($entry.Value)")
    $previewValue = if ($entry.Key -in $redactedKeys) { "<redacted>" } else { "$($entry.Value)" }
    $previewArgs += @("-e", "$($entry.Key)=$previewValue")
  }

  $cmdText = "k6 " + ($previewArgs -join " ")
  Write-Host "Running: $cmdText"

  if ($DryRun.IsPresent) {
    exit 0
  }

  if (-not (Get-Command k6 -ErrorAction SilentlyContinue)) {
    throw "k6 is not installed. Install from https://k6.io/docs/get-started/installation/"
  }

  & k6 @args
  if ($LASTEXITCODE -ne 0) {
    throw "k6 run failed."
  }
}
finally {
  Pop-Location
}
