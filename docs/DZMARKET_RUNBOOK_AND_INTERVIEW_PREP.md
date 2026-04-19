# DZMarket - Runbook Ops + Interview Prep

Version: 2026-03-03
Audience: owner + equipe ops/dev

## 1) Infra production

### 1.1 Serveurs Hetzner
- `dzm-app-01` (`91.107.239.5`): Caddy + Supabase stack
- `dzm-db-01` (`46.225.88.249`): PostgreSQL dedie
- `dzm-storage-01` (`91.98.227.237`): MinIO/S3

### 1.2 Domaines
- `app.dzmarket.pro` -> frontend web
- `api.dzmarket.pro` -> Supabase/Kong
- `www.dzmarket.pro` -> redirect vers `app.dzmarket.pro`
- `dzmarket.pro` -> redirect vers `app.dzmarket.pro`

## 2) Commandes essentielles

### 2.1 SSH (PowerShell)
```powershell
$key = "$env:USERPROFILE\.ssh\dzmarket_hetzner"
ssh -i $key -o IdentitiesOnly=yes root@91.107.239.5 "echo ok; hostname"
```

### 2.2 Etat stack
```bash
cd /opt/supabase/docker
docker compose -f docker-compose.yml -f docker-compose.s3.yml ps
```

### 2.3 Health web/api
```bash
curl -I https://app.dzmarket.pro
curl -I https://api.dzmarket.pro
```

## 3) Deploy web

### Build + zip local
```powershell
flutter build web --release --dart-define-from-file=test/test_env.json
powershell -NoProfile -Command "Compress-Archive -Path '.\\build\\web\\*' -DestinationPath '.\\dzmarket-web.zip' -Force"
```

### Upload + extract serveur
```cmd
scp -i "%USERPROFILE%\.ssh\dzmarket_hetzner" -o IdentitiesOnly=yes .\dzmarket-web.zip root@91.107.239.5:/tmp/dzmarket-web.zip
ssh -i "%USERPROFILE%\.ssh\dzmarket_hetzner" -o IdentitiesOnly=yes root@91.107.239.5 "rm -rf /var/www/dzmarket-web/* && unzip -oq /tmp/dzmarket-web.zip -d /var/www/dzmarket-web"
curl.exe -I https://app.dzmarket.pro
```

## 4) Deploy Edge Function (ex: job-runner)
```cmd
scp -i "%USERPROFILE%\.ssh\dzmarket_hetzner" -o IdentitiesOnly=yes .\supabase\functions\job-runner\index.ts root@91.107.239.5:/tmp/job-runner.index.ts
ssh -i "%USERPROFILE%\.ssh\dzmarket_hetzner" -o IdentitiesOnly=yes root@91.107.239.5 "mkdir -p /opt/supabase/docker/volumes/functions/job-runner && cp /tmp/job-runner.index.ts /opt/supabase/docker/volumes/functions/job-runner/index.ts && cd /opt/supabase/docker && docker compose -f docker-compose.yml -f docker-compose.s3.yml up -d --force-recreate functions"
```

## 5) Smoke scripts (obligatoires)

### SLI
```powershell
.\scripts\sli_quick_check.ps1 -WindowMinutes 10 -SampleCount 30 -SshKeyPath "$env:USERPROFILE\.ssh\dzmarket_hetzner"
```

### Auth/API/templates
```powershell
.\scripts\auth_smoke_check.ps1 -AppServerIp 91.107.239.5 -SshKeyPath "$env:USERPROFILE\.ssh\dzmarket_hetzner"
```

Note:
- `-SendRecoveryTest` peut echouer en `429` si le test recovery est relance trop vite.

## 6) Caddy redirections root/www
Extrait attendu dans `/etc/caddy/Caddyfile`:
```caddy
www.dzmarket.pro {
    redir https://app.dzmarket.pro{uri} 301
}

dzmarket.pro {
    redir https://app.dzmarket.pro{uri} 301
}
```

Apply:
```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

## 7) Troubleshooting rapide

### 7.1 SSH KO depuis un poste
1. Tester port 22:
```powershell
Test-NetConnection 91.107.239.5 -Port 22
```
2. Verifier cle + passphrase.
3. Verifier `fail2ban`/firewall cote serveur.

### 7.2 Erreur scp chemin local
- Verifier chemin reel (poste/cwd).
- En CMD, utiliser chemins absolus `C:\...`.

### 7.3 ADB non trouve
- Utiliser `C:\Android\sdk\platform-tools\adb.exe`.

## 8) Lancement public - regle simple
GO si:
- quality gate PASS
- mix load reference PASS (`220+5`)
- SLI PASS
- auth smoke PASS
- smoke manuel P0 PASS

NO-GO sinon.

## 9) Interview prep (Tech Lead)
Pitch court:
- migration complete vers infra self-hosted
- runbooks, QA, charge, incidents
- focus fiabilite + delivery + mentoring

Points a illustrer:
1. incident SSH resolu sans downtime majeur
2. correction label URLs + callback auth
3. campagne charge et definition budget d'exploitation
