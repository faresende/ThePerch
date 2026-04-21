# Security audit, 2026-04-20

This document summarizes the audit that followed the 2026-04-20 incident. It lists what was found, what was fixed, what remains for the human to complete, and the PR description to use when opening the review branch.

## Incident recap

On 2026-04-20 two keys leaked into a public GitHub repository:

1. A Supabase service-role key (prefix `sb_secret_eJlrj...`, key name "default"), auto-revoked by Supabase within hours.
2. An OpenAI API key (prefix `sk-proj-IG8cUzx...`), revoked by OpenAI on the same day.

Exposure window for both was under 24 hours. Supabase API logs for that window showed normal iOS token-refresh traffic and the expected Python worker POSTs; no mass exports, no schema changes, no auth-table tampering.

This audit took a worst-case view anyway and cleaned the repository comprehensively.

## What was found

Full classification table in `/tmp/secrets-audit.md` (generated during the audit). Summary:

- **The reported `sb_secret_eJlrj...` Supabase service-role key was not in this repository** (HEAD or history). It leaked from a different repository. Already revoked.
- **Six live-HEAD secrets** in a single file, `supabase/003_bookmarks.sql`, all introduced by commit `021118d` ("Pre-improvement snapshot", 2026-03-07):
  - OpenAI project key (revoked)
  - Two Google API keys (`goplaces`, `nano-banana-pro`)
  - OpenClaw gateway placeholder (user-confirmed stale, never a live credential)
  - ElevenLabs API key (SAG voice skill)
  - The file itself was an OpenClaw agent skills registry committed to the wrong repo.
- **One history-only secret** in `deploy-testflight.sh`: a Telegram bot token at commit `a6ad409c`. HEAD already used an env var fallback.
- **One history-only secret** in `ios/ThePerch/Sources/ThePerch/Config/Secrets.plist`: the legacy Supabase anon JWT, committed at `021118d`. Role is `anon` (publishable by design), so low risk; scrubbed anyway for hygiene.
- **Six false positives**: the Supabase publishable key in `AppConfig.swift:10` (designed to ship), a UI TextField placeholder in `OnboardingView.swift:68`, a test fixture in `ShareExtensionTests.swift:28`, a docs placeholder in `GETTING_STARTED.md:62`, and an example `password` string in `SETUP.md:153`.
- **No Fastmail, Apple Developer, AWS, GitHub, GitLab, Slack, Stripe webhook, Anthropic, or private-key leaks.** Every edge function reads secrets from `Deno.env.get(...)` correctly.

## What was fixed on branch `security/audit-2026-04-20`

Each bullet is one commit, in order.

1. `security: scaffold admin-create-user edge function` (`773c27b`): new Edge Function at `supabase/functions/admin-create-user/` that wraps `auth.admin.createUser` behind a JWT-verified `ADMIN_USER_UUIDS` allowlist. Designed for server-to-server invocation by Claudinho, not by the iOS app.
2. `security: remove supabase/003_bookmarks.sql` (`cbd3f0b`): deleted the OpenClaw skills registry file. Does not affect the ThePerch database.
3. `security: load Supabase credentials from env, fail fast if missing` (`eb75623`): replaced the sanitised-but-leaky `SUPABASE_KEY = '***REMOVED***'` constant in the Python worker with a strict `_require_env()` pattern. SUPABASE_URL and PERCH_USER_ID now also come from env.
4. `security: extend .gitignore, untrack Xcode user state, add secret templates` (`f94c209`): new `.gitignore` covering `.env`, `.env.*` (with `!.env.example`), `*.xcconfig` (with `!*.example.xcconfig`), `*.pem`, `*.key`, `id_rsa*`, `id_ecdsa*`, `id_ed25519*`, `service-account*.json`, `firebase-adminsdk*.json`, plus Python venv and editor junk. Untracked two Xcode user-state files that had been committed by accident. Added `Secrets.example.xcconfig` and `scripts/.env.example` as committed templates.
5. `security: add SECURITY.md, pre-commit gitleaks hook, CI secrets scan` (`ffdf6d0`): three layers of prevention. `SECURITY.md` documents the disclosure policy and the secret-management model per code path. `.pre-commit-config.yaml` runs gitleaks on staged changes before every commit. `.github/workflows/secrets-scan.yml` runs gitleaks on every PR, push to `main`, push to `security/**`, and manual dispatch. Both scans cover the working tree; CI also scans full history.
6. `security: add history scrub script for confirmed-leaked secrets` (`a00be17`): `scripts/purge-secrets-from-history.sh` uses `git filter-repo --replace-text` to redact the seven literal secrets from history. Requires explicit confirmation, warns about stashes, supports `--mirror` for the safer workflow. Not run as part of this audit.
7. `security: wire Secrets.xcconfig -> Info.plist -> SecretsLoader pipeline` (`b4665a8`): established the documented iOS secret-loading chain. `project.pbxproj` now references `Secrets.xcconfig` as the base configuration for Debug and Release on the main app target. `Info.plist` gained `$(VAR)` entries that Xcode substitutes at build time. `SecretsLoader.swift` provides a typed wrapper over `Bundle.main.object(forInfoDictionaryKey:)` that treats `REPLACE_ME*`, `YOUR_*`, and unresolved `$(NAME)` literals as missing. `AppConfig.managedCloudAnonKey` is now a computed property; the last hardcoded publishable key literal is gone from source.
8. `security: add python-dotenv loader and requirements.txt for worker` (`8e239fa`): the Python worker now calls `_load_dotenv_if_available()` at import time. python-dotenv is an optional dev dependency; production hosts continue to use host-provided env vars. `requirements.txt` pins `requests` and `python-dotenv`.
9. `security: DB hardening migration (RLS + tightened policies + search_path)` (`4bfd0c0`): `supabase/migrations/20260420230000_security_hardening.sql`. Enables RLS on `dashboard_records`, `home_widgets`, `sections`; replaces wide-open policies with per-operation `auth.uid() = user_id` policies scoped to the `authenticated` role; tightens `token_usage` INSERT; attaches `SET search_path = public, pg_temp` to the six advisor-flagged trigger functions. Not applied.

Also done, no commit required:
- Populated local `Secrets.xcconfig` and `scripts/.env` with known values. Service-role key and Karakeep token are marked `REPLACE_ME` for you to fill in.
- Verified `plutil -lint` on both `Info.plist` and `project.pbxproj`.

## What remains for you

### Critical (required before treating the repo as "safe")

1. **Rotate the Google API keys** (already done per your last message, listed for the record):
   - `AIzaSyBhirp...96GWyGL0` (goplaces, redacted, see `/tmp/secrets-audit.md`)
   - `AIzaSyCduQ...fXEY4GU` (nano-banana-pro, redacted, see `/tmp/secrets-audit.md`)
2. **Rotate the Telegram bot token** (also done per your message).
3. **Generate a new Supabase service-role key** in Supabase Dashboard, Settings, API. Paste it into `scripts/.env` in the `SUPABASE_SERVICE_ROLE_KEY` line (the file already has `REPLACE_ME_NEW_SERVICE_ROLE_KEY_FROM_DASHBOARD` waiting for it).
4. **Paste your Karakeep API token** into `ios/ThePerch/Sources/ThePerch/Config/Secrets.xcconfig` in the `KARAKEEP_TOKEN` line (currently `REPLACE_ME_KARAKEEP_TOKEN`).
5. **Apply the DB hardening migration**:
   ```sh
   supabase db push --project-ref <YOUR-PROJECT-REF>
   ```
   Review `supabase/migrations/20260420230000_security_hardening.sql` before applying. After applying, re-run the Supabase advisor from the dashboard to confirm all WARNings resolved.
6. **Enable Leaked Password Protection**: Supabase Dashboard, Authentication, Settings, enable "Leaked Password Protection" (HaveIBeenPwned integration).
7. **Set admin-create-user secrets** (once you have Claudinho's UUID from Authentication, Users):
   ```sh
   supabase secrets set --project-ref <YOUR-PROJECT-REF> \
     ADMIN_USER_UUIDS="<claudinho-uuid>"
   ```
   Verify that `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are already set (they are used by the other edge functions).
8. **Deploy the new edge function**:
   ```sh
   supabase functions deploy admin-create-user --project-ref <YOUR-PROJECT-REF>
   ```
9. **Run the history scrub** after you are sure you want to rewrite history. First rescue any stash you want to keep:
   ```sh
   git stash list
   git stash branch rescued-tangerine stash@{0}   # example
   bash scripts/purge-secrets-from-history.sh
   git push --force-with-lease --all
   git push --force-with-lease --tags
   ```
   Then delete any forks.
10. **Install the pre-commit hook locally**:
    ```sh
    brew install pre-commit
    pre-commit install
    pre-commit run --all-files   # first run, sanity check
    ```

### Recommended but not critical

11. Rotate the legacy Supabase anon JWT (low risk; publishable by design, but hygiene).
12. Open Xcode, build once, and verify the app boots and reads secrets from the xcconfig pipeline. If it fails to find a secret in DEBUG, you will see an `assertionFailure` pointing at `SecretsLoader`.

## PR description draft

Copy this into the GitHub PR when opening `security/audit-2026-04-20` for review.

---

### Summary

Full response to the 2026-04-20 secret-leak incident. Removes the confirmed-leaked secrets from HEAD, establishes a proper secret-management pipeline for the iOS app, Python worker, and Edge Functions, hardens the database (RLS + tightened policies + pinned search_path on six functions), and adds three layers of leak prevention (local pre-commit, CI, and a documented disclosure policy).

Nine commits, one concern each, in this order:

1. Scaffold `admin-create-user` Edge Function (JWT + allowlist + service-role createUser).
2. Remove `supabase/003_bookmarks.sql` (OpenClaw config, wrong repo).
3. Python worker loads Supabase credentials from env with fail-fast guards.
4. Extend `.gitignore`, untrack Xcode user state, add secret templates.
5. Add `SECURITY.md`, pre-commit gitleaks hook, CI secrets scan workflow.
6. Add history scrub script (documented, not run).
7. Wire `Secrets.xcconfig` → `Info.plist` → `SecretsLoader` pipeline.
8. Add python-dotenv loader and `requirements.txt` for the worker.
9. DB hardening migration (RLS + tightened policies + pinned search_path).

### Test plan

- [ ] Open the project in Xcode. Build succeeds. Confirm `Info.plist` entries resolve to values at build time (no literal `$(NAME)` strings).
- [ ] Launch the iOS app. Confirm it connects to Supabase using the xcconfig-sourced key (existing Secrets.plist still works as fallback).
- [ ] `python3 -m pip install -r scripts/requirements.txt && python3 scripts/orders_autopilot_ingest_fastmail.py --limit 1`. Confirm the worker loads `.env`, authenticates to Supabase, and exits cleanly.
- [ ] `brew install pre-commit && pre-commit install && pre-commit run --all-files`. Confirm no findings.
- [ ] In a fresh clone, apply the migration against a throwaway Supabase project (`supabase db push`), then run the Supabase security advisor. Confirm all ERRORs and the five function WARNs resolve.
- [ ] Open the `admin-create-user` function README and confirm the allowlist + deployment instructions are runnable as-is.
- [ ] Check GitHub Actions: the `secrets-scan` workflow runs on this PR and completes green (after history scrub).
- [ ] Run `bash scripts/purge-secrets-from-history.sh` in a mirror clone, confirm the target literals disappear, then apply to the real repo and force-push.

### Out of scope

- Rotating external secrets (done out of band, see commit messages).
- Enabling Leaked Password Protection (dashboard setting, linked in `SECURITY_AUDIT.md`).
- Deleting forks of the public repo (manual GitHub action).

---

## Dashboard-only action checklist

- [ ] Supabase, Settings, API: generate a new service-role key if you have not already. Paste into `scripts/.env`.
- [ ] Supabase, Authentication, Settings: enable **Leaked Password Protection**.
- [ ] Supabase, Authentication, Users: copy Claudinho's UID. Feed into the `supabase secrets set ADMIN_USER_UUIDS=...` command.
- [ ] Supabase, Advisors, Security: re-run after applying the migration; confirm zero ERRORs and the five mutable-search-path WARNs are gone.
- [ ] GitHub, repo settings: enable secret scanning + push protection if not already on (the same gitleaks pass runs in CI too, but GitHub's native scanning catches known-provider patterns server-side).
- [ ] GitHub, Forks tab: note every fork. Delete or contact owner after history scrub.
- [ ] Google Cloud Console, APIs & Services, Credentials: confirm the rotated goplaces and nano-banana-pro keys replace the leaked ones.
- [ ] BotFather (Telegram): confirm the new bot token is active; revoke the old one if not already done.

## Files touched

| Path | Change |
|---|---|
| `.gitignore` | Rewritten |
| `.github/workflows/secrets-scan.yml` | New |
| `.pre-commit-config.yaml` | New |
| `SECURITY.md` | New |
| `SECURITY_AUDIT.md` | New (this file) |
| `ios/ThePerch/Info.plist` | Added `$(VAR)` entries |
| `ios/ThePerch/Sources/ThePerch/Config/AppConfig.swift` | Removed hardcoded publishable key |
| `ios/ThePerch/Sources/ThePerch/Config/Secrets.example.xcconfig` | New |
| `ios/ThePerch/Sources/ThePerch/Config/Secrets.xcconfig` | New, gitignored |
| `ios/ThePerch/Sources/ThePerch/Config/SecretsLoader.swift` | New |
| `ios/ThePerch/ThePerch.xcodeproj/project.pbxproj` | Added xcconfig references + base configuration on main app target |
| `scripts/.env` | New, gitignored |
| `scripts/.env.example` | New |
| `scripts/orders_autopilot_ingest_fastmail.py` | Env vars + dotenv loader |
| `scripts/purge-secrets-from-history.sh` | New |
| `scripts/requirements.txt` | New |
| `supabase/003_bookmarks.sql` | Deleted |
| `supabase/functions/admin-create-user/index.ts` | New |
| `supabase/functions/admin-create-user/README.md` | New |
| `supabase/migrations/20260420230000_security_hardening.sql` | New, not applied |
| `ios/ThePerch/ThePerch.xcodeproj/.../UserInterfaceState.xcuserstate` | Untracked |
| `ios/ThePerch/ThePerch.xcodeproj/.../xcschememanagement.plist` | Untracked |

## Notes left in the audit report

`/tmp/secrets-audit.md` (generated during the run, not committed since it holds raw secret metadata) contains the full per-secret classification table with commit SHAs and recommended actions.
