# Shareability pass — wrap-up

**Session date:** 2026-04-20 → 2026-04-21
**Branch:** `main`, 5 commits ahead of `origin/main`
**Status:** iOS build passes. Dashboard-sync TypeScript builds. Repo is still private. Ready for your review.

---

## What changed — at a glance

Five commits, readable in order:

1. `d924fdb` — **shareability design spec** (`docs/superpowers/specs/2026-04-20-shareability-design.md`)
2. `9acb741` — **archive internal review/plan docs** under `docs/archive/` (13 files out of the root)
3. `e42d717` — **remove personal data** from tracked files (Secrets.plist untracked, AppConfig cleaned up, personal-data migrations moved out of `supabase/migrations/`)
4. `12ba9e5` — **genericize personal data + remove stray config** (placeholders across skills, script env vars, seed replaced, misplaced openclaw.json config removed)
5. `01f4dcd` — **newcomer docs + per-skill install/contract + iOS cleanup** (README / SHARE / AGENT_BOOTSTRAP / per-skill INSTALL.md + CONTRACT.md / stale iOS dev notes archived)

---

## ⚠️ Things you need to do before going public

### 1. Rotate a leaked service role key (HIGH PRIORITY)

I found a real Supabase **service role key** hardcoded in `scripts/orders_autopilot_ingest_fastmail.py` (line 24):

```
sb_secret_***REDACTED***
```

I replaced it in the current file with `os.environ.get(...)`. **But the key is still in your git history** (every commit before `12ba9e5`). If you make the repo public, anyone can fetch the full history and extract it.

**What to do:**
1. Log into Supabase → Settings → API → regenerate the service_role key for the project at `<YOUR-PROJECT-REF>.supabase.co` ( the old `cgmaotzmeoiueyzlchaz` one).
2. Update any tooling that used the old key (your cron scripts, local env files).
3. Either accept the history leak (the key is now invalid anyway) or rewrite history with `git filter-repo` before pushing public.

I did not run `git filter-repo` for you — history rewrites are your call.

### 2. Review the three new top-level docs

- [`README.md`](../README.md) — rewritten for newcomers. Make sure the tone matches your voice.
- [`SHARE.md`](../SHARE.md) — canonical install guide. Three paths. Check the step counts against reality.
- [`AGENT_BOOTSTRAP.md`](../AGENT_BOOTSTRAP.md) — paste-to-your-agent prompt. The tone is deliberately prescriptive (you're instructing another LLM). If that doesn't feel right, soften it.

### 3. Flip the repo to public when you're ready

Command when you are:

```bash
gh repo edit faresende/ThePerch --visibility public --accept-visibility-change-consequences
```

You may want to add a LICENSE file first (README says "TBD — a permissive open-source license will be added before the repo goes public"). MIT or Apache-2.0 are the usual picks.

### 4. Later: set up TestFlight

[`ios/TESTFLIGHT.md`](../ios/TESTFLIGHT.md) is a placeholder that lists the exact work. You'll need your Apple Developer membership active and about 20 minutes in App Store Connect.

---

## What I did NOT touch

- **iOS app source code** (beyond AppConfig.swift, KarakeepService.swift, EventCard.swift preview string, and ShareExtensionView.swift comment). No feature changes.
- **Supabase schema migrations.** Moved two personal-data migrations out of the sequence, but the schema itself is unchanged.
- **Any tests.** If you have a test suite, run it.
- **Your local `~/.openclaw/skills/` copies.** These are installed runtime copies, outside the repo. They're likely now out of date relative to `skill/` in the repo — if your agents depend on the installed versions, you may want to re-copy them.
- **Skill code (`skill/dashboard-sync/src/*.ts`)** beyond removing the hardcoded Fabio user ID fallback. I did not touch `email-classifier.ts`, `bookmark-watcher.ts`, etc.

---

## Design decisions captured

All 8 questions you answered are in the spec: [`docs/superpowers/specs/2026-04-20-shareability-design.md`](./superpowers/specs/2026-04-20-shareability-design.md). If anything there doesn't match what you had in mind, the spec is the place to contest it before the work gets used.

---

## Repo shape after this pass

```
ThePerch/
├── README.md             ← NEW: newcomer-focused
├── SHARE.md              ← NEW: canonical install guide
├── AGENT_BOOTSTRAP.md    ← NEW: paste-to-your-agent
├── GETTING_STARTED.md    ← trimmed, points at SHARE.md
├── CHANGELOG.md
├── .env.example          ← NEW: all env vars documented
├── ios/
│   ├── ThePerch/         ← only ARCHITECTURE.md + code here now
│   ├── TESTFLIGHT.md     ← NEW: placeholder for later
│   └── ...
├── skill/
│   └── perch-*/          ← each has SKILL.md + INSTALL.md + CONTRACT.md
├── supabase/
│   ├── 001_initial_schema.sql
│   ├── 002_seed_demo.sql       ← replaces 002_seed_fabio.sql
│   ├── migrations/             ← personal-data migrations moved out
│   └── personal-data/          ← NEW: one-off historical scripts
├── docs/
│   ├── agent-prompts.md  ← renamed from claudinho-prompts.md
│   ├── archive/          ← historical review/plan docs
│   └── superpowers/      ← specs and plans
```

---

## Smoke tests I ran

- `xcodebuild ... build` against `ThePerch.xcodeproj`, Debug, iphonesimulator → **BUILD SUCCEEDED**.
- `cd skill/dashboard-sync && npm run build` (tsc) → **clean**.
- `git grep` for known key patterns and personal identifiers → **no matches in active paths** (only intentional mentions in `docs/archive/` and `supabase/personal-data/`).

## Smoke tests I did NOT run

- Unit tests (if they exist in the Xcode project or in `skill/dashboard-sync`).
- A live round-trip through Supabase with a test user (would need your credentials).
- The orders autopilot pipeline end-to-end.

---

## If you want to keep going

- **License.** Pick MIT or Apache-2.0 and commit it as `LICENSE`.
- **Issue templates.** Add `.github/ISSUE_TEMPLATE/` with a bug-report + feature-request template.
- **Contributing guide.** `CONTRIBUTING.md` at root describing how to propose a new skill, how to test changes, etc.
- **A short demo video or GIF** in the README. Static screenshots exist but a 30-second loop would land harder.
- **Skill verification CI.** A GitHub Action that checks every `skill/*/` has `SKILL.md`, `INSTALL.md`, `CONTRACT.md` and that required frontmatter fields are present.

None of these are blockers for making it public. They're polish.
