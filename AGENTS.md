# DZMarket Agent Instructions

- Keep context small: start with `docs/agent/README.md`, then read only the task-specific file.
- Treat live code, migrations, and config as source of truth over old handovers.
- Preserve unrelated dirty worktree changes; never revert user work unless explicitly requested.
- Keep fixes narrow, run targeted tests, and report any unverified risk before release.
- Never commit or print secrets, private keys, plist contents, keystores, passwords, service-role keys, or token values.
- When code/config/deploy behavior changes, update the matching `docs/agent/*.md` instruction file in the same turn.
- Commit only intentional files and push after verification when Git auth/remote are available.
