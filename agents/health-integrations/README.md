# Health Integrations + BioChecha Insights

The data + agent layer that feeds the Today-tab insight card AND the
post-wake Telegram briefing. See:

- `docs/post-wake-pipeline.md` — InBody CSV → iOS card + Telegram, architecture + setup
- `docs/superpowers/specs/2026-04-26-insights-and-health-integrations-design.md` — original insights spec
- `docs/superpowers/specs/2026-04-28-time-aware-insights-design.md` — time-aware slot split spec

The scripts live in two places by convention:
- **This repo** (`agents/health-integrations/`) — source of truth, versioned.
- **`~/.openclaw/workspace/scripts/health-integrations/`** — runtime location the cron expects. Should be a symlink to this directory.

If you're setting up a new Mac, after cloning:

```bash
mkdir -p ~/.openclaw/workspace/scripts
ln -s ~/Developer/ThePerch/agents/health-integrations \
      ~/.openclaw/workspace/scripts/health-integrations
```

## Components

### Ingest (data → `public.health_metrics`)

| File | Purpose | Schedule |
|---|---|---|
| `eight_sleep_ingest.py` | Last-24h sleep stages, HRV, RHR from the 8sleep API. **Fallback / fill-in for Oura.** | every 30min |
| `withings_ingest.py` | Last-7d weight + body comp + BP + HR from Withings. **Fallback for InBody on body comp.** | hourly |
| `inbody_ingest.py` | Parses any `InBody-*.csv` in `~/Documents/Claudio/` → 22 metrics. **Primary body-composition source.** Deletes file after success. | watcher (60s poll) |
| `inbody_backfill_from_json.py` | One-shot: imports historical scans from the legacy `body-composition.json` into `health_metrics`. | manual, idempotent |
| `calendar_sync.py` | macOS Calendar.app → `dashboard_records` (category=calendar) for opportunity-based insight categories. | every 15min |

### Insight generation (data → `public.insights`)

| File | Slot | Schedule |
|---|---|---|
| `biochecha_dynamic_insight.py` | morning / midday / afternoon / evening / event_logistics / morning_post_wake | cron-driven |
| `biochecha_post_wake_insight.py` | `morning_post_wake` (the InBody-triggered one) — generates BOTH iOS card AND long-form Telegram briefing | watcher-driven |
| `biochecha_event_insight.py` | `event_logistics` — fired by 17track when a shipment changes status | event-driven |
| `biochecha_daily_insight.py` | **Legacy.** Pre-time-aware-insights single-shot 7am morning generator. Kept for reference; not on cron. | (none) |

### Helpers

| File | Purpose |
|---|---|
| `_supabase_client.py` | Shared HTTP helper. `bulk_upsert_health_metrics`, `insert_agent_run`. Auto-registers agents in `public.agents` on first run. |
| `_telegram_client.py` | Stdlib-only Bot API client. Reads bot token from `~/.openclaw/secrets.json`. Used by `biochecha_post_wake_insight.py`. |
| `withings_setup.py` | One-shot OAuth handshake. Run manually once (opens browser). |

## Source-of-truth precedence

When the same metric is written by multiple sources for the same day,
the higher-priority source wins. Lower-priority sources fill gaps.

| Domain | Primary | Fallback |
|---|---|---|
| Body composition (weight, body fat %, fat mass, muscle mass) | InBody | Withings |
| Sleep (duration, score, HRV, RHR) | Oura *(ingest TBD)* | 8sleep |

The picker lives in `biochecha_dynamic_insight.py:_pick_by_priority`. Ranks
are `SLEEP_SOURCE_PRIORITY` and `BODY_COMP_SOURCE_PRIORITY` constants —
add a new source by appending it to the tuple.

**Heads-up:** there's no Oura ingest yet. Sleep data is currently
8sleep-only. Build an `oura_ingest.py` to flip the precedence; the
gather code is already ready.

## Setup

### 1. Credentials in `perch.env`

`~/.openclaw/secrets/perch.env` (iCloud-synced — see main repo README):

```bash
# Supabase
export SUPABASE_URL=https://<project>.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=...
export PERCH_USER_ID=...

# OpenAI (insight generation)
export OPENAI_API_KEY=...

# 8sleep
export EIGHT_SLEEP_EMAIL=you@example.com
export EIGHT_SLEEP_PASSWORD=...

# Withings — register at https://developer.withings.com/dashboard/
export WITHINGS_CLIENT_ID=...
export WITHINGS_CLIENT_SECRET=...
```

### 2. Withings one-shot OAuth (only needed once)

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/.openclaw/workspace/scripts/health-integrations/withings_setup.py
```

### 3. Telegram bot (for post-wake briefings)

The `biochecha` Telegram bot must exist in your openclaw config:
- `~/.openclaw/secrets.json` → `/channels/telegram/accounts/biochecha/botToken` set
- `~/.openclaw/openclaw.json` → `/channels/telegram/accounts/biochecha/allowFrom` includes your Telegram user ID

`_telegram_client.py` reads from these automatically — no env vars needed.

### 4. InBody watcher launchd agent

```bash
cp ops/launchd/com.theperch.inbody-watcher.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.theperch.inbody-watcher.plist
```

Polls `~/Documents/Claudio/` every 60s. Drop a CSV from the LookinBody
Connect app and within a minute you get a fresh iOS card + Telegram DM.
See `docs/post-wake-pipeline.md` for the full flow.

### 5. Cron entries (4 scheduled slots + 2 ingests)

The user-facing cron lives in `~/.openclaw/cron/jobs.json`. Look for jobs
named `biochecha-morning-insight`, `biochecha-midday-insight`,
`biochecha-afternoon-insight`, `biochecha-evening-insight`,
`8sleep-ingest`, `withings-ingest`, `calendar-sync`.

If they're missing, the time-aware-insights plan walks through generating
them: `docs/superpowers/plans/2026-04-28-time-aware-insights.md` Task 4.4.

## Running manually for testing

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a

# Pull latest data
python3 .../eight_sleep_ingest.py
python3 .../withings_ingest.py

# Drop an InBody CSV in ~/Documents/Claudio/ then either wait 60s OR:
python3 .../inbody_ingest.py
python3 .../biochecha_post_wake_insight.py

# Generate any specific scheduled slot
python3 .../biochecha_dynamic_insight.py morning
python3 .../biochecha_dynamic_insight.py midday
python3 .../biochecha_dynamic_insight.py afternoon
python3 .../biochecha_dynamic_insight.py evening
```

Each script prints a short summary on stdout and writes a row to
`public.agent_runs` for observability.

## Voice tuning

Two prompts:
- `SYSTEM_PROMPT` (iOS card, 30-55 words, single paragraph)
- `SYSTEM_PROMPT_TELEGRAM` (post-wake DM only, 200-400 chars, multi-section, Markdown)

Both live in `biochecha_dynamic_insight.py`. Edit, run a slot manually,
read the output, iterate.

The rage-shake feedback loop also feeds back as few-shot context: when
the user shakes the device on the Today tab and submits a reaction,
that reaction lands in `public.insight_feedback` and is injected into
the next 5 slot generations as "RECENT USER FEEDBACK". See
`agents/health-integrations/biochecha_dynamic_insight.py:_gather_recent_feedback`.

## Failure handling

Every script:
- Writes to `public.agent_runs` on every run (status = ok / partial / error)
- Prints to stdout for cron-log visibility
- Exits non-zero on fatal failures so escalation paths trigger

8sleep is the most fragile (reverse-engineered API). When it changes,
expect agent_runs status='error' rows. The insight scripts are resilient:
empty data → category returns None → falls through to other categories
or `quiet_day_fallback`.

## Tests

```bash
cd agents/health-integrations
python3 -m unittest test_dynamic_insight   # 34 tests
python3 -m unittest test_supabase_client   # 2 tests
```
