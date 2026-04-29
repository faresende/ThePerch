# SETUP-FOR-AGENTS.md

> **You are an openclaw agent (Claude or compatible). The user just handed you this file and told you to set up The Perch.** Follow it end-to-end. When you hit a step that needs a human (signing into a service, copy-pasting a key, running Xcode) — pause, ask, and continue when they say go.
>
> This doc is the canonical install sequence. The README.md is for humans; this is for you.

---

## Pre-flight

Confirm these are present on the user's machine. If anything's missing, tell them which and stop:

```bash
which xcodebuild   # Xcode 15+ — required
which node         # Node 22+ — required
which python3      # Python 3.11+ — required
which psql         # optional, only for local SQL ops
ls ~/.openclaw     # openclaw CLI installed and used at least once
```

Confirm the repo is cloned to `~/Developer/ThePerch` (or wherever the user prefers — adjust paths below accordingly):

```bash
ls ~/Developer/ThePerch/README.md
```

---

## Step 1 — Create a Supabase project (HUMAN STEP)

Tell the user:

> Go to https://supabase.com/dashboard, create a new project. Free tier is fine. Once it's provisioned (≈90 seconds), grab three things from **Settings → API**:
>
> 1. The **Project URL** (looks like `https://xxxxx.supabase.co`)
> 2. The **anon / public** key
> 3. The **service_role** key (keep this private — it bypasses RLS)
>
> Tell me when you've got them.

Wait for the user to confirm. Don't proceed without all three.

---

## Step 2 — Run migrations

The schema lives in **two places** under `supabase/`:

1. **`supabase/001_initial_schema.sql`** — bootstrap tables (`users`, `agents`, `sections`, `home_widgets`, `dashboard_records`, `health_metrics`, `agent_users`, etc.)
2. **`supabase/002_seed_demo.sql`** — demo agent set + section layout (idempotent, replace placeholder UUIDs with the user's auth uid before running)
3. **`supabase/migrations/*.sql`** — every change since (orders, shipments, insights, learned_senders, merchant_rules, agent_runs retention, etc.) — apply in **filename order** (timestamps sort lexicographically).

Easiest path — open Supabase Dashboard → SQL Editor → New Query → paste → Run, repeat for each file in this order:

```bash
ls -1 ~/Developer/ThePerch/supabase/001_initial_schema.sql \
       ~/Developer/ThePerch/supabase/002_seed_demo.sql \
       ~/Developer/ThePerch/supabase/migrations/*.sql
```

Or, if the user has the Supabase CLI configured:

```bash
supabase db push --project-ref <YOUR-PROJECT-REF>
```

(`db push` reads from `supabase/migrations/`. The two `001_*` / `002_*` files at `supabase/` root won't be picked up automatically — paste those into the SQL Editor first.)

Verify a few key tables exist after migrations land:

```sql
-- Run in Supabase SQL Editor
SELECT count(*) FROM public.users;             -- should exist (may be 0)
SELECT count(*) FROM public.dashboard_records; -- should exist (the iOS app's primary read surface)
SELECT count(*) FROM public.orders;            -- should exist
SELECT count(*) FROM public.health_metrics;    -- should exist
SELECT count(*) FROM public.insights;          -- should exist
SELECT count(*) FROM public.order_corrections; -- should exist (Phase 1 corrections)
```

If any of these throw "relation does not exist", a migration didn't apply. Stop and investigate.

---

## Step 3 — Create the user record (HUMAN STEP)

The Perch's RLS policies key off `auth.uid()`. The user needs an auth account on their Supabase project.

Tell the user:

> In Supabase: **Authentication → Users → Add user → Create new user**. Pick an email and password. Once created, copy the user's UUID — you'll need it for the env files.

When they have the UUID, store it as `PERCH_USER_ID` (you'll write it to perch.env in Step 5).

Then create the `public.users` row that mirrors the auth user:

```sql
INSERT INTO public.users (id, display_name)
VALUES ('<YOUR-USER-ID>', 'Your Name');
```

(The exact schema for `public.users` is in `supabase/001_*.sql` — check it if anything's different.)

---

## Step 4 — Set up the openclaw skill

```bash
cd ~/Developer/ThePerch/skill/dashboard-sync
npm install
npm run build         # compiles dist/

# Symlink (or copy) into the openclaw skills directory
ln -sf ~/Developer/ThePerch/skill/dashboard-sync ~/.openclaw/skills/dashboard-sync
ls ~/.openclaw/skills/dashboard-sync/cli.js   # should resolve
```

Test the skill loads (won't have data yet, but should respond):

```bash
node ~/.openclaw/skills/dashboard-sync/cli.js --help
```

---

## Step 5 — Write `~/.openclaw/secrets/perch.env`

Create the file. You'll fill it in across the next steps:

```bash
mkdir -p ~/.openclaw/secrets
chmod 700 ~/.openclaw/secrets

cat > ~/.openclaw/secrets/perch.env <<'EOF'
# Supabase — from Step 1
export SUPABASE_URL=https://<YOUR-PROJECT-REF>.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=<paste-your-service-role-key>
export PERCH_USER_ID=<your-user-uuid-from-step-3>

# OpenAI — only needed for BioChecha daily insight (Step 7)
export OPENAI_API_KEY=

# Withings — only needed if you want body composition data (Step 8)
export WITHINGS_CLIENT_ID=
export WITHINGS_CLIENT_SECRET=

# 8sleep — only needed if you have an 8sleep mattress (Step 9).
# The two CLIENT_* values are app-identifying constants extracted
# from the official Pod app — multiple community projects ship the
# same. See scripts/.env.example for rationale + ToS caveats.
export EIGHT_SLEEP_EMAIL=
export EIGHT_SLEEP_PASSWORD=
export EIGHT_SLEEP_CLIENT_ID=
export EIGHT_SLEEP_CLIENT_SECRET=

# Oura — primary sleep source (Step 8). Generate at
# https://cloud.ouraring.com/personal-access-tokens
export OURA_PERSONAL_TOKEN=

# 17track — only needed for shipment ETAs (Step 10)
export SEVENTEEN_TRACK_API_KEY=

# InBody H30 watcher — override default ~/Documents/InBody dir (Step 11)
export INBODY_WATCH_DIR=

# Telegram bot for post-wake briefings — optional. Account name
# defaults to "biochecha" for back-compat with the maintainer's
# openclaw config; override via PERCH_TELEGRAM_ACCOUNT.
export PERCH_TELEGRAM_ACCOUNT=
export PERCH_TELEGRAM_BOT_TOKEN=
export PERCH_TELEGRAM_CHAT_ID=

# TestFlight deploy (deploy-testflight.sh) — only the maintainer needs
# these on their dev machine. APPLE_KEY_ID is the 10-char alphanumeric
# key id; APPLE_ISSUER is a UUID.
export APPLE_KEY_ID=
export APPLE_ISSUER=
export APPLE_KEY_PATH=
EOF

chmod 600 ~/.openclaw/secrets/perch.env
```

The user fills in the optional ones as they decide which integrations they want.

---

## Step 6 — Symlink the agent scripts

```bash
mkdir -p ~/.openclaw/workspace/scripts/health-integrations
ln -sf ~/Developer/ThePerch/agents/health-integrations/* \
       ~/.openclaw/workspace/scripts/health-integrations/
ls ~/.openclaw/workspace/scripts/health-integrations/
```

You should see roughly:
- Helpers: `_supabase_client.py`, `_telegram_client.py`
- Insight generators: `biochecha_dynamic_insight.py`, `biochecha_post_wake_insight.py`, `biochecha_event_insight.py`, `archive/biochecha_daily_insight.py` (legacy, archived 2026-04-29)
- Ingest workers: `oura_ingest.py`, `eight_sleep_ingest.py`, `withings_ingest.py`, `withings_setup.py`, `inbody_ingest.py`, `inbody_backfill_from_json.py`, `calendar_sync.py`
- Maintenance: `prune_agent_runs.py`

---

## Step 7 — BioChecha time-aware insights (optional, recommended)

Skip this if the user doesn't want LLM-generated insights.

The user needs an OpenAI API key (https://platform.openai.com/api-keys). gpt-4o-mini, ~$0.0001 per insight; daily cost is negligible.

The insights system has six slots:

| Slot | Trigger | What it produces |
|---|---|---|
| `morning` | 7am Lisbon cron | Forward-looking plan-of-the-day (training, macros, calendar load) |
| `midday` | noon cron | Mid-day check-in (anticipatory lunch / pacing / shipments) |
| `afternoon` | 3pm cron | Gap-aware opportunity nudge |
| `evening` | 8pm cron | Day recap |
| `morning_post_wake` | InBody watcher OR manual | Post-weigh-in retrospective + body-comp delta + Telegram briefing |
| `event_logistics` | 17track shipment status flip | "Out for delivery" / "ETA today" |

Smoke-test that the pipeline works:

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_dynamic_insight.py morning
```

If it succeeds, an insight row lands in `public.insights` with today's date and `insight_type='daily_health_morning'`. Verify:

```sql
SELECT insight_type, body, valid_for_date FROM public.insights
WHERE agent_id = 'biochecha' ORDER BY generated_at DESC LIMIT 5;
```

The first run will likely fall through to `quiet_day_fallback` because no health data has been ingested yet — that's expected. Categories are explained in `agents/health-integrations/README.md` and `docs/post-wake-pipeline.md`.

`biochecha_daily_insight.py` was the legacy single-shot 7am generator. It is now archived at `agents/health-integrations/archive/biochecha_daily_insight.py` — kept for git history, not on cron, not symlinked into the live runtime.

---

## Step 8 — Withings (optional, fallback body-comp source)

Skip if the user doesn't have a Withings account.

1. **HUMAN STEP:** user goes to https://developer.withings.com/dashboard/, creates a personal app. Sets the redirect URI to `http://localhost:8127/withings/callback`.

2. They paste the `client_id` + `client_secret` into `perch.env`.

3. Run the OAuth handshake (one-time):

   ```bash
   set -a && source ~/.openclaw/secrets/perch.env && set +a
   python3 ~/.openclaw/workspace/scripts/health-integrations/withings_setup.py
   ```

   Browser opens, user authorizes, the script captures the code and persists tokens to `~/.openclaw/state/withings-tokens.json`.

4. Run the first ingest:

   ```bash
   python3 ~/.openclaw/workspace/scripts/health-integrations/withings_ingest.py
   ```

   Should report `written=N failed=0`.

---

## Step 9 — Oura (optional, primary sleep source)

Skip if the user doesn't have an Oura ring.

The user generates a personal access token at https://cloud.ouraring.com/personal-access-tokens (sign in → Create new). Pastes it into `perch.env` as `OURA_PERSONAL_TOKEN=…`. Then:

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/.openclaw/workspace/scripts/health-integrations/oura_ingest.py
```

Should report `sessions=N daily_sleep=N readiness=N written=N failed=0`. Pulls the last 14 days of sleep + daily sleep score + readiness score into `public.health_metrics` under `source='oura'`. Source-of-truth precedence in the gather code is **Oura > 8sleep**; if both are present for the same night, Oura wins.

---

## Step 10 — 8sleep (optional, fallback sleep source, may break)

Skip if the user doesn't have an 8sleep mattress. Warn them this integration is reverse-engineered and may break.

User adds `EIGHT_SLEEP_EMAIL` + `EIGHT_SLEEP_PASSWORD` (their 8sleep app login) to `perch.env`. Then:

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/.openclaw/workspace/scripts/health-integrations/eight_sleep_ingest.py
```

Should report `written=N failed=0`. Pulls the last 14 days of nightly data into `public.health_metrics` under `source='8sleep'`. Used as a fallback when Oura is silent (e.g. ring off the charger), and for bed-temp / room-temp signals Oura doesn't have.

---

## Step 11 — InBody H30 watcher (optional, primary body-comp source)

Skip if the user doesn't have an InBody H30 / LookinBody Connect.

The user exports CSVs from LookinBody Connect into a folder; a launchd polling agent watches it, ingests + deletes new files within 60s, and re-fires the post-wake insight. The end-to-end pipeline (CSV → iOS card + Telegram briefing) is documented in `docs/post-wake-pipeline.md`.

Install the watcher:

```bash
~/Developer/ThePerch/scripts/install-inbody-watcher.sh
# default ~/Documents/InBody — override with WATCH_DIR=...
```

The script renders `ops/launchd/com.theperch.inbody-watcher.plist.template` with the chosen paths and `launchctl load`s it. Idempotent — re-run after editing.

If the user has a legacy `body-composition.json` from a pre-watcher chat-based flow, run the one-shot backfill once to populate historical scans:

```bash
python3 ~/.openclaw/workspace/scripts/health-integrations/inbody_backfill_from_json.py
```

Source-of-truth precedence: **InBody > Withings**. Withings still ingests if configured, but InBody wins where both have data for the same day.

---

## Step 12 — 17track (optional, for shipment ETAs)

Skip if the user doesn't ship online or doesn't care about ETAs.

User signs up at https://api.17track.net/, gets an API key (free tier covers ~40 trackings/month), pastes into `perch.env` as `SEVENTEEN_TRACK_API_KEY`.

The orders skill will use it on next inbox scan.

---

## Step 13 — Cron jobs

The Perch's data pipeline runs on cron. A complete template ships at
`ops/cron-jobs.example.json`. Copy it (merging with whatever already
exists) into the openclaw cron file:

```bash
mkdir -p ~/.openclaw/cron
# If you already have jobs.json, merge by hand. If not:
cp ops/cron-jobs.example.json ~/.openclaw/cron/jobs.json
$EDITOR ~/.openclaw/cron/jobs.json   # adjust paths + tz to your install
```

The full set is **8 ingest + insight jobs + 1 retention job**. All use the
`lightContext: true` + `toolsAllow: ["exec"]` + `zai/glm-5` + NO_REPLY pattern
so the cron agent runs the script and exits silently on success — no LLM
narration unless the script fails.

Common shape (substitute `<NAME>`, `<SCRIPT>`, `<EXPR>`, `<TIMEOUT>`):

```json
{
  "id": "<uuidgen>",
  "agentId": "cron-agent",
  "name": "<NAME>",
  "enabled": true,
  "schedule": { "kind": "cron", "expr": "<EXPR>", "tz": "Europe/Lisbon" },
  "sessionTarget": "isolated",
  "wakeMode": "now",
  "delivery": { "channel": "last", "mode": "none" },
  "payload": {
    "kind": "agentTurn",
    "lightContext": true,
    "toolsAllow": ["exec"],
    "model": "zai/glm-5",
    "timeoutSeconds": <TIMEOUT>,
    "message": "Run exactly this command once:\npython3 ~/.openclaw/workspace/scripts/health-integrations/<SCRIPT>\n\nRules:\n- If the command exits 0, reply exactly NO_REPLY.\n- If it exits non-zero, reply with the first line of stderr only.\n- Do not summarise, do not mention cron or runs."
  },
  "createdAtMs": <unix-ms>,
  "state": {}
}
```

Per-job fillings:

| name | expr | script | timeout |
|---|---|---|---|
| `oura-ingest`              | `*/30 * * * *`   | `oura_ingest.py`         | 300 |
| `8sleep-ingest`            | `*/30 * * * *`   | `eight_sleep_ingest.py`  | 300 |
| `withings-ingest`          | `0 * * * *`      | `withings_ingest.py`     | 300 |
| `calendar-sync`            | `*/15 6-22 * * *`| `calendar_sync.py`       |  60 |
| `biochecha-morning-insight`   | `0 7 * * *`   | `biochecha_dynamic_insight.py morning`   | 600 |
| `biochecha-midday-insight`    | `0 12 * * *`  | `biochecha_dynamic_insight.py midday`    | 600 |
| `biochecha-afternoon-insight` | `0 15 * * *`  | `biochecha_dynamic_insight.py afternoon` | 600 |
| `biochecha-evening-insight`   | `0 20 * * *`  | `biochecha_dynamic_insight.py evening`   | 600 |
| `agent-runs-prune`         | `0 4 * * *`      | `prune_agent_runs.py`    | 120 |

Generate UUIDs with `uuidgen`. Tweak the timezone if the user isn't in Lisbon.

The post-wake insight (`biochecha_post_wake_insight.py`) and event-logistics slot (`biochecha_event_insight.py`) do **not** go on cron — they're triggered by the InBody watcher (Step 11) and the orders-autopilot 17track hook (Step 12) respectively.

---

## Step 14 — LaunchAgent for 17track polling

```bash
~/Developer/ThePerch/ops/install-launchagent.sh
```

This substitutes `__HOME__` in the plist template with the user's actual home dir, copies into `~/Library/LaunchAgents/`, and `launchctl load`s it. From now on, every 30 minutes it polls 17track for ETAs + delivery status updates.

Verify it's loaded:

```bash
launchctl list | grep com.theperch.poll-shipments
```

Logs at `~/.openclaw/logs/poll-shipments.log`.

---

## Step 15 — iOS app

Open Xcode:

```bash
open ~/Developer/ThePerch/ios/ThePerch/ThePerch.xcodeproj
```

Tell the user:

> 1. Sign in with your Apple ID under **Project → Signing & Capabilities → Team** (set to your personal team).
> 2. Bundle identifier — change it to something unique under your Team. The default is `NotButter.ThePerch`; pick `<yourdomain>.ThePerch` or similar.
> 3. Copy `Config/Secrets.example.xcconfig` → `Config/Secrets.xcconfig` (the .xcconfig is gitignored). Fill in:
>    - `SUPABASE_URL` (from Step 1)
>    - `SUPABASE_ANON_KEY` (from Step 1, the **anon** one not service_role)
>    - `KARAKEEP_BASE_URL` and `KARAKEEP_TOKEN` — leave blank if you don't have a Karakeep instance. The Bookmarks tab will show a friendly empty state.
> 4. Build + Run on your device (not simulator — push notifications and JMAP-via-share don't work in sim).

First launch should show the Today tab with empty states for everything that doesn't have data yet. As cron runs and data accumulates, the cards populate.

---

## Step 16 — Smoke test

```bash
# Verify a few endpoints by hitting Supabase directly:
set -a && source ~/.openclaw/secrets/perch.env && set +a
curl -s "$SUPABASE_URL/rest/v1/health_metrics?select=metric&limit=1" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"
```

Should return `[]` initially (or `[{"metric":"..."}]` after the first ingest run).

Run the configured ingests + one slot generation manually so the user has data on Today the first time they open the app:

```bash
python3 ~/.openclaw/workspace/scripts/health-integrations/oura_ingest.py
python3 ~/.openclaw/workspace/scripts/health-integrations/eight_sleep_ingest.py
python3 ~/.openclaw/workspace/scripts/health-integrations/withings_ingest.py
python3 ~/.openclaw/workspace/scripts/health-integrations/calendar_sync.py
python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_dynamic_insight.py morning
```

(Skip whichever ingest the user didn't configure. The morning slot will fall through to `quiet_day_fallback` if nothing's in `health_metrics` yet — that's expected.)

---

## Done

If you got through all 16 steps cleanly: tell the user The Perch is live, give them the next-build instructions ("bump build, run on device"), and exit. If you got stuck, tell them which step and why.

Common stumbles to watch for:

- **"Missing env" errors:** they didn't `source perch.env` in the same shell that's running the script.
- **Withings ingest writes 0:** their most recent weigh-in is older than the script's lookback window. Default is 60 days — adjust if needed.
- **8sleep "session token not supported":** 8sleep updated their auth flow again. Open an issue; we'll fix.
- **iOS app shows "The insight engine takes the morning…":** the daily insight cron hasn't fired yet, or the insight failed to decode. Check `agent_runs` for errors.
- **Karakeep tab shows "not configured":** expected if they didn't set `KARAKEEP_BASE_URL`. Working as intended.

---

## You — agent — should not

- Modify any of the user's existing data without explicit confirmation.
- Push any commits to the user's repo without explicit confirmation.
- Skip the rotation reminder if they've ever distributed an IPA.
- Auto-resolve "Withings ingest failed" by changing migration files. Migrations are immutable once applied.
