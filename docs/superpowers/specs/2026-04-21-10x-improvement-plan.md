# The Perch — 10X Improvement Plan

**Date:** 2026-04-21
**Status:** Plan locked. Executing Tier 1–2 tonight; Tier 3–4 sequenced for follow-up sessions.

## What this is

Synthesis of ~60 findings from a four-track audit:
- my own self-audit of `orders`/`deliveries` (post the listener+classifier cutover) and the foundational pieces (`dashboard-sync`, `perch-supabase`)
- an Explore-agent audit of `perch-health` + `perch-nutrition`
- an Explore-agent audit of `perch-calendar` + `perch-workouts`
- an Explore-agent audit of `perch-bookmarks` + the iOS app as a whole

## Meta-patterns (why things feel unreliable)

The specific bugs are symptoms of five recurring patterns. Fixing the patterns fixes many bugs at once.

### M1. Silent failures everywhere

| Symptom | Diagnosis |
|---|---|
| Orders Python cron exited 2 for days; cron agent reported "ok" | Inner-script exit code swallowed by agent wrapper. Fixed. |
| `calendar-dashboard-sync` runs twice daily, reports `ok`, no evidence anything was written | Cron wrapper doesn't verify row count before/after; `delivery.mode: 'none'`. |
| Bookmarks pipeline stopped writing March 30 | Nobody noticed because there's no freshness check per pipeline. |
| `commerce`-category dashboard_records frozen since April 17 | Ditto. |

Root cause: **no agent-run observability table**. No single place to ask "when did pipeline X last succeed?". Fix is in Tier 1.

### M2. Dead or never-running pipelines

| Claimed but not running | Evidence |
|---|---|
| Oura Ring ingestion | `perch-health/SKILL.md` describes it; no matching script in repo/runtime. |
| 17track shipment polling | Cron exists, disabled since the script it references (`orders_autopilot_poll_shipments.js`) doesn't exist. Re-wired to `cli.js poll-shipments`, still disabled pending API key. |
| Nutrition `progress_summary` records | `NutritionViewModel` assumes they exist; none in DB. Daily totals never computed. |
| Bookmarks ingest | Last row 2026-03-30 with `display_hint='bookmark'`, no activity since. |
| review_items UI | Pipeline writes them (I added one); iOS has no consumer. |

### M3. Data quality

- **`orders` row completeness:** 50 rows, 0 have `total_amount`, 14% have `source_email_ids`, 42% have `merchant_name`.
- **Calendar naive datetimes:** reference data shows `2026-04-02T08:00:00` (no timezone offset) — the iOS decoder requires offsets per spec. Silent empty-state.
- **Hardcoded macro targets:** `HealthViewModel` pins 180P / 386C / 110F regardless of block. Nutrition agent changes targets, iOS never updates.
- **Unnormalized tags + merchant names:** "iOS"/"ios"/"IOS" all coexist; "Mukama" and "Amazon" both get merchant/merchant_name set inconsistently.
- **Unbounded event growth:** no cron purges past events; `records` for calendar accumulates forever.

### M4. iOS gaps

- No widget / Live Activity / ShareExtension deep links back into the app.
- `@Observable` migration stopped at ViewModels; Services still use `@Published`.
- No Dynamic Type scaling; accessibility flag.
- No workout-logging UI (only agent path).
- No review-items UI (pipeline writes, consumer doesn't exist).
- Dead code: `WidgetRouter.swift`, unused synthetic-nutrition logic in `HealthViewModel`.

### M5. Missing foundation

No `agent_runs` table. No standardized heartbeat pattern. No tests for timezone / validation edge cases. Two independent delivery pipelines (email-driven + SQLite tracker) that don't reconcile.

---

## Ranked plan

### Tier 1 — Foundational reliability (execute first)

**T1.1 — `agent_runs` observability table + helper** (M, foundational)

New Supabase table:
```sql
CREATE TABLE agent_runs (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id     text NOT NULL,
  run_type     text NOT NULL,    -- 'ingest', 'poll', 'sync', 'aggregate'
  started_at   timestamptz NOT NULL DEFAULT now(),
  ended_at     timestamptz,
  status       text NOT NULL,    -- 'running', 'ok', 'error', 'partial'
  summary      jsonb,            -- { processed: N, created: M, errors: [...] }
  error_detail text
);
CREATE INDEX ON agent_runs (agent_id, started_at DESC);
```

Helper in `dashboard-sync`: `cli.js record-run --agent X --type Y [--status ok] [--summary '{...}']` — single-row upsert pattern. Wrapper scripts (`run_orders_autopilot.sh`, `run_orders_ingest_catchup.sh`, the new progress-summary aggregator) call it at end.

A single SQL query — `SELECT agent_id, max(started_at), status FROM agent_runs GROUP BY agent_id ORDER BY max(started_at) DESC` — answers "what broke, when." The iOS Admin section becomes useful for the first time.

**T1.2 — Nutrition progress-summary aggregator** (M, unblocks three HIGH findings)

New script `skill/dashboard-sync/scripts/aggregate-nutrition.ts` driven by cron every 2 hours:
- Query today's `meal` records for the user
- Sum calories + macros
- Query latest targets record (from a new `nutrition_targets` row written by the user's Nutrition agent whenever targets change — new table)
- Upsert a `progress_summary` record for today in `dashboard_records`
- Write to `agent_runs`

Side effect: fixes hardcoded targets in `HealthViewModel` — the view just reads the latest progress_summary.

**T1.3 — Calendar ISO8601 enforcement + duplicate check + past-event purge** (S+S+S, all three calendar HIGHs at once)

Add to whatever runs `calendar-dashboard-sync` (likely an agent turn):
- Always emit ISO8601 with explicit offset; reject naive datetimes at the write layer (validation in `cli.js push` for `category=calendar`).
- Upsert by `(user_id, title, start_time)` instead of blind insert.
- After sync, `DELETE FROM dashboard_records WHERE category='calendar' AND (data->>'start_time')::timestamptz < now() - interval '30 days'`.

**T1.4 — Diagnose and revive the bookmarks pipeline** (M)

Three weeks of no new bookmark data. Hunt: check cron, check Karakeep-sync, check whether the sender is still auth'd, compare disk state to DB state. Restore with observability via T1.1.

### Tier 2 — Quality + coverage (next)

**T2.1 — Oura ingestion pipeline** (L)

New `skill/perch-health/scripts/oura-ingest.ts` using an existing Oura token from `~/.openclaw/secrets/`. Runs daily at 07:00 local. Writes `health_summary` + `body_metrics` to `dashboard_records` with proper Oura "sleep day" UTC-4pm timezone handling.

**T2.2 — Workout `workout_type` field** (S)

Schema: add `data.workout_type` to workout records (pull | push | legs | rest). Update iOS `WorkoutSessionData` to read it explicitly instead of inferring from `muscleGroups`.

**T2.3 — Workout logging UI in iOS** (L)

New `LogWorkoutSheet` accessible from `WorkoutView`. Exercise list, sets × reps × weight, notes, duration. Writes direct to `records` with `category='workouts', type='workout_session'`. Closes the biggest iOS gap in this skill.

**T2.4 — Kill or merge the SQLite delivery trackers** (M)

Two crons (`delivery-tracker` + `Nightly Delivery Tracker`) read from `~/.openclaw/data/deliveries.db` and push to Supabase. `Nightly` literally opens browser tabs to scrape carrier pages. Decide: merge manual entries into the email pipeline as a new "manual" source, OR keep SQLite as a human-entry tool but retire the Supabase-push (app reads from `orders` table anyway).

**T2.5 — Orders data backfill + dedup** (M)

Fill in `source_email_ids` for existing orders from legacy `source_email_id` column. Normalize `merchant_name`. Investigate why `total_amount` is 0% populated (is the extractor broken? does the DB have `total` but not `total_amount`?).

### Tier 3 — iOS polish (after the pipelines are solid)

**T3.1 — `review_items` UI in OrdersView** (M)

The orders pipeline creates rows the app never surfaces. Add a "needs attention" surface: unmatched shipments, ambiguous order emails, duplicate candidates.

**T3.2 — Deep linking from widgets + Live Activities + Share Extension** (L)

`theperch://bookmarks?tab=paperless`, `theperch://orders?id=<uuid>`, etc. Every external touchpoint routes cleanly into the app.

**T3.3 — Dynamic Type support** (L)

`PerchTheme.Font` constants → semantic sizes. Accessibility scaling across cards. Non-trivial because of card density but important.

**T3.4 — Image caching** (M)

Integrate an image cache (or wrap existing `CacheService`) for health images, weather, delivery thumbnails. High-impact perceived perf win.

**T3.5 — @Observable migration complete** (S)

Last few `@Published` usages in services → `@Observable`. Consistency win.

**T3.6 — Empty / error pattern standardization** (S)

Three different error patterns in use (`ErrorBanner`, inline `Text`, `SupabaseServiceError` strings). One `ErrorPresentation` protocol, all errors through it.

### Tier 4 — Substantive but lower ROI

- Tag/merchant normalization layer (shared canonicalization table, aliases).
- Health display hints granularity (`weight_chart`, `sleep_chart`, `hrv_chart`).
- Tests for timezone + data-validation edge cases.
- Generalize `orders_autopilot_ingest_fastmail.py` → `skill/perch-orders/scripts/ingest.py` (Phase 1.5 from prior session).
- Delete dead `WidgetRouter.swift`.
- Standardize on a secrets resolution layer so keys stop drifting between `~/.openclaw/secrets.json`, `.env` files, and keychain.

### Explicitly not doing tonight

- TestFlight / App Store Connect setup (needs Apple Dev account + your attention).
- Public repo flip (you control that moment).
- Adding brand-new skills (reducing surface area > adding).
- Force-push to origin (accumulates until you approve).

---

## Execution plan for tonight

Tier 1 in full:
- [T1.1] `agent_runs` table + `cli.js record-run` helper + wire into the two cron wrappers I created.
- [T1.2] `aggregate-nutrition.ts` script + cron.
- [T1.3] Calendar validation + upsert + purge in whatever agent currently powers `calendar-dashboard-sync`.
- [T1.4] Bookmarks diagnosis (identify the stoppage cause; fix if straightforward).

If context allows, into Tier 2:
- [T2.2] `workout_type` field — trivially small, high signal.
- [T2.5] Orders data backfill.

Everything else queued with the ranked plan above and clear next-steps.

---

## Success criteria for this session

Coming back tomorrow, you should be able to:
1. Run `SELECT agent_id, max(started_at) AS last_run, status FROM agent_runs GROUP BY agent_id` and see every active pipeline listed with its last status.
2. See a daily nutrition progress gauge in the app that reflects real meals and real targets, updating automatically as you log meals.
3. See upcoming calendar events with correct timezone display; no naive-datetime silent drops.
4. Either: bookmarks flowing again, or a clear note explaining why it stopped and what needs to happen.
5. Orders pipeline continuing to work (listener + catchup already in place from this afternoon's work).

Non-criteria (deliberately out of scope tonight):
- iOS source changes beyond trivial consumer updates for new schema fields.
- New pipelines (Oura).
- Workflow changes in Supabase (auth, RLS — they're fine as-is).
