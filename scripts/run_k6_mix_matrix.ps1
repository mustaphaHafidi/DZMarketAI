param(
  [string]$EnvFile = "load/env.local",
  [string]$ListingsVus = "200,210,220",
  [int]$AuthVus = 5,
  [string]$Duration = "30m",
  [switch]$RunSliCheck
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot

try {
  $runner = Join-Path $projectRoot "scripts/run_k6_phase.ps1"
  $sli = Join-Path $projectRoot "scripts/sli_quick_check.ps1"

  if (-not (Test-Path $runner)) {
    throw "Missing script: $runner"
  }
  if (-not (Test-Path $EnvFile)) {
    throw "Env file not found: $EnvFile"
  }

  $vusSteps = @()
  foreach ($item in ($ListingsVus -split ",")) {
    $trimmed = $item.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    $n = 0
    if (-not [int]::TryParse($trimmed, [ref]$n)) {
      throw "Invalid ListingsVus value: $trimmed"
    }
    $vusSteps += $n
  }

  if ($vusSteps.Count -eq 0) {
    throw "No valid listings VUs found."
  }

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $outDir = Join-Path $projectRoot "k6-results/mix-matrix-$stamp"
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null

  $rows = New-Object System.Collections.Generic.List[object]

  Write-Host "Running mix matrix:"
  Write-Host "  listings VUs: $($vusSteps -join ', ')"
  Write-Host "  auth VUs    : $AuthVus"
  Write-Host "  duration    : $Duration"
  Write-Host "  env file    : $EnvFile"
  Write-Host "  output dir  : $outDir"
  Write-Host ""

  foreach ($lv in $vusSteps) {
    Write-Host "=== Step listings=$lv auth=$AuthVus duration=$Duration ==="

    $listingsOut = Join-Path $outDir "listings-$lv-auth-$AuthVus.log"
    $authOut = Join-Path $outDir "auth-$lv-auth-$AuthVus.log"

    $commonArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner, "-EnvFile", $EnvFile, "-Duration", $Duration)

    $listingsJob = Start-Job -ScriptBlock {
      param($baseArgs, $logPath, $vus)
      $args = @($baseArgs + @("-Scenario", "listings", "-Vus", "$vus"))
      & powershell.exe @args *> $logPath
      [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        LogPath  = $logPath
      }
    } -ArgumentList @($commonArgs, $listingsOut, $lv)

    $authJob = Start-Job -ScriptBlock {
      param($baseArgs, $logPath, $vus)
      $args = @($baseArgs + @("-Scenario", "auth", "-Vus", "$vus"))
      & powershell.exe @args *> $logPath
      [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        LogPath  = $logPath
      }
    } -ArgumentList @($commonArgs, $authOut, $AuthVus)

    Wait-Job -Id $listingsJob.Id, $authJob.Id | Out-Null
    $listingsResult = Receive-Job -Id $listingsJob.Id
    $authResult = Receive-Job -Id $authJob.Id
    Remove-Job -Id $listingsJob.Id, $authJob.Id -Force | Out-Null

    $listingsExit = [int]$listingsResult.ExitCode
    $authExit = [int]$authResult.ExitCode

    $sliStatus = "SKIP"
    if ($RunSliCheck.IsPresent) {
      try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sli | Out-Null
        if ($LASTEXITCODE -eq 0) {
          $sliStatus = "PASS"
        } else {
          $sliStatus = "FAIL"
        }
      } catch {
        $sliStatus = "FAIL"
      }
    }

    $status = if ($listingsExit -eq 0 -and $authExit -eq 0 -and ($sliStatus -in @("PASS", "SKIP"))) { "PASS" } else { "FAIL" }

    $rows.Add([PSCustomObject]@{
      step          = "listings=$lv,auth=$AuthVus"
      listings_vus  = $lv
      auth_vus      = $AuthVus
      duration      = $Duration
      listings_exit = $listingsExit
      auth_exit     = $authExit
      sli_check     = $sliStatus
      status        = $status
      listings_out  = $listingsOut
      auth_out      = $authOut
    })

    Write-Host "Result step listings=$lv auth=$AuthVus => $status (listings=$listingsExit, auth=$authExit, sli=$sliStatus)"
    Write-Host ""
  }

  $summaryCsv = Join-Path $outDir "summary.csv"
  $rows | Export-Csv -Path $summaryCsv -NoTypeInformation -Encoding UTF8

  Write-Host "=== Matrix Summary ==="
  $rows | Select-Object step, listings_exit, auth_exit, sli_check, status | Format-Table -AutoSize
  Write-Host "Summary CSV: $summaryCsv"

  $hasFail = ($rows | Where-Object { $_.status -eq "FAIL" }).Count -gt 0
  if ($hasFail) {
    exit 1
  }
}
finally {
  Pop-Location
}
