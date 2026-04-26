# Health Integrations + BioChecha Daily Insight

These scripts are the data + agent layer for the daily-insight surface on the Today tab. See the spec at
`docs/superpowers/specs/2026-04-26-insights-and-health-integrations-design.md` for the architecture rationale.

The scripts live in two places by convention:
- **This repo** (`agents/health-integrations/`) — source of truth, versioned.
- **`~/.openclaw/workspace/scripts/health-integrations/`** — the runtime location the cron expects. Should be a copy or symlink of this directory.

If you're setting up a new Mac, after cloning:

```bash
mkdir -p ~/.openclaw/workspace/scripts
ln -s ~/Developer/ThePerch/agents/health-integrations \
      ~/.openclaw/workspace/scripts/health-integrations
```

## Components

| File | Purpose |
|---|---|
| `_supabase_client.py` | Shared HTTP helper for upserting `health_metrics` + recording `agent_runs`. |
| `eight_sleep_ingest.py` | Pulls last-24h sleep sessions, stages, HRV, RHR from the 8sleep private API. |
| `withings_setup.py` | One-shot OAuth handshake. Run manually once (opens browser). |
| `withings_ingest.py` | Pulls last-7d weight + body comp + BP + HR from Withings. Auto-refreshes tokens. |
| `biochecha_daily_insight.py` | Reads recent data from Supabase, generates today's insight via GPT-4o-mini, writes to `public.insights`. |

## Setup

### 1. Credentials in `perch.env`

Add to `~/.openclaw/secrets/perch.env` (which is now iCloud-synced — see main repo README):

```bash
# 8sleep — your Pod account email + password
export EIGHT_SLEEP_EMAIL=you@example.com
export EIGHT_SLEEP_PASSWORD=...

# Withings — register a personal app at https://developer.withings.com/dashboard/
# Set its redirect URI to: http://localhost:8127/withings/callback
export WITHINGS_CLIENT_ID=...
export WITHINGS_CLIENT_SECRET=...
```

### 2. Withings one-shot OAuth (only needed once)

After client_id + client_secret are in `perch.env`:

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/.openclaw/workspace/scripts/health-integrations/withings_setup.py
```

A browser tab opens, asks you to grant access. After you click through, the script captures the OAuth code on `localhost:8127` and writes refresh + access tokens to `~/.openclaw/state/withings-tokens.json` (mode 600).

Done. The hourly ingest cron uses these tokens automatically and refreshes them when they expire.

### 3. Cron entries

Add to `~/.openclaw/cron/jobs.json` (or use whatever scheduler you prefer):

```json
{
  "id": "8sleep-ingest",
  "name": "8sleep-ingest",
  "enabled": true,
  "schedule": { "kind": "cron", "expr": "*/30 * * * *", "tz": "Europe/Lisbon" },
  "payload": {
    "kind": "shell",
    "command": "set -a && source ~/.openclaw/secrets/perch.env && set +a && python3 ~/.openclaw/workspace/scripts/health-integrations/eight_sleep_ingest.py"
  }
},
{
  "id": "withings-ingest",
  "name": "withings-ingest",
  "enabled": true,
  "schedule": { "kind": "cron", "expr": "0 * * * *", "tz": "Europe/Lisbon" },
  "payload": {
    "kind": "shell",
    "command": "set -a && source ~/.openclaw/secrets/perch.env && set +a && python3 ~/.openclaw/workspace/scripts/health-integrations/withings_ingest.py"
  }
},
{
  "id": "biochecha-daily-insight",
  "name": "biochecha-daily-insight",
  "enabled": true,
  "schedule": { "kind": "cron", "expr": "0 7 * * *", "tz": "Europe/Lisbon" },
  "payload": {
    "kind": "shell",
    "command": "set -a && source ~/.openclaw/secrets/perch.env && set +a && python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_daily_insight.py"
  }
}
```

Or if your existing cron infrastructure uses `agentTurn` payloads (looking at `~/.openclaw/cron/jobs.json` — it does), adapt to that shape.

## Running manually for testing

```bash
# Source env once
set -a && source ~/.openclaw/secrets/perch.env && set +a

# Pull latest sleep
python3 ~/.openclaw/workspace/scripts/health-integrations/eight_sleep_ingest.py

# Pull latest weight / BP / etc
python3 ~/.openclaw/workspace/scripts/health-integrations/withings_ingest.py

# Generate today's insight
python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_daily_insight.py
```

Each script prints a short summary on stdout and writes a row to `public.agent_runs` for visibility in the autopilot health view (when that view ships).

## Voice tuning

The writerly voice lives in the SYSTEM_PROMPT constant at the top of `biochecha_daily_insight.py`. Examples of good + bad insights are baked into the prompt. To tune tone:

1. Edit the SYSTEM_PROMPT
2. Run `biochecha_daily_insight.py` manually
3. Read the output, iterate

The insight's `data` jsonb field captures `{model, data_window_days, summary_counts}` so you can audit which model + how much data backed each row.

## Failure handling

All three scripts:
- Write to `public.agent_runs` on every run (status = ok / partial / error)
- Print to stdout for cron-log visibility
- Exit non-zero on fatal failures so cron escalation paths trigger

8sleep is the most fragile (reverse-engineered API). When it changes, expect agent_runs status='error' rows. The insight script is resilient: if 8sleep data is empty for the day, the prompt explicitly tells GPT to say "no notable sleep signal" honestly.
