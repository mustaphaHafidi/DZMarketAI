# Documentation Inventory

This file records what future agents should read, keep, archive, or ignore.

## Primary Agent Docs

- `docs/agent/README.md`: entrypoint.
- `docs/agent/project-map.md`: compact repo map.
- `docs/agent/mobile-release.md`: Android/iOS release and Firebase/APNs.
- `docs/agent/server-ops.md`: Hetzner and production diagnostics.
- `docs/agent/db-and-migrations.md`: schema and SQL rules.
- `docs/agent/qa-regression.md`: test and release gates.
- `docs/agent/known-issues.md`: recent cautions.

## Keep As Reference

- `README.md`: public repo overview.
- `config.md`: runtime config reference; may need later consolidation.
- `infra/hetzner/SERVERS_CONFIG_AND_KEYS.md`: operational map without secret values.
- `docs/SLO_SLI_DZMARKET.md`: production reliability targets.
- `docs/QA_SMOKE_AND_LOCAL_CHECKLIST.md`: detailed QA checklist.
- `docs/QA_RUNBOOK_FR_AR.md`: manual QA in French/Arabic.
- `docs/PRODUCT_SPEC_PDF_RETURNS_NOTIFICATIONS.md`: product/ops spec details.
- carrier integration docs under `skill_yallidine`, `skill_zrexpress`, `skill_ecotrack`, and `GUEPEX_INTEGRATION_DOCUMENTATION.md`.

## Stale Or Archive Candidates

Do not read these by default; they are historical and can mislead current work:

- `PROJECT_CONTEXT.md`
- `NEXT_STEPS.md`
- `NEXT_UPDATES.md`
- `SKILL_DZmarketAI.md`
- `Skill_DB.md`
- `docs/HANDOVER_PC2.md`
- `docs/RELEASE_1_0_3_STABILITY_UPDATE.md`
- `docs/GO_NO_GO_PUBLIC_LAUNCH.md`
- `docs/LOAD_TEST_PLAN_1M.md`
- `docs/READ_PATH_OPTIMIZATION_240_PLUS.md`
- `docs/PUBLIC_LAUNCH_RUNBOOK_J0_J1.md`
- `PLAN_1M_USERS.md`
- `BUSINESS_PLAN_DZMARKET_24M.md`
- `MARKETING_PLAN_DZMARKET_12M.md`

## Local / Generated Files To Ignore

- screenshots from Codemagic/App Store/Firebase manual work
- `.playwright-mcp/`
- root `*.out.txt` and `*.err.txt`
- root deploy archives like `dzmarket-web*.zip` and `dzmarket-web*.tar.gz`
- local Apple/Firebase secret material
- Flutter build caches: `build/`, `.dart_tool/`
- generated marketing video outputs

