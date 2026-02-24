param(
  [string]$AppServerIp = "91.107.239.5",
  [string]$SshKeyPath = "$env:USERPROFILE\.ssh\dzmarket_hetzner",
  [string]$TestEmail = "",
  [switch]$SendRecoveryTest
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $SshKeyPath)) {
  throw "SSH key not found: $SshKeyPath"
}

$sshBin = "$env:WINDIR\System32\OpenSSH\ssh.exe"
if (-not (Test-Path $sshBin)) {
  $sshBin = "ssh"
}

$sendRecovery = if ($SendRecoveryTest.IsPresent) { "true" } else { "false" }

$remoteScript = @'
set -euo pipefail

TEST_EMAIL="${1:-}"
SEND_RECOVERY="${2:-false}"

ok() { echo "[OK] $1"; }
ko() { echo "[KO] $1"; exit 1; }

check_http_200() {
  local name="$1"
  local url="$2"
  shift 2
  local out="/tmp/auth-smoke-${name}.out"
  local code
  code="$(curl -sS -o "$out" -w '%{http_code}' "$@" "$url" || true)"
  if [ "$code" != "200" ]; then
    echo "[$name] HTTP=$code"
    head -c 600 "$out" || true
    echo
    ko "$name failed"
  fi
  ok "$name HTTP 200"
}

cd /opt/supabase/docker || ko "Cannot access /opt/supabase/docker"

ANON_KEY="$(sed -n 's/^ANON_KEY=//p' .env | head -n 1)"
[ -n "$ANON_KEY" ] || ko "ANON_KEY missing in /opt/supabase/docker/.env"
ok "ANON_KEY loaded"

check_http_200 "app_home" "https://app.dzmarket.pro/"
check_http_200 "auth_health" "https://api.dzmarket.pro/auth/v1/health" -H "apikey: $ANON_KEY"
check_http_200 "storage_status" "https://api.dzmarket.pro/storage/v1/status" -H "apikey: $ANON_KEY"
check_http_200 "tpl_confirmation" "https://app.dzmarket.pro/auth-email/confirmation.html"
check_http_200 "tpl_recovery" "https://app.dzmarket.pro/auth-email/recovery.html"

AUTH_ENV="$(docker inspect supabase-auth --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null || true)"
echo "$AUTH_ENV" | grep -q '^GOTRUE_MAILER_TEMPLATES_CONFIRMATION=' || ko "GOTRUE_MAILER_TEMPLATES_CONFIRMATION missing"
echo "$AUTH_ENV" | grep -q '^GOTRUE_MAILER_TEMPLATES_RECOVERY=' || ko "GOTRUE_MAILER_TEMPLATES_RECOVERY missing"
echo "$AUTH_ENV" | grep -q '^GOTRUE_MAILER_SUBJECTS_CONFIRMATION=' || ko "GOTRUE_MAILER_SUBJECTS_CONFIRMATION missing"
echo "$AUTH_ENV" | grep -q '^GOTRUE_MAILER_SUBJECTS_RECOVERY=' || ko "GOTRUE_MAILER_SUBJECTS_RECOVERY missing"
ok "Auth mailer env vars present"

if docker logs --tail 400 supabase-auth 2>&1 | grep -Ei 'template_body_parse_error|unexpected "\\\\" in operand' >/dev/null; then
  ko "Template parse errors detected in supabase-auth logs"
fi
ok "No template parse errors in recent auth logs"

if [ "$SEND_RECOVERY" = "true" ]; then
  [ -n "$TEST_EMAIL" ] || ko "SendRecoveryTest=true but TestEmail is empty"
  RECOVER_OUT="/tmp/auth-smoke-recover.out"
  RECOVER_CODE="$(curl -sS -o "$RECOVER_OUT" -w '%{http_code}' -X POST \
    -H "apikey: $ANON_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\"}" \
    "https://api.dzmarket.pro/auth/v1/recover" || true)"
  if [ "$RECOVER_CODE" != "200" ]; then
    echo "[recover] HTTP=$RECOVER_CODE"
    head -c 600 "$RECOVER_OUT" || true
    echo
    ko "Recovery email API failed"
  fi
  ok "Recovery email API accepted for $TEST_EMAIL"
fi

echo "[DONE] Auth smoke check passed."
'@

$encodedScript = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript))
$remoteCommand = "echo '$encodedScript' | base64 -d | bash -s -- '$TestEmail' '$sendRecovery'"

Write-Host "Running auth smoke check on root@$AppServerIp ..."
$sshOut = & $sshBin -o BatchMode=yes -i $SshKeyPath -o IdentitiesOnly=yes "root@$AppServerIp" $remoteCommand 2>&1
if ($sshOut) {
  $sshOut | Write-Output
}

if ($LASTEXITCODE -ne 0) {
  throw "Auth smoke check failed."
}

Write-Host "Auth smoke check completed successfully."
