# Supabase self-host - DZMarket (App/Edge server)

## Prerequis
- Docker + Docker Compose
- Acces aux 3 serveurs:
  - DB (PostgreSQL)
  - App/Edge (ce serveur)
  - Storage (MinIO)

## 1) Recuperer la config officielle (recommended)
Dans un dossier temporaire:

```bash
git clone https://github.com/supabase/supabase.git
cd supabase/docker
```

Copier le docker-compose et les fichiers de config dans `infra/supabase/` :

```bash
cp docker-compose.yml ../../infra/supabase/docker-compose.prod.yml
cp .env.example ../../infra/supabase/.env.example
```

## 2) Configurer `.env` (exemple)
Dupliquer `.env.example` en `.env` puis remplir:

- `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
- `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`
- `SITE_URL`, `API_EXTERNAL_URL`, `SUPABASE_PUBLIC_URL`
- Storage: `MINIO_ENDPOINT`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`

## 3) Lancer
Depuis `infra/supabase/` :

```bash
docker compose -f docker-compose.prod.yml up -d
```

## 4) Ports recommandés
- 8000 (Kong) -> api.app.dz
- 3000 (Studio) -> studio.app.dz (optionnel)
- 5432 (DB) -> interne uniquement

## 5) Notes
- La DB est externe (Serveur A).
- MinIO est externe (Serveur C).
- Mettre les secrets dans un gestionnaire ou fichier .env non versionne.

