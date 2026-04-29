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
- `002_seed_demo.sql` ships generic agent IDs (main / health / calendar / orders / legal) and a Demo User display name
- DEBUG mock orders in `OrdersService.swift` swapped real-looking tracker numbers for synthetic placeholders
- 13 byte-identical root-level docs (`DESIGN_REVIEW.md`, `PLAN.md`, `WORKLOG.md`, etc.) deleted; canonical copies remain in `docs/archive/`

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

[Unreleased]: https://github.com/faresende/ThePerch/compare/build/43...HEAD
[Build 43]: https://github.com/faresende/ThePerch/compare/build/42...build/43
[Build 42]: https://github.com/faresende/ThePerch/releases/tag/build/42
