# Agent Workflow Rules

Read this before changing code, config, deploy scripts, or project instructions.

## Default Flow

1. Check `git status --short --branch`.
2. Inspect live files before trusting old markdown or chat history.
3. Make the smallest safe change that solves the current task.
4. Run targeted tests or checks that match the changed area.
5. Update the smallest relevant file in `docs/agent/` when behavior, release steps, server operations, database rules, or known issues changed.
6. Commit only intentional files.
7. Push after verification when the remote and credentials are available.

## Documentation Hygiene

- One topic per markdown file; do not grow one monolithic handover.
- Keep `docs/agent/README.md` as the index only.
- Prefer updating an existing small topic file over editing old broad docs.
- Do not copy full old Codex JSONL sessions into repo docs.
- Keep docs operational and current; mark stale historical docs as historical instead of treating them as truth.

## Git Safety

- Preserve unrelated dirty files.
- Do not use destructive Git commands unless explicitly requested.
- Do not commit generated caches or build outputs.
- Do not commit secrets or local-only credentials.
- If the worktree is dirty, stage explicit paths only.

