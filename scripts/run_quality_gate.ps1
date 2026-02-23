param(
  [string]$Flavor = "dev",
  [string]$EnvFile = "test/test_env.json",
  [string[]]$UnitTests = @(
    "test/tmp_translation_test.dart",
    "test/add_listing_form_test.dart",
    "test/orders_page_test.dart",
    "test/status_labels_test.dart"
  ),
  [string[]]$AnalyzeTargets = @(
    "lib/src/features/listings/add_listing_page.dart",
    "lib/src/features/listings/listings_page.dart",
    "lib/src/services/i18n.dart"
  ),
  [switch]$RunIntegration,
  [ValidateSet("smoke", "core", "orders", "chat", "courier-live", "full")]
  [string]$IntegrationPhase = "smoke",
  [string]$DeviceId = "",
  [switch]$RunAuthSmoke,
  [string]$AuthSmokeTestEmail = "",
  [string]$AppServerIp = "91.107.239.5",
  [string]$SshKeyPath = "$env:USERPROFILE\.ssh\dzmarket_hetzner"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot

$results = New-Object System.Collections.Generic.List[Object]
$hasFailure = $false

function Invoke-Step {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Action
  )

  Write-Host ""
  Write-Host "==> $Name"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $status = "PASS"
  $details = ""

  try {
    & $Action
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
      throw "Exit code $LASTEXITCODE"
    }
  } catch {
    $status = "FAIL"
    $details = $_.Exception.Message
    $script:hasFailure = $true
  } finally {
    $sw.Stop()
    $results.Add([PSCustomObject]@{
      Step      = $Name
      Status    = $status
      DurationS = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
      Details   = $details
    })
  }
}

try {
  Invoke-Step -Name "Flutter tests" -Action {
    & flutter test @UnitTests
  }

  Invoke-Step -Name "Flutter analyze" -Action {
    & flutter analyze @AnalyzeTargets
  }

  if ($RunIntegration.IsPresent) {
    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
      throw "RunIntegration requires -DeviceId"
    }
    Invoke-Step -Name "Integration phase: $IntegrationPhase" -Action {
      & "$PSScriptRoot\run_integration_staged.ps1" `
        -DeviceId $DeviceId `
        -Phase $IntegrationPhase `
        -Flavor $Flavor `
        -EnvFile $EnvFile
    }
  }

  if ($RunAuthSmoke.IsPresent) {
    Invoke-Step -Name "Auth/API smoke (remote)" -Action {
      $smokeArgs = @(
        "-AppServerIp", $AppServerIp,
        "-SshKeyPath", $SshKeyPath
      )
      if (-not [string]::IsNullOrWhiteSpace($AuthSmokeTestEmail)) {
        $smokeArgs += @("-TestEmail", $AuthSmokeTestEmail, "-SendRecoveryTest")
      }
      & "$PSScriptRoot\auth_smoke_check.ps1" @smokeArgs
    }
  }
}
finally {
  Pop-Location
}

Write-Host ""
Write-Host "===== Quality Gate Summary ====="
$results | Format-Table -AutoSize

if ($hasFailure) {
  Write-Error "Quality gate failed."
  exit 1
}

Write-Host "Quality gate passed."
