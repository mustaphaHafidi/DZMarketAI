param(
  [string]$Repo = "mustaphaHafidi/DZMarketAI",
  [string]$AppServerIp = "91.107.239.5",
  [string]$SshKeyPath = "$env:USERPROFILE\.ssh\dzmarket_hetzner",
  [string]$SupabaseUrl,
  [switch]$SkipGithubSecrets
)

$ErrorActionPreference = "Stop"

if (-not $SupabaseUrl) {
  $SupabaseUrl = "http://${AppServerIp}:8000"
}

if (-not (Test-Path $SshKeyPath)) {
  throw "SSH key not found: $SshKeyPath"
}

Write-Host "Step 1/4 - Read keys from dzm-app-01 .env"
$remoteCmd = "grep -E '^(ANON_KEY|SERVICE_ROLE_KEY)=' /opt/supabase/docker/.env"
$raw = & ssh -i $SshKeyPath -o IdentitiesOnly=yes "root@$AppServerIp" $remoteCmd

$anonLine = ($raw | Where-Object { $_ -like "ANON_KEY=*" } | Select-Object -First 1)
$serviceLine = ($raw | Where-Object { $_ -like "SERVICE_ROLE_KEY=*" } | Select-Object -First 1)

if (-not $anonLine -or -not $serviceLine) {
  throw "Could not read ANON_KEY/SERVICE_ROLE_KEY from remote .env"
}

$anonKey = $anonLine.Substring("ANON_KEY=".Length)
$serviceRoleKey = $serviceLine.Substring("SERVICE_ROLE_KEY=".Length)

Write-Host ("ANON_KEY prefix: {0} (len={1})" -f $anonKey.Substring(0, [Math]::Min(10, $anonKey.Length)), $anonKey.Length)
Write-Host ("SERVICE_ROLE_KEY prefix: {0} (len={1})" -f $serviceRoleKey.Substring(0, [Math]::Min(10, $serviceRoleKey.Length)), $serviceRoleKey.Length)

Write-Host "Step 2/4 - Write local test/test_env.json"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$testEnvPath = Join-Path $repoRoot "test\test_env.json"
$templatePath = Join-Path $repoRoot "test\test_env.example.json"

if (Test-Path $templatePath) {
  $json = Get-Content $templatePath -Raw | ConvertFrom-Json
} else {
  $json = [ordered]@{}
}

$json.SUPABASE_URL = $SupabaseUrl
$json.SUPABASE_ANON_KEY = $anonKey

$json | ConvertTo-Json -Depth 20 | Set-Content -Path $testEnvPath -Encoding UTF8
Write-Host "Updated $testEnvPath"

Write-Host "Step 3/4 - Optional: update GitHub Action secrets"
if (-not $SkipGithubSecrets) {
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if ($null -eq $gh) {
    Write-Warning "gh CLI not found. Skipping GitHub secrets update."
  } else {
    & gh secret set SUPABASE_URL --repo $Repo --body $SupabaseUrl
    & gh secret set SUPABASE_SERVICE_ROLE_KEY --repo $Repo --body $serviceRoleKey
    Write-Host "GitHub secrets updated for repo $Repo"
  }
} else {
  Write-Host "SkipGithubSecrets enabled."
}

Write-Host "Step 4/4 - Ready to run app against Hetzner"
Write-Host "USB run command:"
Write-Host "flutter run -d <DEVICE_ID> --flavor dev -t lib/main.dart --dart-define-from-file=test/test_env.json --no-resident"
Write-Host ""
Write-Host "Done."
