# DZMarket Agent Notes

Purpose: keep future agent context small. Read only the file that matches the task.

## Read Order

- New or unclear task: read this file, then `project-map.md`.
- Mobile build, Codemagic, TestFlight, Play Console, Firebase, APNs: read `mobile-release.md`.
- Hetzner, Supabase stack, prod logs, web deploy: read `server-ops.md`.
- SQL, RPC, schema, migrations, RLS: read `db-and-migrations.md`.
- Tests, USB checks, regression safety: read `qa-regression.md`.
- Recent bugs and release cautions: read `known-issues.md`.
- Old documentation cleanup decisions: read `doc-inventory.md`.
- Agent workflow, commits, pushes, and doc hygiene: read `workflow-rules.md`.

## Rules

- Treat live repo files as source of truth over old handovers.
- Do not load old Codex JSONL sessions wholesale. Search targeted excerpts only.
- Preserve unrelated dirty worktree changes.
- Never commit or print secrets: API keys, service-role keys, `.p8`, plist contents, keystores, passwords.
- Prefer narrow fixes plus targeted tests before any release.
- If behavior, deployment, tests, or operational process changes, update the smallest matching file in this folder before commit/push.
