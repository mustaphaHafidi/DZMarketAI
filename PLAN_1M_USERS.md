# Plan 1M Utilisateurs/An - DZMarket

## 1) Objectif
- Cible business: 1M utilisateurs/an (trafic annuel, croissance progressive).
- Cible technique: disponibilite > 99.5%, temps de reponse API p95 < 400 ms.
- Contrainte budget: scale par paliers, sans surdimensionner trop tot.

## 2) Hypotheses de charge
- 3 photos max/annonce, 4 MB max/photo (12 MB brut/annonce).
- Forte saisonnalite (pics soir/weekend, promos, retours colis).
- Flux critiques: auth, creation annonce, messagerie, commandes, bordereaux.

## 3) Architecture cible
- Web/App: `app.dzmarket.pro`
- API Supabase/Kong: `api.dzmarket.pro`
- Stack: Supabase self-host (Auth, PostgREST, Realtime, Storage, Edge Functions)
- DB: PostgreSQL (primary, puis replica lecture)
- Objet: MinIO/S3 compatible + CDN
- Reverse proxy/TLS: Caddy
- Securite edge: Cloudflare (DNS, SSL, WAF, rate limit)

## 4) Phasage de montee en charge
### Phase A - Lancement (jusqu'a ~100k utilisateurs/an)
- 3 noeuds separes: app/api, db, storage.
- Sauvegardes DB + tests de restauration mensuels.
- Alerting minimal: CPU, RAM, disque, erreurs 5xx, latence p95.

### Phase B - Croissance (~100k -> 500k/an)
- Ajout Redis (cache + throttling + anti-spike).
- Replica PostgreSQL pour lectures lourdes (dashboard, stats vendeur).
- Jobs asynchrones dedies (notifications, transporteurs, recalcul stats).
- Objectif: p95 API < 350 ms.

### Phase C - Acceleration (~500k -> 1M/an)
- API horizontalisee derriere LB.
- Realtime isole si saturation.
- DB haute dispo (primary + replica + failover teste).
- Stockage objet redondant + politique lifecycle.
- Objectif: p95 API < 250 ms sur endpoints critiques.

## 5) Seuils d'upgrade (gating)
- CPU > 70% soutenu 15 min.
- RAM > 80% soutenu 15 min.
- DB connexions > 75% du max.
- p95 endpoint critique > 400 ms (3 fenetres de suite).
- Erreurs 5xx > 1% sur 5 min.
- Stockage > 75% capacite.

## 6) Optimisations produit obligatoires
- Pagination stricte sur annonces/messages.
- Index DB revus trimestriellement (orders, messages, products, shipments).
- Pre-calcul KPI vendeur (eviter agregats lourds en live).
- Upload image: compression + miniatures + controle taille.
- Rate-limit sur auth, reset password, creation offre/commande.

## 7) Securite et conformite
- Secrets hors repo (`.env`, secret manager CI/CD).
- RLS stricte + audit des policies.
- Chiffrement des tokens transporteurs et journaux d'acces.
- Backup off-site hebdo + test restore mensuel.
- Journalisation des actions sensibles (auth, commandes, remboursements).

## 8) Budget indicatif
- Phase A: 200-400 EUR/mois
- Phase B: 400-900 EUR/mois
- Phase C: 900-1800 EUR/mois

## 9) Roadmap operationnelle (prochaines actions)
1. Finaliser observabilite (dashboards + alertes p95/5xx).
2. Executer tests de charge realistes (auth, chat, annonce, commande, label).
3. Definir runbook incident (DB saturee, queue bloquee, provider transport down).
4. Mettre en place revue capacite hebdomadaire (SLO + couts + saturation).

## 10) Checklist avant scale publique large
- Test E2E complet (web + mobile) valide.
- Test charge valide avec rapport chiffre.
- Rollback DB + rollback web documentes et testes.
- Support operationnel pret (retours, litiges, pannes transporteurs).

---
Reference execution: `NEXT_UPDATES.md` (priorites) + `infra/HETZNER_MIGRATION_RUNBOOK.md` (runbook infra).
