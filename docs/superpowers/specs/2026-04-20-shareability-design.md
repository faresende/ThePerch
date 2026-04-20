# The Perch — Shareability Design

**Date:** 2026-04-20
**Author:** Drafted with Claude (approved decisions by Fábio)
**Status:** Approved, implementation in progress

## Goal

A newcomer can go from "I heard about The Perch" to a working dashboard in about 30 minutes, picking whichever skills they want, using setup instructions they can paste into their own agent (OpenClaw, Claude Code, or any CLI).

## Non-Goals

- TestFlight setup (requires Fábio's Apple Developer account; deferred)
- npm publishing of skills (copy-paste install is the chosen packaging)
- Landing page / marketing site
- Changes to iOS app source code (this pass is docs + skills only)
- Making the repo public (Fábio will flip it manually after review)

## Approved Decisions

Captured from the brainstorming Q&A on 2026-04-20:

| Decision | Choice |
|---|---|
| iOS distribution | Source-build now, TestFlight later (placeholder doc) |
| Skill runtime | Runtime-agnostic: OpenClaw + Claude Code + plain CLI |
| Personal data | Replace with generic template; strip Fábio-specific values |
| Scope | MVP + skills polish pass |
| Repo visibility | Stays private; Fábio flips it later |
| Personal integrations | Make pluggable (providers/ folder, generic contract) |
| Skill packaging | Directory per skill, copy-paste install |
| Repo root clutter | Archive old review/plan docs under docs/archive/ |

## Architecture

```
Repo root
├── README.md              # Rewritten for newcomers
├── SHARE.md               # Canonical "share with a friend" install guide
├── AGENT_BOOTSTRAP.md     # Paste-to-your-agent setup prompt
├── GETTING_STARTED.md     # Trimmed; points at SHARE.md
├── .env.example           # All env vars a user might need
├── supabase/
│   ├── 001_initial_schema.sql
│   ├── 002_rls_policies.sql         # Extracted (or retained) from current schema
│   └── 003_seed_demo.sql            # Generic replacement for 002_seed_fabio.sql
├── skill/
│   └── perch-<name>/
│       ├── SKILL.md         # Runtime-agnostic; YAML frontmatter compatible with OC + CC
│       ├── INSTALL.md       # Three install blocks
│       ├── CONTRACT.md      # Supabase schema the skill reads/writes
│       ├── providers/       # example.* reference implementations (pluggable integrations)
│       ├── scripts/         # runtime-agnostic node/python scripts
│       └── README.md
├── ios/
│   ├── (unchanged source)
│   └── TESTFLIGHT.md        # Placeholder for future TestFlight link
└── docs/
    ├── archive/             # Old review/plan docs move here
    └── superpowers/specs/   # This spec lives here
```

## Core Shapes

### INSTALL.md (per skill)

Each skill's INSTALL.md has three blocks:

1. **OpenClaw** — `cp -r skill/perch-<name> ~/.openclaw/skills/` plus any required env vars.
2. **Claude Code** — `cp -r skill/perch-<name> ~/.claude/skills/` plus any required env vars.
3. **Plain CLI / bring your own agent** — `cd skill/perch-<name> && npm install && node scripts/<entry>.js --help`.

All three blocks reference the same underlying scripts; the difference is only discovery/invocation.

### CONTRACT.md (per skill)

Describes, without prescribing a data source:

- Which Supabase tables the skill reads/writes.
- The exact JSON payload shape for `data` field in `dashboard_records` (keys, units, types).
- Required and optional fields.
- Any timezone / formatting rules (e.g., ISO-8601 with explicit offset).

Purpose: a user with a different data source (any sleep tracker, any IMAP provider) can plug it in without guessing the contract.

### providers/ (per skill, where applicable)

- `providers/oura.example.js` (for perch-health)
- `providers/fastmail-jmap.example.js` (for perch-orders)
- `providers/meal-tracker.example.js` (for perch-nutrition)

These are illustrative adapters. The skill's scripts call a `Provider` interface; the example files show how to wire a specific one.

### AGENT_BOOTSTRAP.md

A single markdown file a user pastes into any coding agent chat:

> "Set up The Perch for me. Here is the repo: <url>. My Supabase project URL is <X> and service role key is <Y> (in $HOME/.theperch/credentials). Install these skills: [health, calendar]. Follow the INSTALL.md in each skill directory."

The file is written so that reading it gives the agent everything needed: repo layout, install locations, env var names, verification commands, where to report errors.

### SHARE.md

Canonical install guide. Three paths:

1. **Just the iOS app** — clone, open in Xcode, build. No backend needed if you run against demo data (future).
2. **Full self-host** — Supabase project + migrations + iOS app + pick-and-install skills.
3. **Guided by an agent** — paste AGENT_BOOTSTRAP.md into your agent, answer its questions.

## Migration from Current State

| Current | After |
|---|---|
| README.md is the skill-ecosystem overview | README.md is "what is The Perch" for a newcomer; skill-ecosystem overview moves inline into SHARE.md |
| `supabase/002_seed_fabio.sql` with Fábio's UUID | `supabase/003_seed_demo.sql` with placeholders + demo agent set |
| `claudinho-prompts.md` at root with hardcoded URL and UUID | Rewritten; placeholders `<YOUR_SUPABASE_URL>` and `<YOUR_USER_UUID>` |
| `ios/ThePerch/CLAUDINHO-SUPABASE-SETUP.md` with hardcoded values | Genericized |
| `DESIGN_REVIEW.md`, `DESIGN_REVIEW_V2.md`, `PLAN.md`, `PLAN_M2.md`, `WORKLOG.md`, `PERF_REVIEW.md`, `SWE_REVIEW.md`, `FOUNDATION_SUMMARY.md`, `IMPLEMENTATION_CHECKLIST.md`, `HOME_REDESIGN.md`, `FILE_MANIFEST.md`, `PRODUCT_REVIEW.md`, `PERFORMANCE_AUDIT.md` at root | All moved to `docs/archive/` |
| Skills reference "BioChecha", "weekly-med", "Fastmail", "Oura" by name in SKILL.md | Skills describe the contract; provider-specific details move to `providers/<name>.example.<ext>` |

## Error Handling & Edge Cases

- **Secret scan**: before each commit, grep for known leaked patterns (sk-, SUPABASE URLs other than placeholders, UUIDs matching Fábio's user UUID). If anything surfaces, stop and flag.
- **Build verification**: run `xcodebuild ... build` on the iOS app after the doc/rename changes to confirm no path references broke.
- **Skill smoke test**: for at least one skill (`dashboard-sync`), run `node cli.js --help` (or equivalent) to confirm the scripts still execute.
- **Backward compat**: the file rename `002_seed_fabio.sql` → `003_seed_demo.sql` must be accompanied by docs referencing the new name. Keep the old filename as a broken link only if references are tracked down.

## Testing Plan

1. After all changes: clean git status, verify archive directory contents, verify no references to the old seed filename remain (`git grep 002_seed_fabio`).
2. Grep for Fábio's known values (`cgmaotzmeoiueyzlchaz`, the specific UUID, `biochecha`, `weekly-med`, `fastmail`) in tracked files; confirm only appear in `docs/archive/` and `providers/*.example.*`.
3. xcodebuild verification on iOS app.
4. dashboard-sync smoke test: `cd skill/dashboard-sync && node cli.js --help` runs without error.

## Commit Strategy

Logical chunks, each independently reviewable:

1. `chore: archive internal review/plan docs under docs/archive`
2. `feat: add runtime-agnostic INSTALL.md + CONTRACT.md per skill`
3. `refactor: genericize personal integrations into providers/ pattern`
4. `feat: replace Fábio-specific seed with generic demo seed`
5. `docs: rewrite README for newcomers; add SHARE.md + AGENT_BOOTSTRAP.md`
6. `docs: scaffold ios/TESTFLIGHT.md placeholder`
7. `chore: add .env.example with all user-facing env vars`

## Rollback

All work is additive or moves-only. If any step goes wrong, `git reset --hard HEAD~N` reverts; no state is lost because the repo is fully tracked.

## Open Questions for Future Work (Not This Pass)

- TestFlight setup (needs Apple Developer account steps).
- Whether to publish skills to npm eventually.
- Landing page / marketing site.
- Whether the iOS app should ship with a "demo mode" that works without Supabase.
- Multi-user Supabase tenancy story (currently single-user per project).
