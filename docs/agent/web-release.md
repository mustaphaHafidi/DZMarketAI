# Web Release Gate

Use this before staging any DZMarket web artifact.

1. Build the exact intended source state.
2. Run `powershell -ExecutionPolicy Bypass -File .\scripts\verify_web_artifact.ps1`.
3. Stage and atomically swap the complete `build\web` artifact while preserving
   the production `config.json` and one rollback.
4. Verify `www`, `app`, `robots.txt`, `sitemap.xml`, and the two icon-font URLs return HTTP 200. Check the
   sign-in page console has no font or favicon 404 errors.

Never deploy a partial selection of files from `build\web`.

For a feature with a database migration, a successful web build is not enough:
apply and verify the migration first, then execute the feature's acceptance
gate (for vehicles, `vehicle-release.md`) before the atomic release swap.
