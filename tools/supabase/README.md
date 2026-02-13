# Supabase CLI (Pinned Local Copy)

This folder contains a pinned Windows Supabase CLI binary used by this project.

## Purpose
- Keep a known CLI version for reproducible deploy/migration commands.
- Avoid relying on globally installed CLI versions.

## Files
- `supabase.exe`
- `supabase_windows_amd64_v2.75.0.tar.gz`
- `LICENSE`

## Usage (Windows PowerShell)
Run from repo root:

```powershell
.\tools\supabase\supabase.exe --version
.\tools\supabase\supabase.exe db push
.\tools\supabase\supabase.exe functions deploy job-runner
.\tools\supabase\supabase.exe functions deploy create_shipment
```

## Notes
- Authenticate first with your Supabase account/token.
- Keep project secrets in environment variables or CI secrets, not in Git.

## Next Updates
See NEXT_UPDATES.md for the current prioritized roadmap and release checklist.

