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
- **Round 10**: dropped `bookmarks.fts tsvector` column + `idx_bookmarks_fts` GIN index — both were created in R9 but had no populator (no trigger, no GENERATED expression) and no consumer; dead column + pure write-amp index
- **Round 10**: prompt-injection wrapper bypass closed in both `dashboard-sync/llm-extractor.ts` and `nutrition-copilot/llm.ts` — `sanitizeForPrompt` now replaces `<` and `>` with full-width forms so a user typing `</user-input>` or `</email_body>` literally can't close the wrapper and inject directives
- **Round 10**: `insertRecord` error path in `SupabaseService.swift` wrapped in `#if DEBUG` (the only ungated print left after R9); PostgREST FK-violation messages can include row column values
- **Round 10**: realtime listener tasks now tracked PER-CHANNEL (`recordsTasks`/`agentsTasks`) so a re-subscribe that removes the channel correctly cancels the dead listener tasks instead of leaking them into the global `realtimeTasks` array
- **Round 10**: `prune_email_classifications` 7-day floor guard added in R9 was correct — R10 added a public.bookmarks `REVOKE ALL ... FROM anon` defense-in-depth statement (RLS already denies anon, but the table-level GRANT inherited from the Supabase template was not explicitly revoked)
- **Round 10**: `eight_sleep_ingest._login` HTTPError no longer interpolates response body into the exception message (it could echo the email back on 401/429); now reports the status code only
- **Round 10**: stub migrations committed for `20260429165022_round7_idle_in_transaction_timeout` + `20260429170724_round8_idle_tx_timeout_at_login_role` so `supabase db push` against prod doesn't refuse for "missing migration files" — the prod ledger references both

### Performance — Round 10
- iOS: `DashboardViewModel.subscribeToAgents` callback now goes through `scheduleDebouncedAgentsRefresh` — the prior path called `loadAgents(forceRefresh: true)` directly per realtime tick, so a 5-agent burst at the 7am cron tick fired 5 sequential HTTP round-trips on the main actor
- iOS: `mergeRealtimeChange` UPDATE path uses **synchronous** `preDecodeRecords` for the single updated record (was async detached), so `DecodingCache` is hot before SwiftUI body invalidation fires — closes a real correctness bug where realtime UPDATEs showed the prior value until the next cold load
- iOS: `WorkoutsSegment` no longer maintains a private `HealthViewModel` instance; reads directly from `dashboardViewModel.healthRecords` (eliminates a duplicate `recomputeMetricCaches` pass per realtime tick)
- iOS: `NutritionHomeCard` now uses the same `Snapshot`-via-Hashable-`Fingerprint` pattern that R9 introduced for `HealthSummaryHomeCard` — collapses 5+ redundant filter+map+filter+reduce passes per body render
- iOS: `CalendarTodayCard` got the same Snapshot pattern (5+ passes → 1)
- iOS: `CalendarSectionContent` (HubTab) coalesced its two `.onChange(of:)` handlers (`calendarRecords` + `eventKitEvents`) behind a single Hashable fingerprint, plus cached `dayEvents` so the four body-side reads hit a single pre-filtered array
- iOS: `NutritionViewModel.loadMeals` now equality-checks before assigning to `meals` — the didSet has no built-in short-circuit and unconditional reassignment was firing `recomputeDaySections` on every realtime tick even when the meal set was unchanged
- iOS: `NutritionViewModel.loadMeals` target-context gate tightened — used to fire on any meal that had `asMacros() != nil` (i.e., every meal), so a meals-only batch from `refreshMeals` overwrote `targetSourceRecords` with rows that lacked the user's daily target. Now requires explicit `daily_calories` measurement OR `display_hint=macros_bar` records
- iOS: `TravelHomeCard` no longer writes to the (R9-hoisted) shared `TravelViewModel.records` — HubTab is the canonical writer with the right cadence; the card's redundant write was firing `recomputeTrips` on every full-records change
- iOS: `loadEventKitEvents` now equality-checks before assigning to `eventKitEvents` (`@Observable` doesn't equality-check on its own; cold start + every scenePhase=active foreground was triggering Calendar*Card body re-renders even when the device's calendar was unchanged)
- iOS: dead `weightRecords` computed property removed from `HealthViewModel`; dead `HealthSummaryCard.swift` (215 LOC, only referenced by its own #Preview) deleted
- iOS: `LazyView` doc corrected — the prior comment claimed it deferred building inside `TabView(.page(...))`, which it doesn't (paged TabView eagerly evaluates page bodies for swipe preview). The wrapper is a passthrough; kept only to avoid touching the ~6 call sites

### Security — Round 11 (final pre-public round)
- **R11 CRITICAL** TravelHomeCard cold-launch regression: R10 dropped the `records → travelVM.records` writes from the card on the assumption that HubTab's writer would feed the shared (R9-hoisted) TravelViewModel. But a user who lives on TodayTab and never visits Hub got an empty `travelVM.currentTrip` → the trip banner never appeared. Hoisted the write into `ThePerchApp.MainTabView` via `.onChange(of: dashboardViewModel.travelRecords)` plus a one-shot seed in the auth-state `.task`. TravelViewModel.records.didSet gained an equality short-circuit so the redundant HubTab writer is harmless.
- **R11 CRITICAL** migration ledger drift closed: 8 prod migration versions had no local file (`prune_agent_runs_and_drop_legacy_orders_cols`, `restore_order_number_column`, `active_shipments_view`, `prune_agent_runs_lock`, `dashboard_records_indexes_v2`, `replica_identity_default`, `fix_rls_recursion_agents`, `round10_drop_bookmarks_fts_dead_code`). All committed as idempotent stub files matching the prod versions exactly so `supabase db push` against the prod project no longer refuses for "missing migration files." Fresh installs replay the same end state because every statement is `CREATE OR REPLACE` / `CREATE INDEX IF NOT EXISTS` / `ALTER TABLE ... DROP COLUMN IF EXISTS` / etc.
- **R11 HIGH** added `ios/ThePerch/PrivacyInfo.xcprivacy` declaring `NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1`, used by `@AppStorage` + `UserDefaults(suiteName:)` for widget data sync) and `NSPrivacyAccessedAPICategoryFileTimestamp` (reason `C617.1`, used by `CrashReporter` for "X minutes ago" labels). Apple has been rejecting App Store + TestFlight submissions without a privacy manifest declaring required-reason API usage since iOS 17 (May 2024).
- **R11 MEDIUM** `nutrition-copilot/llm.ts:correctMeal` now sanitizes `original.input_text` / `meal_name` / `analysis_line` before re-injecting them into the LLM prompt. The R10 prompt-injection wrapper fix only sanitized the active-call `correctionText`; the stored fields from a prior `analyze` call carried unsanitized values that re-entered the prompt via `JSON.stringify(original, null, 2)` (which doesn't escape `<` / `>`).

### Performance — Round 11
- iOS: `attemptRealtimeReconnect` agents callback now routes through `scheduleDebouncedAgentsRefresh` — R10's debounce only patched `setupRealtimeSubscriptions`, missed this reconnect path (exactly where bursts are most likely: cellular flap → 5+ buffered agent updates flush at once)
- iOS: `ThePerchApp.scenePhase` `.onChange` gated with `oldPhase == .background` so the cold-start path no longer fires `loadDashboard` twice (once via `.task(id:)`, once via `.onChange(scenePhase: .inactive → .active)`). Saves ~50–100ms of duplicate predecode on every cold launch
- iOS: `SupabaseService.signOut` now calls `await unsubscribeAll()` BEFORE `client.auth.signOut()`. The prior path leaked the records + agents websockets and 4 long-lived listener Tasks per sign-out (until process termination, or until a re-sign-in clobbered them via the `if let existing` branch)
- iOS: `TravelViewModel.records` didSet now equality-short-circuits — the R11 C1 fix introduced a second writer (in `ThePerchApp`), and without the guard both writers' identical assignments would each run `recomputeTrips`
- Docs: `SETUP-FOR-AGENTS.md` cron schedule table aligned with `ops/cron-jobs.example.json` (minute offsets `13`, `3`, `5`, `7`, `9` are deliberate — staggered to avoid openclaw worker-pool lock contention; previously the README table showed canonical-hour times like `0 7`, `0 12` etc.)

After Round 11, the 5-round budget (R7–R11) was nominally exhausted, but extending the audit revealed that diminishing returns hadn't actually been reached.

### Security — Round 12
- **R12 CRITICAL** Widget extension target was missing `PrivacyInfo.xcprivacy`. R11 closed the main app target only; the widget extension reads `UserDefaults(suiteName:)` for widget data sync, which is a required-reason API. App Store / TestFlight rejects the entire IPA when an `.appex` bundle has no privacy manifest. Added `ios/ThePerch/ThePerchWidgets/PrivacyInfo.xcprivacy` declaring `NSPrivacyAccessedAPICategoryUserDefaults` (`CA92.1`) and wired into the widget's Resources build phase.
- **R12 CRITICAL** Migration replay collision: `20260429700000_round6_perf_security_followups.sql` issued bare `CREATE POLICY agents_select_own` / `agent_users_select_own`, but the R11 stub `20260429162035_fix_rls_recursion_agents.sql` already creates them. On a fresh `supabase db push`, the stub runs first (lower timestamp), then R6 fails with `42710 policy already exists`. Postgres 17 doesn't support `CREATE POLICY IF NOT EXISTS`, so added `DROP POLICY IF EXISTS` guards to make this pair idempotent across replay orderings.
- **R12 HIGH** Server-controlled URLs flowed unrestricted into `UIApplication.shared.open` across 8 call sites (HubTab tracking link, HubTab bookmarks, DeliveryCard tracking, SearchView bookmark + delivery, EmailSummaryCard Fastmail, ReviewItemCard Fastmail fallback, UniversalCardFooter action.deepLink, WidgetRouter bookmark). An attacker controlling a Karakeep instance, or whose order-confirmation email gets parsed, could inject `shortcuts://run-shortcut?...` (silent shortcut execution), `mailto:`/`tel:`/`sms:`/`facetime:` (silent compose), or `theperch://auth/callback?...` (re-enter auth flow). New `Views/Helpers/ExternalURLOpener.swift` allowlists `http`/`https` only; all 8 sites routed through it. Locally-constructed `calshow:` and `maps:` URLs (with hardcoded prefix + numeric/encoded payload) keep using direct `UIApplication.shared.open`.
- **R12 HIGH** `nutrition-copilot/correctMeal` re-injection: R11 sanitized `input_text` / `meal_name` / `analysis_line` but `meal_time` and `photo_url` rode through via `...original` unsanitized. iOS clients can PATCH any `dashboard_records.data` field for their own row, so a malicious client could inject prompt directives into either field and have them re-enter via `JSON.stringify(safeOriginal)`. Both fields now stripped from the prompt entirely (the LLM doesn't need either to perform a correction).
- **R12 HIGH** Documented `KARAKEEP_TOKEN` IPA-recovery risk: values from `Secrets.xcconfig` get substituted into `Info.plist` at build time; the resulting IPA contains the literal token, recoverable via `plutil`. For single-user / single-device installs this is the intended trade-off. SETUP-FOR-AGENTS now documents the risk and recommends moving to Keychain (via onboarding) for any multi-device or multi-user fork.
- **R12 MEDIUM** `anon` role retained `arwdDxtm` (full DML+TRUNCATE+REFERENCES) on 22 RLS-enabled public tables and 2 views (`active_shipments_summary`, `agent_runs_latest`) — 24 entries total. RLS denies anon for SELECT/INSERT/UPDATE/DELETE because no policy targets `anon`, but TRUNCATE bypasses RLS in Postgres, and REFERENCES can be used as a row-existence oracle. R10 only revoked anon on `bookmarks`; new migration `20260429900000_round12_revoke_anon_grants.sql` sweeps every public table. Defense-in-depth — doesn't change any working code path.
- **R12 MEDIUM** 21 ungated `print(...)` statements across iOS were emitting to Console.app + sysdiagnose in release builds. Many included `error.localizedDescription` which can carry PostgREST FK-violation column values, partial query strings, etc. All wrapped in `#if DEBUG`. Verified via depth-aware sweep that zero ungated prints remain in `ios/ThePerch/Sources/`.
- **R12 MEDIUM** `signOut` could hang ~60s on a flapping/dead network. R11 had `await unsubscribeAll()` BEFORE `client.auth.signOut()`; `unsubscribeAll` awaits two `client.realtimeV2.removeChannel(...)` calls, each waiting up to ~30s for the server `phx_leave` ack. Sign-out is a security action — must succeed regardless of network. Now races `unsubscribeAll` against a 2s timeout via `withTaskGroup`; whichever finishes first wins. After timeout the websocket gets GC'd anyway when `auth.signOut` invalidates the session.

### Performance — Round 12
- iOS: `NumberFormatter` was being allocated per body render across 6 currency/integer formatting sites (OrderCard.totalText, HubTab.priceText + inFlightLabel, ReviewItemCard.formatCurrency, HealthTab.integerString, OrderItem.displayUnitPrice). NumberFormatter init is heavier than DateFormatter (~50–150µs: locale + currency-symbol resolution); 5–15 currency labels visible on Hub/Today added 0.5–2ms of avoidable main-actor work per re-render. New `PerchFormatters.currency(code:fractionDigits:)` cache keyed on `(code, digits)`; new `PerchFormatters.integer` static formatter. All 6 sites routed through.

### Docs — Round 12
- `SETUP-FOR-AGENTS.md` cron timeouts column aligned with `ops/cron-jobs.example.json` (R11 claimed alignment but didn't — calendar-sync was 60→300, biochecha-* was 600→300, agent-runs-prune was 120→60).
- `SETUP-FOR-AGENTS.md` Step 15 gained a privacy-manifest note pointing to the two `.xcprivacy` files and what to update if integrations are removed/added.
- `SETUP-FOR-AGENTS.md` Step 2 gained a migration-ledger note explaining repo timestamps don't exactly match prod's `schema_migrations` ledger; on a fresh fork everything's idempotent, but `db push` against an already-converged prod project needs `supabase migration repair` first.

After Round 12, R13+ remain on the table — the audits found 2 CRITICAL items (one being a regression of R11's privacy-manifest fix that missed the second target) and 4 HIGH items the prior 11 rounds all missed. The pattern of "every round catches what the prior round missed" continues to hold.

### Security — Round 13
- **R13 HIGH** Three SwiftUI URL openers bypassed the R12 `ExternalURLOpener` allowlist. R12 grepped for `UIApplication.shared.open` only and missed `Link(destination:)` and `@Environment(\.openURL)`, both of which call the same underlying API and inherit the same scheme problem. Affected sites: `OrderCard.swift` (shipment tracking, server-mutable via PostgREST), `RecordDetailView.swift` (delivery tracking AND bookmark URL — the bookmark case is exactly what the helper's doc-comment cites as the motivating example). All 3 sites converted from `Link`/`openURL` to `Button` + `ExternalURLOpener.openExternal(...)`. Helper's doc-comment updated to call out SwiftUI primitives explicitly so future changes don't re-introduce the gap.
- **R13 MEDIUM** New migration `20260429910000_round13_alter_policies_to_authenticated.sql` flips 34 RLS policies across 11 public tables from `TO {public}` to `TO {authenticated}`. R6's policies (R5/R6 fix) correctly used `{authenticated}`; older policies inherited `{public}` from the original Supabase template. `public` matches every role including anon. Live state was safe (R12 revoked all anon table grants AND `auth.uid()` is NULL for anon) but defense-in-depth: a `pg_dump` restore that re-applies default Supabase grants would re-introduce anon, and `{public}`-targeted policies would be one less defense layer. Postgres 17's `ALTER POLICY ... TO authenticated` lets us flip the role without rewriting USING/WITH CHECK clauses.
- **R13 MEDIUM** `unsubscribeAll` now parallelizes the two `removeChannel` awaits via `async let` so both share the 2s `signOut` timeout window. Previously sequential — channel A took the full budget on slow networks, leaving channel B with whatever was left. The `signOut` `withTaskGroup` comment also clarified to reflect that `cancelAll()` doesn't propagate into the SDK's `phx_leave` ack wait — the orphaned task continues until the websocket dies on auth invalidation. Local sign-out completes immediately; channel teardown is best-effort.
- **R13 DOC** Step 2 ledger note in `SETUP-FOR-AGENTS.md` tightened from "several timestamps don't exactly match" to "~13 early migrations and several mid-April files" so forking users see the actual scale before attempting `db push` against an already-converged project.
- **R13 DOC** R12 CHANGELOG entry corrected: the anon REVOKE sweep covers 22 tables + 2 views (24 entries total), not just "22 tables."

### Performance — Round 13
- iOS: realtime burst no longer does an O(N) `recordsFingerprint(allRecords)` scan per UPDATE. The realtime merger now passes a `_recordsScanHint` (the new record's `updatedAt.timeIntervalSince1970`) before mutating; the `allRecords.didSet` observes the hint, updates the cached fingerprint incrementally with `max(cached, hint)`, and skips the full scan. For a 30-msg burst over 1000 records, drops 30K iterations to 30 single-step updates (~1.5ms saved on MainActor). The full O(N) scan still runs for initial-load and debounced-refresh paths (1–2× per session — cheap enough to not matter).

### Security — Round 14
- **R14 security: DIMINISHING RETURNS REACHED.** The R14 security audit verified the R13 SwiftUI URL allowlist coverage, the 34 ALTER POLICY landings, the unsubscribeAll Task children, the _recordsScanHint invariants, plus a sweep of all other URL primitives (Markdown, AttributedString, WKWebView, SFSafariViewController, Text auto-link, AsyncImage), Info.plist URL-type validation, USING-vs-WITH CHECK gaps, Keychain accessibility class, try? swallowing on auth paths, UserDefaults credential storage, ATS, replica identity, and storage bucket policies. No new findings. Advisor baseline unchanged.

### Performance — Round 14
- iOS: **R14 HIGH F-1** — `toggleRecordPin` correctness bug present since R7. The optimistic-local pin mutation `allRecords[index].pinned = newPinnedState` doesn't change `updatedAt`, so the fingerprint stays identical and `rebuildFilteredArrays()` is skipped — typed slices (healthRecords, recordsBySlug) keep stale `pinned` values until the next realtime UPDATE for that record arrives. Now forces a rebuild after the optimistic mutation. Pin toggle is rare; the rebuild cost is negligible vs. the correctness win.
- iOS: **R14 MEDIUM F-2** — R13's hint mechanism dropped the O(N) scan during burst, but `rebuildFilteredArrays()` itself was still firing per-message (30 rebuilds × 60–120ms each on 1000 records). New `scheduleFilteredArraysRebuild()` debounces the rebuild via a 50ms quiet window — one rebuild per burst instead of N. Body reads of `allRecords` see fresh values immediately (Swift assignment is synchronous + @Observable broadcasts); typed slices catch up after the quiet window. Initial-load / debounced-refresh paths still rebuild synchronously (no hint set → rebuilds run inline as before).

### Docs — Round 14
- Migration `20260429910000_round13_alter_policies_to_authenticated.sql` header and CHANGELOG R13 entry corrected: 33 → 34 ALTER POLICY statements (off-by-one).
- SETUP-FOR-AGENTS.md Step 2 ledger note tightened with the R14-measured actual scale: "~35 repo files with no matching prod version + ~32 prod versions with no matching repo file" instead of the prior "~13 early migrations and several mid-April files."

### BioChecha rotation fix (2026-04-29 evening)

User reported the iOS Today card was "stuck on the afternoon insight, never rotated to the others." Investigation surfaced three independent failures stacked on top of each other:

**Root cause 1 — wrong model in cron payloads.** The 4 `biochecha-*-insight` cron entries in `~/.openclaw/cron/jobs.json` (and in `ops/cron-jobs.example.json`, the public template) specified `model: "zai/glm-5"`. The openclaw gateway is rejecting that model — `gateway.err.log` shows `[cron] payload.model 'zai/glm-5' not allowed, falling back to agent defaults` firing every ~10 minutes. The fallback chain (minimax → openai-codex) sometimes times out, leading to dropped insight rows. Working ingest jobs (`8sleep-ingest`, `withings-ingest`, `oura-ingest`) used `minimax-portal/MiniMax-M2.7-highspeed` directly and fired reliably — that's the working pattern. **Fix:** swapped the 4 biochecha-insight payloads to the working model. Also patched `ops/cron-jobs.example.json` (10 occurrences total) so fresh forks don't inherit the broken pattern. Note: 15 OTHER cron jobs in the user's local config (orders-autopilot, paperless-doc-sync, agent-runs-prune, etc.) still use `zai/glm-5` — out of scope of this fix but flagged for follow-up.

**Root cause 2 — symlinks decayed into stale copies.** SETUP-FOR-AGENTS Step 6 says `ln -sf ~/Developer/ThePerch/agents/health-integrations/* ~/.openclaw/workspace/scripts/health-integrations/`, but only `calendar_sync.py` was actually a symlink — everything else was a stale copy from Apr 28. Critically, `biochecha_dynamic_insight.py`, `biochecha_post_wake_insight.py`, `biochecha_event_insight.py`, `oura_ingest.py`, `inbody_*.py`, `prune_agent_runs.py`, and `_telegram_client.py` were **missing entirely** from the workspace dir — so even when cron tried to invoke them via the documented path, they'd fail with FileNotFoundError. **Fix:** removed all stale copies and re-symlinked the entire dir from the repo. Going forward, any `git pull` automatically reaches the running cron.

**Root cause 3 — no catchup when a slot misses.** Even with the cron fixed, a single network hiccup or model timeout drops a slot for the day. The script had no recovery mechanism. **Fix:** `biochecha_dynamic_insight.py` now runs a catchup pass before the requested slot. Refactored `main()` into `_run_one_slot(slot)` + a thin coordinator that walks `["morning", "midday", "afternoon", "evening"]` in order, runs any slot whose row is missing for today (via new `_slot_has_row_today` helper), then runs the requested slot. So even if morning misses at 7am, when midday fires at 12pm it'll write morning first, then midday. The evening cron is the safety net — as long as it lands, the user sees a complete daily rotation. `morning_post_wake` and `event_logistics` are excluded from catchup since both are event-fired (InBody scale / 17track shipment poll) and depend on upstream triggers.

**iOS — fixed the "latest generated wins" rule.** `InsightsService.fetchTodayDailyInsight` previously sorted by `generated_at DESC LIMIT 1`. That meant a slot firing late (e.g. afternoon catchup writing at 14:00 before midday's normal 12:05) would display all afternoon even though midday was the semantically-current slot. Now uses time-of-day-aware selection with a fallback ladder per current local hour:

```
20:00–06:59 → evening → afternoon → midday → morning_post_wake → morning → legacy
15:00–19:59 → afternoon → midday → morning_post_wake → morning → legacy
12:00–14:59 → midday → morning_post_wake → morning → legacy
07:00–11:59 → morning_post_wake → morning → legacy
```

Plus an explicit yesterday-evening fallback for 00:00–06:59 so the card isn't empty during the overnight gap before today's morning fires. Single round-trip — fetches today's rows + yesterday's evening with one `in (today, yesterday)` filter, picks in-memory.

**iOS — slot label visible on card.** The kicker now shows `MORNING · BIOCHECHA` / `MIDDAY · BIOCHECHA` / `AFTERNOON · BIOCHECHA` / `EVENING · BIOCHECHA` so the user sees which take they're reading and visually confirms the rotation is working. Legacy `daily_health` rows still show `TODAY · BIOCHECHA`. `event_logistics` rows show `DELIVERY · BIOCHECHA`.

**Backfill.** Today's missing morning + evening insights generated manually and inserted into `public.insights` so the iOS card immediately rotates to the right slot per the new selection rule.

---

### Round 15 — DIMINISHING RETURNS REACHED
All three R15 audits (security, iOS perf, backend+docs) returned **DIMINISHING RETURNS REACHED — NO NEW FINDINGS.** The audit cadence has saturated. Per the loop's stop rule ("stop on first empty round"), R15 is the natural terminator. R16 unnecessary.

The only R15 commit was a 10µs cleanup the iOS perf agent flagged for code clarity:
- iOS: dropped a redundant `await MainActor.run { ... }` inside `scheduleFilteredArraysRebuild`'s `Task { [weak self] in ... }`. An unstructured `Task { ... }` spawned from a MainActor-isolated method inherits the parent's actor isolation — the closure body already runs on MainActor, so the inner hop was a same-actor suspend with no purpose. Drops one suspension point between the cancellation check and the rebuild call.

After 9 rounds of pre-public deep audits (R7→R15) — every round caught regressions introduced by the prior round plus pre-existing gaps until R14 (security)/R15 (all surfaces) finally returned empty. **Recommendation per the security audit's closing note**: future audit work should be event-driven (when new code lands, when an edge function actually deploys, when MFA enrollment ships) rather than another round number.

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
