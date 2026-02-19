# DZMarket - Runbook Ops + Interview Prep

Version: 2026-02-17  
Audience: Mustapha (owner), ops/dev team  
Goal: avoir un guide unique, pratique, pour exploiter la plateforme et preparer l'entretien Tech Lead Java.

---

## 1) Architecture actuelle (prod)

### 1.1 Serveurs Hetzner

- `dzm-app-01` (`91.107.239.5`) : Caddy + stack Supabase self-host (Kong/Auth/Rest/Storage/etc.).
- `dzm-db-01` (`46.225.88.249`) : PostgreSQL dedie.
- `dzm-storage-01` (`91.98.227.237`) : MinIO objet.

Reseau prive:

- reseau: `dzmarket-net`
- plage: `10.30.0.0/16`

### 1.2 Domaines en service

- `app.dzmarket.pro` -> frontend web
- `api.dzmarket.pro` -> API Supabase/Kong
- `dzmarket.pro` -> redirection vers `app.dzmarket.pro`

---

## 2) Ce qui est deja installe

Sur `dzm-app-01`:

- Ubuntu 24.04 LTS
- Docker + Docker Compose plugin
- Caddy (reverse proxy + TLS Let's Encrypt)
- Supabase self-host via compose:
  - `kong`, `auth`, `rest`, `realtime`, `storage`, `db`, `meta`, `studio`, `pooler`, `vector`, `analytics`, `imgproxy`
- override healthcheck storage (localhost IPv4)
- SMTP Brevo configure pour Auth (emails transactionnels)

---

## 3) Commandes operations (PowerShell/CMD + Linux)

## 3.1 Connexion SSH (Windows PowerShell)

```powershell
ssh -i "$env:USERPROFILE\.ssh\dzmarket_hetzner" -o IdentitiesOnly=yes root@91.107.239.5
```

## 3.2 Connexion SSH (Windows CMD)

```bat
ssh -i "%USERPROFILE%\.ssh\dzmarket_hetzner" -o IdentitiesOnly=yes root@91.107.239.5
```

## 3.3 Verification rapide plateforme (sur serveur)

```bash
hostname
systemctl is-active ssh
cd /opt/supabase/docker
docker compose -f docker-compose.yml -f docker-compose.s3.yml ps
```

---

## 4) DNS + Caddy (configuration type)

## 4.1 Enregistrements DNS minimum

- `@` (A) -> `91.107.239.5`
- `app` (A) -> `91.107.239.5`
- `api` (A) -> `91.107.239.5`
- `www` (CNAME) -> `app.dzmarket.pro`

Important:

- Eviter coexistence `www` en A + CNAME.
- Garder une seule definition pour `www`.

## 4.2 Caddyfile (serveur app)

Fichier: `/etc/caddy/Caddyfile`

```caddy
api.dzmarket.pro {
  reverse_proxy 127.0.0.1:8000
}

app.dzmarket.pro {
  root * /var/www/dzmarket-web
  file_server
  try_files {path} /index.html
}

dzmarket.pro {
  redir https://app.dzmarket.pro{uri}
}
```

Appliquer:

```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
journalctl -u caddy -f
```

---

## 5) Supabase self-host - commandes essentielles

## 5.1 Lancer/recreer stack

```bash
cd /opt/supabase/docker
docker compose -f docker-compose.yml -f docker-compose.s3.yml up -d
```

Recreation ciblee:

```bash
docker compose -f docker-compose.yml -f docker-compose.s3.yml up -d --force-recreate auth kong
```

## 5.2 Healthcheck Storage (fix IPv4)

Fichier override: `docker-compose.override.yml` ou `docker-compose.healthfix.yml`

```yaml
services:
  storage:
    healthcheck:
      test: ["CMD-SHELL","wget -q -O /dev/null http://127.0.0.1:5000/status || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 10
```

Appliquer:

```bash
docker compose -f docker-compose.yml -f docker-compose.s3.yml -f docker-compose.override.yml up -d --force-recreate storage
docker compose -f docker-compose.yml -f docker-compose.s3.yml -f docker-compose.override.yml ps
```

---

## 6) Deploy frontend web (Flutter web)

## 6.1 Build (PC avec le code)

```powershell
flutter clean
flutter pub get
flutter build web --release
```

## 6.2 Zip build (PowerShell)

```powershell
Compress-Archive -Path .\build\web\* -DestinationPath .\dzmarket-web.zip -Force
```

Si tu es en CMD:

```bat
powershell -NoProfile -Command "Compress-Archive -Path 'C:\src\IA\dzmarket\build\web\*' -DestinationPath 'C:\src\IA\dzmarket\dzmarket-web.zip' -Force"
```

## 6.3 Upload + install sur serveur

```bat
scp -i "%USERPROFILE%\.ssh\dzmarket_hetzner" -o IdentitiesOnly=yes "C:\src\IA\dzmarket\dzmarket-web.zip" root@91.107.239.5:/tmp/dzmarket-web.zip
```

```bat
ssh -i "%USERPROFILE%\.ssh\dzmarket_hetzner" -o IdentitiesOnly=yes root@91.107.239.5 "apt-get install -y unzip && rm -rf /var/www/dzmarket-web/* && unzip -o /tmp/dzmarket-web.zip -d /var/www/dzmarket-web && curl -I https://app.dzmarket.pro"
```

---

## 7) SMTP Brevo (Auth Supabase)

## 7.1 Variables a configurer dans `/opt/supabase/docker/.env`

- `SMTP_HOST=smtp-relay.brevo.com`
- `SMTP_PORT=587`
- `SMTP_USER=<brevo_login>`
- `SMTP_PASS=<brevo_secret>`
- `SMTP_ADMIN_EMAIL=no-reply@dzmarket.pro`
- `SMTP_SENDER_NAME=DZMarket`
- `SITE_URL=https://app.dzmarket.pro`
- `API_EXTERNAL_URL=https://api.dzmarket.pro`
- `SUPABASE_PUBLIC_URL=https://api.dzmarket.pro`

## 7.2 Injection fiable pour GoTrue (auth override compose)

Fichier conseille: `docker-compose.authfix.yml`

```yaml
services:
  auth:
    environment:
      GOTRUE_EXTERNAL_EMAIL_ENABLED: "true"
      GOTRUE_DISABLE_SIGNUP: "false"
      GOTRUE_MAILER_AUTOCONFIRM: "false"
      GOTRUE_SMTP_HOST: "${SMTP_HOST}"
      GOTRUE_SMTP_PORT: "${SMTP_PORT}"
      GOTRUE_SMTP_USER: "${SMTP_USER}"
      GOTRUE_SMTP_PASS: "${SMTP_PASS}"
      GOTRUE_SMTP_ADMIN_EMAIL: "${SMTP_ADMIN_EMAIL}"
      GOTRUE_SMTP_SENDER_NAME: "${SMTP_SENDER_NAME}"
      GOTRUE_MAILER_EXTERNAL_HOSTS: "api.dzmarket.pro,app.dzmarket.pro"
```

Appliquer:

```bash
docker compose -f docker-compose.yml -f docker-compose.s3.yml -f docker-compose.authfix.yml up -d --force-recreate auth kong
```

## 7.3 Templates email DZMarket (confirmation + reset)

Objectif:

- Email de confirmation compte avec branding DZMarket.
- Email de reset mot de passe avec branding DZMarket.
- FR/AR dans le meme template selon `user_metadata.lang` (`fr` par defaut, `ar` si present).

Fichier override conseille: `docker-compose.auth-mail-templates.yml`

```yaml
services:
  auth:
    environment:
      GOTRUE_MAILER_TEMPLATES_CONFIRMATION: "https://app.dzmarket.pro/auth-email/confirmation.html"
      GOTRUE_MAILER_TEMPLATES_RECOVERY: "https://app.dzmarket.pro/auth-email/recovery.html"
      GOTRUE_MAILER_SUBJECTS_CONFIRMATION: "DZMarket - Confirmez votre email / تأكيد البريد الإلكتروني"
      GOTRUE_MAILER_SUBJECTS_RECOVERY: "DZMarket - Réinitialisation du mot de passe / إعادة تعيين كلمة المرور"
```

Verifier que les templates sont bien servis par le site web:

```bash
curl -I https://app.dzmarket.pro/auth-email/confirmation.html
curl -I https://app.dzmarket.pro/auth-email/recovery.html
```

Appliquer l'override auth:

```bash
docker compose -f docker-compose.yml -f docker-compose.s3.yml -f docker-compose.authfix.yml -f docker-compose.auth-mail-templates.yml up -d --force-recreate auth kong
```

Verifier env dans le conteneur:

```bash
docker inspect supabase-auth --format '{{range .Config.Env}}{{println .}}{{end}}' | grep GOTRUE_MAILER_TEMPLATES
docker inspect supabase-auth --format '{{range .Config.Env}}{{println .}}{{end}}' | grep GOTRUE_MAILER_SUBJECTS
```

Verifier env dans container:

```bash
docker inspect supabase-auth --format '{{range .Config.Env}}{{println .}}{{end}}' | grep GOTRUE_
```

Test recover:

```bash
ANON_KEY=$(grep '^ANON_KEY=' /opt/supabase/docker/.env | cut -d= -f2-)
curl -i -X POST https://api.dzmarket.pro/auth/v1/recover \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"<test_email@example.com>"}'
docker logs --tail 120 supabase-auth
```

---

## 8) Commandes smoke test production

```bash
curl -I https://app.dzmarket.pro
ANON_KEY=$(grep '^ANON_KEY=' /opt/supabase/docker/.env | cut -d= -f2-)
curl -s -H "apikey: $ANON_KEY" https://api.dzmarket.pro/auth/v1/health
curl -i -H "apikey: $ANON_KEY" https://api.dzmarket.pro/storage/v1/status
```

Attendu:

- app: `HTTP/2 200`
- auth health: JSON GoTrue
- storage status: `HTTP/2 200`

## 8.1 Script auto smoke test (Windows -> SSH)

Depuis ton poste Windows (PowerShell):

```powershell
cd C:\src\IA\dzmarket
.\scripts\auth_smoke_check.ps1
```

Avec test d'envoi mail recovery:

```powershell
.\scripts\auth_smoke_check.ps1 -SendRecoveryTest -TestEmail "hafmustapha3@gmail.com"
```

Le script verifie automatiquement:

- app web (`app.dzmarket.pro`)
- auth health
- storage status
- templates email accessibles
- variables mailer chargees dans `supabase-auth`
- absence d'erreurs de parsing template dans logs auth
- (optionnel) appel API recover = `HTTP 200`

---

## 9) Troubleshooting rapide

## 9.1 `ssh timeout` seulement sur un PC

Verifier:

- reseau local / firewall entreprise
- port 22 sortant bloque
- cle SSH chargee
- known_hosts incoherent

Commandes utiles (PowerShell):

```powershell
Test-NetConnection 91.107.239.5 -Port 22
Get-Command ssh
where.exe ssh
ssh-keygen -R 91.107.239.5
```

## 9.2 CMD vs PowerShell

- `Compress-Archive` = PowerShell cmdlet, pas CMD natif.
- En CMD, prefixer par `powershell -NoProfile -Command "..."`

## 9.3 Caddy certs

Si pas de TLS:

- verifier DNS pointe bien vers le serveur
- verifier ports 80/443 ouverts
- suivre logs: `journalctl -u caddy -f`

## 9.4 Storage unhealthy

Toujours preferer healthcheck `127.0.0.1` (pas `localhost` IPv6).

---

## 10) Securite et hygiene

- Ne jamais publier les vrais secrets (SMTP, JWT, DB passwords).
- Regenerer toute cle exposee dans chat/capture.
- Sauvegarde avant chaque modif `.env`:

```bash
cp .env ".env.bak.$(date +%F-%H%M%S)"
```

- Garder un rollback simple:
  - backup DB
  - backup Caddyfile
  - backup `.env`

---

## 11) Interview prep - Tech Lead Java (Berger-Levrault)

## 11.1 Ce que l'offre cherche (resume)

- Lead technique Java/Spring.
- Qualite de code, architecture, mentoring.
- CI/CD, tests, APIs REST, SQL.
- Collaboration Agile (equipes 5-7).

## 11.2 Ton positionnement (CV -> offre)

Points forts a mettre en avant:

- 7+ ans data/logiciel (SQL, ETL, DWH, Cloud, dev full cycle).
- Experience Java + APIs + base de donnees + qualite.
- Pratiques ops/dev reelles (Docker, CI/CD, troubleshooting prod).
- Capacite a structurer, documenter et accompagner l'equipe.

## 11.3 Pitch 60-90 secondes (pret a dire)

"Je suis ingenieur logiciel/data avec 7+ ans d'experience sur des environnements critiques.  
J'ai travaille sur SQL Server, Oracle, PostgreSQL, ETL et developpements Java/API.  
Ces derniers mois, j'ai pilote en autonomie une migration applicative complete vers une infra self-hosted: DNS, reverse proxy TLS, services Docker, auth SMTP, data migration et validation end-to-end.  
Mon point fort est de relier technique et execution: je securise l'architecture, je standardise les pratiques et je debloque les incidents rapidement.  
Je veux aujourd'hui prendre un role de Tech Lead pour faire monter l'equipe en qualite, delivery et fiabilite produit."

## 11.4 6 questions probables + reponses attendues

1) Comment tu encadres une equipe tech?
- alignement clair (qualite, definition of done, normes)
- pairing/review utile
- coaching par objectifs, pas micro-management

2) Comment tu geres la dette technique?
- priorisation risque/impact
- budget de refacto a chaque sprint
- indicateurs: bug rate, lead time, disponibilite

3) Ton approche architecture?
- simple d'abord
- modularite, observabilite, testabilite
- ADR (decision records) pour tracer les choix

4) Qualite logicielle?
- PR checklist
- tests unitaires + integration
- CI gate (lint/tests/security)

5) Incident production critique?
- containment rapide
- rollback ou feature flag
- post-mortem sans blame + actions correctives

6) Pourquoi Berger-Levrault?
- impact concret secteur public/industrie
- enjeu long terme
- role de lead mixant technique + humain

## 11.5 Tes exemples STAR (utilise DZMarket)

### STAR 1 - Migration plateforme
- Situation: dependance cloud externe + besoin de maitrise infra.
- Task: migrer sans perte de donnees et garder la continuit.
- Action: setup Hetzner, self-host Supabase, migration DB+storage, DNS/Caddy/TLS, tests E2E.
- Result: plateforme operationnelle, auth/storage OK, runbook documente.

### STAR 2 - Incident SSH blocant
- Situation: acces SSH coupe sur un poste.
- Task: reprendre la main sans downtime.
- Action: diagnostic reseau, rescue mode, verification sshd/firewall, validation multi-postes.
- Result: acces retabli, procedure de recovery standardisee.

### STAR 3 - Auth email non pro
- Situation: erreurs confirmation/recover.
- Task: fiabiliser experience utilisateur.
- Action: config SMTP Brevo + variables GoTrue + tests logs + callback web.
- Result: envoi email fonctionnel, flux de validation stabilise.

## 11.6 Questions intelligentes a poser demain

1) Quelles sont vos 3 priorites techniques sur 12 mois?
2) Quel niveau d'autonomie reelle pour les choix d'architecture?
3) Quels KPIs engineering suivez-vous (qualite/delivery/fiabilite)?
4) Comment est organise le mentoring des devs moins seniors?
5) Qu'attendez-vous de la personne dans les 90 premiers jours?

## 11.7 Plan de preparation (ce soir + demain matin)

Ce soir (60-90 min):

- relire pitch + 3 STAR
- preparer 2 questions metier + 2 questions techniques
- relire l'offre et surligner les mots cles

Demain matin (30 min):

- repetition orale du pitch (2 fois)
- checklist exemples concrets (architecture, qualite, incident)
- preparer une conclusion claire (motivation + disponibilite)

---

## 12) Checklist finale avant mise en public

- [ ] Web `app.dzmarket.pro` OK (cache nettoye)
- [ ] API `api.dzmarket.pro` health OK
- [ ] Signup + confirmation email + recover password OK
- [ ] Upload images annonces OK
- [ ] Chat + notifications + tri conversation OK
- [ ] Offre negociable (regles min/max) OK
- [ ] Monitoring + backups + rotation secrets planifies

---

## 13) Notes importantes

- Les valeurs sensibles ci-dessus sont volontairement en placeholders.
- Si un secret a ete partage en clair, faire rotation immediate.
- Garder ce document a jour apres chaque changement infra/ops.
