# Loop Engineer — DZMarket

Use `$dzmarket-loop-engineer` for one approved milestone at a time. Purpose:
turn an already-approved decision into a verified, reviewable delivery — not
to autonomously expand product scope, change pricing/monetization, or decide
open product questions on its own.

Originates from El-Himma's `docs/agent/loop-engineer.md` contract, adapted to
DZMarket's own stack (Flutter + self-hosted Supabase/Hetzner) and its own
existing quality-gate script.

## Request Format

```text
Milestone:
Acceptance criteria:
Relevant plan/doc section:
Do not touch:
Device test required: yes/no
Deployment requested: yes/no
```

## Operating Contract

Before editing, read only what's needed to act:
- the relevant plan file (currently `C:\Users\ssloc\.claude\plans\sleepy-percolating-lamport.md`
  "Plan actif") and `docs/agent/next-release-follow-ups.md`;
- current branch and `git status --short`;
- task-specific source, test, and migration files only.

Write concrete acceptance criteria before changing code. Preserve unrelated
dirty files. Never read, print, commit, or copy secrets (Supabase service
role key, SSH key passphrase, Play/App Store credentials).

## Delivery Loop

1. Pick the smallest remaining item from the approved plan. Do not pull in
   anything not already approved (new category, new fee, new field) —
   those are founder decisions, not loop-engineer scope.
2. Make that change only.
3. Validate with the repo's own gate:
   ```powershell
   .\scripts\run_quality_gate.ps1
   ```
   add `-RunIntegration -DeviceId <id>` only once a device shows
   `adb devices` as authorized (not `unauthorized`/`offline`), and only for
   the specific `-IntegrationPhase` the milestone needs (`smoke` first).
   This script never deploys, never touches prod DB/storage, never bumps
   store listings — those stay separate, explicitly approved steps.
4. Load/platform testing already has a harness in this repo: `load/*.js`
   (k6 scripts: `listings`, `auth`, `orders`, `shipments`) driven by
   `scripts/run_k6_phase.ps1` / `run_k6_mix_matrix.ps1`, env from
   `load/env.example`. It targets `api.dzmarket.pro` (production) by
   design, with writes gated off by default (`WRITE_ENABLED=0`) — read-only
   phases are already the safe default. Only the `k6` binary itself may be
   missing locally (`choco install k6` / `winget install k6`); report that
   plainly rather than guessing a result. Enabling `WRITE_ENABLED=1` or a
   `spike`/`soak` phase against prod still needs the founder's go-ahead.
5. Compare the diff to the task. Confirm no unrelated file, secret, or
   out-of-scope product decision was touched.
6. If a check fails, diagnose the specific observed cause and retry only
   that cause. Maximum three attempts per failure; never repeat an
   unchanged failing command.

## Stop And Escalate

Stop and ask the founder when:
- a product decision is still open (e.g. the 4-vs-6 vehicle subcategory
  split flagged in `next-release-follow-ups.md` — never resolve this
  unilaterally);
- a Supabase/Postgres migration needs to be applied to production (needs
  SSH access/passphrase to `dzm-app-01` or `dzm-db-01` — never guessed or
  bypassed);
- the Android device shows `unauthorized`/`offline` in `adb devices` — this
  needs a physical tap on the device's own USB-debugging prompt, which the
  agent cannot do;
- the task would bump a version/build number, trigger a Play Console/
  TestFlight/Codemagic upload, or touch any store listing;
- the task would run any test against the live production API/DB instead of
  a local/staging target.

Deployment and store submission remain separate approval + runbook gates
(see `android-ios-apps` skill and the existing upload scripts). Local green
checks are not a deployment authorization.

## Completion Report

Return only:
- changed files;
- commands run (`run_quality_gate.ps1` and any other) and their actual
  result, not an assumed one;
- device-test status (and why, if skipped);
- deploy/store status, if any (should normally be "not attempted");
- remaining risk or explicit blocker, named plainly (e.g. "device
  unauthorized", "k6 not installed", "migration not applied — needs SSH
  passphrase").
