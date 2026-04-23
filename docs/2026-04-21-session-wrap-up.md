# Session wrap-up — 2026-04-21 → 2026-04-22

Two big tracks landed: **orders pipeline hardening** (Approach B + C, merged after discovering the `jmap-listener` was the right substrate), and a **10X audit + Tier 1 execution** across all skills. Nothing is breaking; a lot of silent failure modes are gone.

## Commits

### ThePerch repo (`~/.openclaw/workspace/ThePerch/`)
Latest first, just this session's additions:

```
9757633 feat(nutrition): aggregator output uses iOS MacrosData-compatible keys
d5095a1 feat(T1.3): calendar_dashboard_sync.py — env-based secrets, ISO8601 w/ tz, agent_runs
9a12e85 feat(T1.1 + T1.2): agent_runs observability + nutrition progress aggregator
3cfe86f docs: 10X improvement plan for The Perch
a1f15f1 feat(orders-pipeline): classifier quality fixes
b5957e4 feat(orders-pipeline): cli.js process-email + poll-shipments, TS fixes, schema
dd34a8b docs: orders pipeline hardening spec (listener-driven ingest + catchup)
```

### Workspace repo (`~/.openclaw/workspace/`)
```
28a4ee3 feat: wrapper for calendar_dashboard_sync cron
eaf5fc8 feat(cron-wrappers): bracket pipeline runs with agent_runs records
7bc1ed6 feat: orders pipeline listener hook + catchup wrapper
```

Both repos still need force-push (history rewrites from earlier sessions are pending).

## What changed, in order

### 1. Orders pipeline: real-time + catchup

The felt pain was "unreliable scanning, things don't update." Root cause was four overlapping pipelines (Python cron re-scanning stateless, 17track poll disabled pointing at a missing script, two SQLite-based delivery trackers, and the TS classifier sitting idle despite being the smart one).

- **TS classifier is now the canonical ingestor.** `skill/dashboard-sync/cli.js process-email` (stdin JSON → classifier → Supabase) is the single write path.
- **`listener.py` drives it in near-real-time.** Already running every 10 s; now spawns a daemon thread that pipes new emails through `orders_ingest_hook.py` → `cli.js process-email`. Results recorded to a shared state file (`~/.openclaw/workspace/state/orders-ingest-state.json`) under fcntl advisory lock.
- **`orders_ingest_catchup.py` is the safety net.** Cron `0 5,17 * * *`. Fetches last 48 h of Fastmail via JMAP, skips IDs already in state, feeds everything else through `cli.js process-email`. Independently recorded to `agent_runs`.
- **Old 30-min Python cron is disabled** (kept for 1-week rollback, then delete). Its wrapper (`run_orders_autopilot.sh`) still exists and records to `agent_runs`, so if you re-enable it you get observability.
- **17track poll is pre-wired** to `cli.js poll-shipments --user_id …`, still disabled pending the API key. **When you add `SEVENTEEN_TRACK_API_KEY=…` to `~/.openclaw/secrets/perch.env`**, flip `orders-autopilot-17track-poll` to `enabled: true` in `~/.openclaw/cron/jobs.json` — shipment statuses will start progressing.
- **Classifier quality fixes** inside the TS code: sender-based hard exclusion for Uber/food-delivery/ride-hailing/Stripe-receipts (kills the "uber #CELLPADDING" garbage rows I caught in testing); tightened order-number extraction to require `#` or "order number/no.", strip HTML attrs before regex, reject CELLPADDING/BGCOLOR/STYLE tokens.

### 2. Schema + data cleanup
- Migration `20260421_relax_legacy_not_null_on_orders_and_shipments`: dropped NOT NULL on `orders.{merchant, order_number, source_email_id, confidence}` and `shipments.carrier`. Replaced the global `(merchant, order_number)` unique index with a per-user partial `(user_id, normalized_merchant, order_number) WHERE order_number IS NOT NULL`.
- Migration `20260421_agent_runs_observability`: new `agent_runs` table + `agent_runs_latest` view + RLS. Every pipeline that matters now brackets its run with an `agent_runs` row.
- Three new agent rows: `nutrition-aggregator`, `orders-ingest-catchup`, `orders-autopilot` (the FK on `dashboard_records.agent_id` needed them provisioned).

### 3. Nutrition aggregator
- `skill/dashboard-sync/scripts/aggregate-nutrition.js`. Every 30 min 06:00–23:30 Europe/Lisbon: sums today's meals, reads targets from `users.preferences->'nutrition_targets'` (fallback to 2800/180/320/90 if missing), upserts a single `progress_summary` record keyed by `(user_id, date)`.
- **iOS-compatible output.** Emits `{protein, protein_target, carbs, carbs_target, fat, fat_target, date}` in `data` — the exact shape `MacrosData` decodes. `NutritionTargets.resolved(for:records:)` will pick these up automatically and stop using the hardcoded 180/386/110 fallback in `HealthViewModel`. Also emits longer `consumed_*_g`/`target_*_g`/`remaining_*_g` keys for SQL readability.

To override defaults: `UPDATE users SET preferences = jsonb_set(preferences, '{nutrition_targets}', '{"calories":2900,"protein":190,"carbs":350,"fat":80}'::jsonb) WHERE id='…';`

### 4. Calendar pipeline
- `scripts/calendar_dashboard_sync.py`. Replaces the agent-turn cron that baked the Supabase anon key into `jobs.json` (yes, that's why I changed it — the key was in backups). New script sources secrets from `perch.env`, runs `icalBuddy`, formats every timestamp as ISO8601 with explicit offset (fixing the naive-datetime silent drops in the iOS decoder), filters "Break / Block Time / Focus / No Meeting / cancelled", brackets the run with `agent_runs`.
- **Not tested in my shell** (no calendar access from the context I was running in). First cron fire at 07:05 or 13:05 Europe/Lisbon will exercise it; if it fails you'll see `status='error'` in `agent_runs` with the error detail. If icalBuddy's output format doesn't match my parser (plausible — it's been a drifty tool), we'll adapt.

### 5. Observability layer
Now live. One query tells you everything:
```sql
SELECT * FROM agent_runs_latest ORDER BY started_at DESC;
```
You'll see `orders-autopilot`, `orders-ingest-catchup`, `nutrition-aggregator`, `calendario` and any others that come online. `status = 'error'` means act; `error_detail` has what happened.

## What I deferred and why

Every deferral lives in the 10X plan doc (`docs/superpowers/specs/2026-04-21-10x-improvement-plan.md`). Top three:

1. **Bookmarks pipeline revival.** Diagnosed: Archie's `karakeep_bookmarks.json` at `~/.openclaw/agents/archie/data/` has malformed JSON (unescaped `"` chars in captioned Instagram reel titles). Archie's sync writer is broken. Downstream writer to `dashboard_records` hasn't been finding usable data since 2026-03-30. Fix path: either repair Archie's writer, or pull Karakeep directly via the `KARAKEEP_TOKEN` you have in iOS Secrets.plist. Real work (~2 h). Queued.

2. **Workout `workout_type` schema.** Would fix the "iOS infers pull/push/legs from `muscleGroups`, error-prone" issue. But needs coordinated schema migration + pipeline update + iOS decoder. Worth its own session.

3. **Orders data backfill.** 50 rows with inconsistent columns (0% `total_amount`, 42% `merchant_name`, 14% `source_email_ids`). Mostly cosmetic; new inserts from the TS classifier are clean.

4. **iOS polish (Tier 3):** review_items UI, deep linking, Dynamic Type, image caching. Each is its own thing.

## What needs you

Ordered by blocking impact:

1. **Force-push both repos** — `main` has diverged from origin on both. Safe:
   ```
   cd ~/.openclaw/workspace/ThePerch && git fetch origin && git push --force-with-lease origin main
   cd ~/.openclaw/workspace && git push  # (no remote historically, confirm)
   ```

2. **Drop `SEVENTEEN_TRACK_API_KEY=…`** into `~/.openclaw/secrets/perch.env`, then flip `orders-autopilot-17track-poll` to `enabled: true` in `jobs.json`. Shipment statuses start progressing.

3. **Provision nutrition targets** via SQL if the defaults (2800/180/320/90) don't match your current macro block.

4. **Watch the first few cron fires after wake-up** to confirm `calendar_dashboard_sync.py` parses your `icalBuddy` output correctly. If not, `SELECT * FROM agent_runs WHERE agent_id='calendario' ORDER BY started_at DESC LIMIT 3` will show you what failed.

5. **Read `docs/superpowers/specs/2026-04-21-10x-improvement-plan.md`** for the full Tier 2–4 queue. Pick what interests you next.

## Outstanding side-observations

- `listener.py` has an **unrelated** pre-existing bug where it tries to resolve a Telegram bot-token config template but just uses the raw dict, producing URLs like `/bot{'source':...}/sendMessage`. I did not fix it — out of scope for orders work. Easy ~20-line fix when you want it.
- `~/.openclaw/agents/archie/data/karakeep_bookmarks.json` is **malformed**. Archie's Karakeep sync writer is emitting invalid JSON. Worth fixing separately.
- Five backup files in `~/.openclaw/cron/jobs.json.bak-*` from my edits — safe to delete once you've verified the new crons land.
