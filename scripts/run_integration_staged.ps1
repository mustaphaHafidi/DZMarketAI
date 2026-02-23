param(
  [string]$DeviceId = '',
  [string]$Flavor = 'dev',
  [string]$EnvFile = 'test/test_env.json',
  [ValidateSet('smoke', 'core', 'orders', 'chat', 'courier-live', 'full')]
  [string]$Phase = 'smoke'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
  if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    throw "Missing -DeviceId. Example: .\scripts\run_integration_staged.ps1 -DeviceId R5CNC13Y7WN -Phase smoke"
  }

  if (-not (Test-Path $EnvFile)) {
    throw "Env file not found: $EnvFile"
  }

  $commonArgs = @(
    '-d', $DeviceId
  )

  $noFlavorDevices = @('windows', 'linux', 'chrome', 'edge', 'web-server')
  if ($noFlavorDevices -notcontains $DeviceId.ToLowerInvariant()) {
    $commonArgs += @('--flavor', $Flavor)
  }

  $commonArgs += @('--dart-define-from-file', $EnvFile)

  $phases = @{
    'smoke' = @(
      'integration_test/auth_flow_test.dart',
      'integration_test/security_state_test.dart',
      'integration_test/shipping_validation_zrexpress_test.dart'
    )
    'core' = @(
      'integration_test/router_refresh_test.dart',
      'integration_test/order_system_messages_test.dart',
      'integration_test/chat_v2_test.dart'
    )
    'orders' = @(
      'integration_test/order_delivery_flow_test.dart'
    )
    'chat' = @(
      'integration_test/chat_flow_test.dart'
    )
    'courier-live' = @(
      'integration_test/courier_flow_test.dart'
    )
    'full' = @(
      'integration_test/auth_flow_test.dart',
      'integration_test/security_state_test.dart',
      'integration_test/shipping_validation_zrexpress_test.dart',
      'integration_test/router_refresh_test.dart',
      'integration_test/order_system_messages_test.dart',
      'integration_test/chat_v2_test.dart',
      'integration_test/order_delivery_flow_test.dart',
      'integration_test/chat_flow_test.dart'
    )
  }

  $selected = $phases[$Phase]
  if (-not $selected -or $selected.Count -eq 0) {
    throw "No tests configured for phase: $Phase"
  }

  Write-Host "Running integration phase '$Phase' on device '$DeviceId' (flavor=$Flavor)..."
  $results = @()

  foreach ($testFile in $selected) {
    Write-Host ""
    Write-Host ">> $testFile"
    & flutter test $testFile @commonArgs
    $exitCode = $LASTEXITCODE
    $results += [PSCustomObject]@{
      TestFile = $testFile
      ExitCode = $exitCode
    }
    if ($exitCode -ne 0) {
      Write-Host ""
      Write-Host "Stopped on first failure in phase '$Phase'."
      break
    }
  }

  Write-Host ""
  Write-Host "Summary:"
  $results | Format-Table -AutoSize

  $failed = $results | Where-Object { $_.ExitCode -ne 0 }
  if ($failed) {
    exit 1
  }
} finally {
  Pop-Location
}
