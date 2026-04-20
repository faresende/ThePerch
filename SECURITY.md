# Security policy

## Reporting a vulnerability

Email me@hellofabio.com with a description of the issue, reproduction steps, and any supporting context. Please do not open a public GitHub issue for security reports. I will acknowledge within a few days and work with you on a fix and a coordinated disclosure window.

## How secrets are managed in this project

The project has three code paths that touch credentials. Each has its own source of truth and no secret is ever committed to git.

### iOS app

- Real values live in `ios/ThePerch/Sources/ThePerch/Config/Secrets.xcconfig` (gitignored).
- The committed template is `ios/ThePerch/Sources/ThePerch/Config/Secrets.example.xcconfig`.
- Xcode substitutes the xcconfig values into `Info.plist` at build time via `$(VAR)` references.
- `AppConfig` reads them from `Bundle.main.infoDictionary` at runtime. A legacy `Secrets.plist` fallback also works for backward compatibility.
- The iOS app stores only the Supabase publishable key (safe to ship in the binary) and the Karakeep API token. It never ships the Supabase service-role key or any other privileged credential.

Setup on a new machine:

```sh
cp ios/ThePerch/Sources/ThePerch/Config/Secrets.example.xcconfig \
   ios/ThePerch/Sources/ThePerch/Config/Secrets.xcconfig
# edit Secrets.xcconfig with real values
```

### Python worker (`scripts/orders_autopilot_ingest_fastmail.py`)

- Real values live in `scripts/.env` (gitignored).
- The committed template is `scripts/.env.example`.
- The worker calls `_require_env(name)` at startup; any missing required variable causes the process to exit with status 2 and a clear stderr message.
- Required variables: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `PERCH_USER_ID`.

Setup on a new machine:

```sh
cp scripts/.env.example scripts/.env
# edit scripts/.env with real values
```

### Supabase Edge Functions

- All functions read secrets via `Deno.env.get(...)` and never hardcode values.
- Values are registered per function with `supabase secrets set --project-ref <ref> KEY=VALUE`.
- Each function's `README.md` documents which environment variables it requires.

## Prevention tooling

This repo runs two layers of automated secret detection.

- **Local pre-commit hook:** `.pre-commit-config.yaml` runs `gitleaks` on staged changes before every commit, plus `detect-private-key` and large-file checks. Install once per machine:
  ```sh
  brew install pre-commit   # or: pip install pre-commit
  pre-commit install
  ```
- **CI on every pull request and push to `main`:** `.github/workflows/secrets-scan.yml` runs `gitleaks` against both the working tree and full git history. The job fails (and blocks merge) on any finding.

Both layers can be bypassed with `git commit -n`. Please do not.

## What to do if a secret leaks

1. **Rotate immediately.** Do not wait for the scrub. The moment a secret is public, treat it as compromised.
   - Supabase: rotate keys in Dashboard, Settings, API.
   - OpenAI / Anthropic / ElevenLabs / Google: rotate in each provider's console.
   - Telegram bot tokens: rotate via BotFather.
   - Apple Developer keys: rotate in App Store Connect, Users and Access, Integrations.
2. **Remove from HEAD.** Delete or redact the value in the working tree and commit the fix.
3. **Scrub from history.** Run `scripts/purge-secrets-from-history.sh` after adding the new literal to the script's `REPLACEMENTS` list. This uses `git filter-repo --replace-text` to rewrite every commit. The script will not run without explicit confirmation.
4. **Force-push and coordinate.** After the scrub, force-push every branch. Every collaborator must re-clone. Any fork must be deleted or re-cloned from the scrubbed upstream.
5. **Re-scan.** Run `gitleaks detect --source . --log-opts=--all --verbose --redact` locally and in CI to confirm the scrub worked.
6. **Document.** Add the incident to `SECURITY_AUDIT.md` so future audits have context.

## Known incidents

- **2026-04-20:** Supabase service-role key and OpenAI API key exposed via a public repository (not this one). Both keys were auto-revoked by their respective providers within hours. A full audit of this repository followed and is documented in `SECURITY_AUDIT.md`.
