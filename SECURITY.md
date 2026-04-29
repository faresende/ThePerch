# Security policy

## Reporting a vulnerability

Email me@hellofabio.com with a description of the issue, reproduction steps, and any supporting context. Please do not open a public GitHub issue for security reports. I will acknowledge within a few days and work with you on a fix and a coordinated disclosure window.

## How secrets are managed in this project

The project has three code paths that touch credentials. Each has its own source of truth and no secret is committed to git.

### iOS app

- Real values live in `ios/ThePerch/Sources/ThePerch/Config/Secrets.xcconfig` (gitignored).
- The committed template is `ios/ThePerch/Sources/ThePerch/Config/Secrets.example.xcconfig`.
- Xcode substitutes the xcconfig values into `Info.plist` at build time via `$(VAR)` references.
- `AppConfig` reads them from `Bundle.main.infoDictionary` at runtime.
- The iOS app stores only the Supabase publishable (anon) key, which is meant to ship in the binary, plus the Karakeep API token. It never ships the Supabase service-role key.

Setup on a new machine:

```sh
cp ios/ThePerch/Sources/ThePerch/Config/Secrets.example.xcconfig \
   ios/ThePerch/Sources/ThePerch/Config/Secrets.xcconfig
# edit Secrets.xcconfig with real values
```

### Python workers (`agents/health-integrations/*.py`, `scripts/*.py`)

- Real values live in `~/.openclaw/secrets/perch.env` (a flat shell-export file outside this repo) AND `scripts/.env` for the legacy ingest path. Both are gitignored.
- The committed template is `scripts/.env.example`.
- Each worker calls `_require_env(name)` (or equivalent) at startup; any missing required variable causes the process to exit with a clear stderr message.
- Common required variables: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `PERCH_USER_ID`. Per-integration: `OURA_PERSONAL_TOKEN`, `EIGHT_SLEEP_EMAIL/PASSWORD`, `WITHINGS_CLIENT_ID/SECRET`, `OPENAI_API_KEY`.

Setup on a new machine:

```sh
cp scripts/.env.example scripts/.env
# edit scripts/.env with real values
# OR (for the agents/health-integrations path) populate ~/.openclaw/secrets/perch.env
```

### Supabase Edge Functions

The repo currently ships one edge function: `supabase/functions/nutrition-copilot/`. It reads `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` + `SUPABASE_ANON_KEY` via `Deno.env.get(...)` and is gated behind a per-request user-JWT check so the service-role key is never exposed across tenant boundaries. Set the env via:

```
supabase secrets set --project-ref <YOUR-PROJECT-REF> \
  SUPABASE_URL=… SUPABASE_ANON_KEY=…
# SUPABASE_SERVICE_ROLE_KEY is auto-injected by Supabase
```

Edge function callers must send a user-session JWT in the `Authorization: Bearer …` header — the anon key alone is rejected.

## Test fixtures and personal data

The classifier regression suite under `skill/dashboard-sync/test/fixtures/` is gitignored at the directory level. The harvest script `fetch_fixtures.py` downloads raw email bodies from Fastmail JMAP for offline replay; those bodies routinely include names, billing addresses, payment-card last-4s, and live customer-authenticate tokens. Re-running the script is fine — the directories are gitignored so the dumps stay local. **Never force-add committed fixtures unless they have been hand-redacted to remove all PII and authentication URLs.**

Screenshot drops under `docs/Images/` and `docs/screenshots/` are also gitignored. Real app screenshots routinely show personal weight, sleep, food, calendar, and bookmark data. If you need a screenshot for the README or a write-up, run `seed-demo-data.js` first and capture against synthetic data.

## Prevention tooling

The repo ships `.gitleaks.toml` with a curated allowlist (well-known JWT header constants, archive-doc references to the rotated project ref, etc.). To run it locally before committing:

```sh
brew install gitleaks
gitleaks detect --source . --redact
```

Pre-commit hooks and CI enforcement are not currently wired up. They have been requested as follow-up work; until they ship, gitleaks is a best-effort manual layer.

## What to do if a secret leaks

1. **Rotate immediately.** Do not wait for the scrub. The moment a secret is public, treat it as compromised.
   - Supabase: rotate keys in Dashboard, Settings, API.
   - OpenAI / Anthropic / ElevenLabs / Google: rotate in each provider's console.
   - Telegram bot tokens: rotate via BotFather.
   - Apple Developer keys: rotate in App Store Connect, Users and Access, Integrations.
   - **Shopify customer-authenticate URLs:** these tokens stay live as long as the customer session exists. Sign out at the merchant's storefront from every device that has an active session — rotation is by-merchant, not centralized.
2. **Remove from HEAD.** Delete or redact the value in the working tree and commit the fix.
3. **Scrub from history.** Run `scripts/purge-secrets-from-history.sh` after adding the new literal to the script's `REPLACEMENTS` list. This uses `git filter-repo --replace-text` to rewrite every commit. The script will not run without explicit confirmation.
4. **Force-push and coordinate.** After the scrub, force-push every branch. Every collaborator must re-clone. Any fork must be deleted or re-cloned from the scrubbed upstream.
5. **Re-scan.** Run `gitleaks detect --source . --log-opts=--all --verbose --redact` locally to confirm the scrub worked.

## Known incidents

- **2026-04-20:** Supabase service-role key and OpenAI API key exposed via a different public repository (not this one). Both keys were auto-revoked by their respective providers within hours. A full audit of this repository followed; the rotated Supabase project ref appears only in archive design docs under `docs/archive/`, exempted in `.gitleaks.toml`.
- **2026-04-29:** Pre-public security pass discovered classifier-test fixtures contained raw Fastmail email bodies with names, billing addresses, payment last-4s, and four live Shopify customer-authenticate URLs. Fixtures deleted from the working tree and the holding directories gitignored. Customer sessions rotated by signing out at the affected merchants.
