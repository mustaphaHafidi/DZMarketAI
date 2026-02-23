param(
  [string]$AppServerIp = "91.107.239.5",
  [string]$SshKeyPath = "$env:USERPROFILE\.ssh\dzmarket_hetzner",
  [int]$WindowMinutes = 5,
  [int]$SampleCount = 20,
  [double]$MaxHttpErrorRatePct = 1.0,
  [int]$MaxP95AppMs = 700,
  [int]$MaxP95ApiMs = 500,
  [int]$MaxP95AuthMs = 400,
  [int]$MaxP95StorageMs = 700,
  [double]$MaxDbActivePct = 75.0,
  [double]$MaxCaddy5xxRatePct = 1.0
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $SshKeyPath)) {
  throw "SSH key not found: $SshKeyPath"
}

$sshBin = "$env:WINDIR\System32\OpenSSH\ssh.exe"
if (-not (Test-Path $sshBin)) {
  $sshBin = "ssh"
}

function Invoke-Ssh {
  param([Parameter(Mandatory = $true)][string]$Command)
  & $sshBin -o BatchMode=yes -i $SshKeyPath -o IdentitiesOnly=yes "root@$AppServerIp" $Command
  if ($LASTEXITCODE -ne 0) {
    throw "SSH command failed: $Command"
  }
}

function Get-HttpSample {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter()][hashtable]$Headers = @{},
    [int]$Count = 20
  )

  $times = New-Object System.Collections.Generic.List[double]
  $codes = New-Object System.Collections.Generic.List[int]

  for ($i = 0; $i -lt $Count; $i++) {
    $args = @("-k", "-sS", "-o", "NUL", "-w", "%{http_code} %{time_total}")
    foreach ($kv in $Headers.GetEnumerator()) {
      $args += @("-H", "$($kv.Key): $($kv.Value)")
    }
    $args += $Url

    $out = & curl.exe @args
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($out)) {
      $codes.Add(0)
      $times.Add(9.999)
      continue
    }

    $parts = ($out -split "\s+", 2)
    $code = 0
    $time = 9.999
    [void][int]::TryParse($parts[0], [ref]$code)
    if ($parts.Count -ge 2) {
      [void][double]::TryParse($parts[1], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$time)
    }
    $codes.Add($code)
    $times.Add($time)
  }

  $sortedTimes = $times.ToArray() | Sort-Object
  $index = [Math]::Ceiling(0.95 * $sortedTimes.Length) - 1
  if ($index -lt 0) { $index = 0 }
  if ($index -ge $sortedTimes.Length) { $index = $sortedTimes.Length - 1 }

  $p95Ms = [Math]::Round($sortedTimes[$index] * 1000)
  $errorCount = ($codes | Where-Object { $_ -lt 200 -or $_ -ge 400 }).Count
  $errorPct = if ($codes.Count -eq 0) { 100.0 } else { [Math]::Round(($errorCount * 100.0) / $codes.Count, 2) }

  [PSCustomObject]@{
    Name       = $Name
    Url        = $Url
    SampleSize = $codes.Count
    P95Ms      = [int]$p95Ms
    ErrorPct   = $errorPct
    LastCode   = $codes[$codes.Count - 1]
  }
}

$remoteScript = @'
set -euo pipefail

WINDOW_MINUTES="${1:-5}"

ANON_KEY="$(sed -n 's/^ANON_KEY=//p' /opt/supabase/docker/.env | head -n 1 || true)"
if [ -n "$ANON_KEY" ]; then
  echo "ANON_KEY_PRESENT=1"
else
  echo "ANON_KEY_PRESENT=0"
fi

DB_METRICS="$(echo "select current_setting('max_connections')::int, count(*) filter (where state = 'active')::int, count(*)::int from pg_stat_activity;" | docker exec -i supabase-db psql -U postgres -d postgres -At)"
IFS='|' read -r DB_MAX DB_ACTIVE DB_TOTAL <<< "$DB_METRICS"
echo "DB_MAX=$DB_MAX"
echo "DB_ACTIVE=$DB_ACTIVE"
echo "DB_TOTAL=$DB_TOTAL"

UNHEALTHY="$(docker ps --format '{{.Status}}' | awk 'BEGIN{c=0} /unhealthy/{c++} END{print c}')"
echo "UNHEALTHY_CONTAINERS=$UNHEALTHY"

WINDOW="${WINDOW_MINUTES} minutes ago"
LOG_CHUNK="$(journalctl -u caddy --since "$WINDOW" --no-pager 2>/dev/null || true)"
CADDY_5XX="$( (printf '%s\n' "$LOG_CHUNK" | grep -Eo '"status":[[:space:]]*5[0-9]{2}|status=5[0-9]{2}' || true) | wc -l | tr -d ' ' )"
CADDY_TOTAL="$( (printf '%s\n' "$LOG_CHUNK" | grep -Eo '"status":[[:space:]]*[0-9]{3}|status=[0-9]{3}' || true) | wc -l | tr -d ' ' )"
echo "CADDY_5XX=$CADDY_5XX"
echo "CADDY_TOTAL=$CADDY_TOTAL"
'@

$tmpScript = [System.IO.Path]::GetTempFileName()
try {
  Set-Content -Path $tmpScript -Value $remoteScript -NoNewline -Encoding UTF8
  $remoteOut = Get-Content -Path $tmpScript -Raw | & $sshBin -o BatchMode=yes -i $SshKeyPath -o IdentitiesOnly=yes "root@$AppServerIp" "bash -s -- '$WindowMinutes'"
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to execute remote SLI collector."
  }
} finally {
  Remove-Item -Path $tmpScript -ErrorAction SilentlyContinue
}

$kv = @{}
foreach ($line in ($remoteOut -split "`r?`n")) {
  if ($line -match "^[A-Z0-9_]+=.*$") {
    $parts = $line -split "=", 2
    $kv[$parts[0]] = $parts[1]
  }
}

if (($kv["ANON_KEY_PRESENT"] -as [int]) -ne 1) {
  throw "ANON_KEY missing on server (/opt/supabase/docker/.env)"
}

$anonKey = (Invoke-Ssh "sed -n 's/^ANON_KEY=//p' /opt/supabase/docker/.env | head -n 1").Trim()
if ([string]::IsNullOrWhiteSpace($anonKey)) {
  throw "Failed to read ANON_KEY from server."
}

$httpChecks = @(
  Get-HttpSample -Name "app_home" -Url "https://app.dzmarket.pro/" -Count $SampleCount
  Get-HttpSample -Name "api_root" -Url "https://api.dzmarket.pro/" -Count $SampleCount
  Get-HttpSample -Name "auth_health" -Url "https://api.dzmarket.pro/auth/v1/health" -Headers @{ apikey = $anonKey } -Count $SampleCount
  Get-HttpSample -Name "storage_status" -Url "https://api.dzmarket.pro/storage/v1/status" -Headers @{ apikey = $anonKey } -Count $SampleCount
)

$dbMax = [double]($kv["DB_MAX"] -as [double])
$dbActive = [double]($kv["DB_ACTIVE"] -as [double])
$dbActivePct = if ($dbMax -le 0) { 100.0 } else { [Math]::Round(($dbActive * 100.0) / $dbMax, 2) }

$caddyTotal = [double]($kv["CADDY_TOTAL"] -as [double])
$caddy5xx = [double]($kv["CADDY_5XX"] -as [double])
$caddy5xxPct = if ($caddyTotal -le 0) { 0.0 } else { [Math]::Round(($caddy5xx * 100.0) / $caddyTotal, 2) }

$checks = New-Object System.Collections.Generic.List[Object]
foreach ($row in $httpChecks) {
  $maxP95 = switch ($row.Name) {
    "app_home" { $MaxP95AppMs }
    "api_root" { $MaxP95ApiMs }
    "auth_health" { $MaxP95AuthMs }
    "storage_status" { $MaxP95StorageMs }
    default { 700 }
  }
  $ok = ($row.ErrorPct -le $MaxHttpErrorRatePct) -and ($row.P95Ms -le $maxP95)
  $checks.Add([PSCustomObject]@{
    Check  = $row.Name
    Status = if ($ok) { "PASS" } else { "FAIL" }
    Detail = "p95=$($row.P95Ms)ms, errors=$($row.ErrorPct)%, lastCode=$($row.LastCode)"
  })
}

$checks.Add([PSCustomObject]@{
  Check  = "db_active_connections"
  Status = if ($dbActivePct -le $MaxDbActivePct) { "PASS" } else { "FAIL" }
  Detail = "active=$dbActive/$dbMax (${dbActivePct}%)"
})

$unhealthy = [int]($kv["UNHEALTHY_CONTAINERS"] -as [int])
$checks.Add([PSCustomObject]@{
  Check  = "containers_health"
  Status = if ($unhealthy -eq 0) { "PASS" } else { "FAIL" }
  Detail = "unhealthy_containers=$unhealthy"
})

$checks.Add([PSCustomObject]@{
  Check  = "caddy_5xx_rate"
  Status = if ($caddy5xxPct -le $MaxCaddy5xxRatePct) { "PASS" } else { "FAIL" }
  Detail = "5xx=$caddy5xx/$caddyTotal (${caddy5xxPct}%) in last ${WindowMinutes}m"
})

Write-Host ""
Write-Host "===== SLI Quick Check ====="
$checks | Format-Table -AutoSize

$hasFail = ($checks | Where-Object { $_.Status -eq "FAIL" }).Count -gt 0
if ($hasFail) {
  Write-Error "SLI quick check failed."
  exit 1
}

Write-Host "SLI quick check passed."
