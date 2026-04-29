# Changelog

All notable changes to The Perch (iOS app, agents, dashboard-sync skill, Supabase schema) are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added — Time-aware insights
- Six-slot insight architecture: pre-wake `morning` (forward-looking plan-of-day), `midday` (anticipatory), `afternoon` (gap-aware opportunity), `evening` (recap), `morning_post_wake` (retrospective + body-comp delta, watcher-fired), `event_logistics` (17track-fired on out-for-delivery / ETA-today)
- `agents/health-integrations/biochecha_dynamic_insight.py` — rule-engine + LLM voice; ranker with category priority + quiet-day fallback; 9 base categories
- `biochecha_post_wake_insight.py` — fires on InBody CSV ingest, generates iOS card + long-form Telegram briefing
- `biochecha_event_insight.py` — fires from `pollAndUpdateShipment` on shipment status flips
- `_telegram_client.py` — stdlib-only Bot API client reading bot token from openclaw config
- iOS `Insight.Kind` enum gains `dailyHealthMorning`, `dailyHealthMorningPostWake`, `dailyHealthMidday`, `dailyHealthAfternoon`, `dailyHealthEvening`, `eventLogistics`
- iOS `fetchTodayDailyInsight` now picks the latest BioChecha row regardless of slot

### Added — InBody H30 watcher
- `agents/health-integrations/inbody_ingest.py` — parses InBody H30 CSVs to 22 metrics, dedupe by measurement timestamp
- `agents/health-integrations/inbody_backfill_from_json.py` — one-shot historical scan import from legacy `body-composition.json`
- `scripts/inbody-watch-tick.sh` + `scripts/install-inbody-watcher.sh` + `ops/launchd/com.theperch.inbody-watcher.plist.template` — polling-watcher install
- `agents/health-integrations/calendar_sync.py` — macOS Calendar.app → `dashboard_records` for opportunity-based insight categories

### Added — Source-of-truth precedence
- Body composition: InBody > Withings (when both have data for the same day, higher-priority source wins; lower fills gaps)
- Sleep: Oura > 8sleep
- New `oura_ingest.py` reads sleep + daily sleep score + readiness via Oura Cloud API v2

### Added — Phase 2 corrections-and-rules (auto-promoted merchant rules)
- `merchant_rules` table + RLS policies + `auth.uid()`-guarded `apply_merchant_rule` and `promote_merchant_rules` SECURITY DEFINER RPCs (service-role bypass for the autopilot)
- iOS Settings → Auto-learned rules (with 30s in-memory TTL cache)
- TS `merchant-rules.ts` lookup wired into `processEmail` short-circuit slot

### Added — Rage-shake feedback loop (Phase 5)
- `insight_feedback` table + RLS
- iOS shake detector + feedback sheet (auto-pre-fills with active insight)
- Few-shot injection of recent feedback into LLM prompts via `_gather_recent_feedback`

### Added — Operational
- `agent_runs_non_ok_idx` partial index + `prune_agent_runs(days)` SECURITY DEFINER RPC (service-role only) + 04:00 daily cron
- `_supabase_client.py` auto-registers agents in `public.agents` on first `insert_agent_run`

### Changed — Performance
- Backend: `gather_state` parallelizes its 7 Supabase reads via `ThreadPoolExecutor`
- iOS: `preDecodeRecords` runs `nonisolated` on `Task.detached` — no main-thread freeze on fetch
- iOS: `InsightsService` + `MerchantRulesService` decode array directly via `FailableDecodable<T>` (killed JSONSerialization round-trip)
- iOS: shared `PerchFormatters.iso8601` replaces 8 per-call `ISO8601DateFormatter()` rebuilds
- iOS hero MP4s re-encoded (26.7 MB → 4.4 MB) and `PaperTexture` 2048² → 1024² (5.4 MB → 0.25 MB) — total 27 MB binary slim
- iOS hero video pipeline async via `Task.detached` (poster image renders immediately)
- Cron jobs: 9 ingest + insight jobs migrated to `lightContext: true` + `toolsAllow: ["exec"]` + `zai/glm-5` + NO_REPLY pattern

### Changed — Other
- Default InBody watch directory now `~/Documents/InBody` (override via `INBODY_WATCH_DIR` env)
- `OrdersView` warm-hydrates from `DashboardViewModel.trackedOrders` when available

### Security
- Pre-public scrub: deleted classifier-test fixtures (carried real Fastmail PII + live Shopify customer-auth tokens), removed maintainer-personal screenshots from `docs/Images/` and `docs/screenshots/`, scrubbed personal prescription identifiers from design docs, rewrote `SECURITY.md` to match actual prevention tooling, locked `prune_agent_runs` to `service_role` only
- Templated `ops/launchd/com.theperch.inbody-watcher.plist` (was hardcoded user paths) + `scripts/install-inbody-watcher.sh` renderer
- App Store Connect API identifiers (`KEY_ID`, `ISSUER`) now read from env in `deploy-testflight.sh`
- `002_seed_demo.sql` ships canonical agent IDs (`main`, `biochecha`, `calendario`, `entregas`, `legal` — kept as project-internal identifiers referenced throughout the iOS + Python code) with neutral user-visible display names (`Main`, `Health`, `Calendar`, `Orders`, `Legal`) and a `Demo User` display name on the seed user
- DEBUG mock orders in `OrdersService.swift` swapped real-looking tracker numbers for synthetic placeholders
- 13 byte-identical root-level docs (`DESIGN_REVIEW.md`, `PLAN.md`, `WORKLOG.md`, etc.) deleted; canonical copies remain in `docs/archive/`
- **Round 7**: hardened `handleIncomingAuthURL` with scheme/host/path/type allowlist + already-signed-in guard so server-controlled URL fields (bookmark.url, shipment.tracking_url) can't trigger session swaps via `theperch://` deeplinks
- **Round 7**: explicit `user_id = auth.uid()` filter added to `fetchRecords` / `fetchSections` / `fetchHomeWidgets` (defense-in-depth on top of RLS); R7 + R8 unified the existence-oracle errors so `cancel_order_correction` / `apply_merchant_rule` etc. return identical "not accessible" messages whether the row is missing or owned by another user
- **Round 8**: removed the recovery-flow carve-out from `handleIncomingAuthURL` — ALL flows now refuse to clobber an existing session (closes a session-fixation chain through `theperch://auth/callback?type=recovery#access_token=ATTACKER` URLs)
- **Round 8**: `idle_in_transaction_session_timeout = 60s` set at DATABASE + `authenticator` (login) role level; R7's setting on `authenticated`/`anon` was a no-op since both are nologin roles
- **Round 8**: `sanitizeForPrompt` regex in `skill/dashboard-sync/src/llm-extractor.ts` rebuilt with explicit `RegExp` constructor + unicode escape strings — the prior literal `/[<unicode>]/g` had collapsed to `/[ -]/g` (just space + hyphen) at commit time, silently disabling control-char + zero-width stripping
- **Round 8**: `dashboard_records` CREATE TABLE added to `supabase/001_initial_schema.sql` (4 later migrations referenced it without it being created); `002_seed_demo.sql` gained an `IF NOT EXISTS auth.users` guard so fresh installs no longer FK-violate before the user is created
- **Round 8**: rewrote `ops/cron-jobs.example.json` to invoke python directly (the prior payloads referenced wrapper scripts that don't exist in the repo)
- **Round 9**: committed missing migration `20260429810000_round9_repo_state_sync.sql` for state that had been applied to prod via dashboard but never landed in `supabase/migrations/` — `idle_in_transaction_session_timeout` at DATABASE + login-role level, `public.bookmarks` table + RLS + indexes (referenced by the Safari extension and iOS but never created by any committed migration), `rls_auto_enable` event-trigger function (defense-in-depth that auto-enables RLS on every new public-schema table)
- **Round 9**: `prune_email_classifications` 7-day floor guard added to mirror `prune_agent_runs` — refuses `days < 7` so a service-role compromise can't one-call wipe email classification history
- **Round 9**: Safari extension `popup.js` `showStatus` rewritten with `createElement` instead of `innerHTML` interpolation — the prior path interpolated server-controlled response text into the popup's innerHTML, an XSS surface in an origin with chrome.storage + chrome.tabs access
- **Round 9**: `eight_sleep_ingest.py` no longer leaks the full OAuth response into `RuntimeError(...)` (which gets persisted to `~/.openclaw/logs/`); now reports only the response's keys
- **Round 9**: nutrition-copilot edge function now sanitizes user-supplied meal text and correction text with the same C0/C1-control + zero-width-char strip as `llm-extractor.ts`, and wraps user input in explicit `<user-input>` delimiters
- **Round 9**: ungated `print` in `SupabaseService.swift` (no-active-session catch) wrapped in `#if DEBUG` to match the rest of the file's release-log discipline
- **Round 9**: dead `keychain-access-groups` entitlement removed (the Share Extension that justified it was deleted in R8)
- **Round 9**: `001_initial_schema.sql` `display_hint` default aligned with prod (`'card'` → `'single_value'`)

---

## [Build 74] - 2026-04-29

The latest tagged build before the public flip. Comprehensive
pre-public hardening (security, perf, docs) ran across Rounds 1–6 in
the Unreleased section above. The "Build 43" / "Build 42" entries
below pre-date that work and document an earlier release lane that
was never published as a Git tag (build/42 / build/43 were renumbered
when the build pipeline switched to the current `CURRENT_PROJECT_VERSION`
scheme — current value is 102).

---

## [Build 43] - 2026-03-18

### Fixed
- Push section content below floating pill bar
- Compile error in WorkoutView and push local changes
- Reduce triple card shadow to single (eliminates flicker on tab switch)
- Travel home card header uses suitcase icon (not airplane, avoids double plane)
- Heartbeat card status color (green/amber/red based on age)
- Calories header wrapping + shorten freshness labels
- Sleep score bar track now visible (was same color as card bg)
- Chip strip: smaller emoji, tighter spacing, proper vertical centering
- Chip strip fills width, 3 chips visible without cropping
- Chip strip uses cardStyle, removed fixed height, consistent borders
- Remove double padding on chip strip (align with other cards)
- Calendar event time labels wrapping vertically
- Add unknown record type fallback, fix calendar_event decoding, fix greeting
- Shorten stale data label (remove verbose 'Data may be outdated')
- Glass header extends to top edge, fix tab switch lag
- Full-width glass header bar (no rounded corners on sides)
- Layer ultraThinMaterial under glassEffect for visible translucency
- Resilient decoding for Supabase records (P0)
- Calorie and Workout tab bugs (P0)
- Sort daily records by updatedAt desc to capture intraday updates (P0)

### Added
- Workout cards + fix connection error persistence
- Chip strip replacing summary card (glanceable 3-chip quick view)
- Liquid Glass card treatment + glass header (Sprint 7)
- Travel feature (Sprint 1–3) + chart fixes + calories logic
- Travel tasks: pre-trip checklist + inline day tasks
- New app icon: P with subtle bird negative space, layered Liquid Glass variant
- SF Symbol leading icon to segment cards

### Changed
- Sleep & recovery card redesigned: score hero, kill rings, inline metrics
- Design audit fixes: all criticals + warnings
- Segment cards redesigned: remove tag pills, use status dots (card layout v3)
- Travel timeline: hotel split, names, type tags, weather condition display
- Inline day tasks moved before segment cards instead of after
- Code quality cleanup (Sprint 6)
- Admin safety + polish (Sprint 5)
- Calendar upgrade (Sprint 4)
- Missing states (Sprint 3)
- Visual consistency (Sprint 2)
- Crash prevention + auth foundation (Sprint 1)

### Removed
- Summary card (replaced by chip strip)
- Triple card shadow (replaced with single shadow)

---

## [Build 42] - 2026-02-XX

_Pre-changelog. See git history for details._

---

[Unreleased]: https://github.com/faresende/ThePerch/compare/build/74...HEAD
[Build 74]: https://github.com/faresende/ThePerch/releases/tag/build/74
[Build 43]: https://github.com/faresende/ThePerch/tree/main/CHANGELOG.md#build-43---2026-03-18
[Build 42]: https://github.com/faresende/ThePerch/tree/main/CHANGELOG.md#build-42---2026-02-xx
