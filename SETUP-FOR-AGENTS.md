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

```bash
cd ~/Developer/ThePerch/supabase/migrations
ls *.sql | sort   # confirm filename order — migrations apply in order
```

The user can paste each migration into Supabase's SQL Editor (Dashboard → SQL Editor → New Query → paste → Run), in **filename order**. Or if they have the Supabase CLI:

```bash
supabase db push --project-ref <YOUR-PROJECT-REF>
```

Verify a few key tables exist after migrations land:

```sql
-- Run in Supabase SQL Editor
SELECT count(*) FROM public.users;            -- should exist (may be 0)
SELECT count(*) FROM public.orders;           -- should exist
SELECT count(*) FROM public.health_metrics;   -- should exist
SELECT count(*) FROM public.insights;         -- should exist
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

# 8sleep — only needed if you have an 8sleep mattress (Step 9)
export EIGHT_SLEEP_EMAIL=
export EIGHT_SLEEP_PASSWORD=

# 17track — only needed for shipment ETAs (Step 10)
export SEVENTEEN_TRACK_API_KEY=
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

You should see `_supabase_client.py`, `biochecha_daily_insight.py`, `eight_sleep_ingest.py`, `withings_ingest.py`, `withings_setup.py`.

---

## Step 7 — BioChecha daily insight (optional, recommended)

Skip this if the user doesn't want LLM-generated daily insights.

The user needs an OpenAI API key (https://platform.openai.com/api-keys). gpt-4o-mini, ~$0.0001 per insight, so daily cost is negligible.

```bash
# After they paste the key into perch.env:
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_daily_insight.py
```

If it succeeds, an insight row lands in `public.insights` with today's date. Verify:

```sql
SELECT * FROM public.insights WHERE agent_id = 'biochecha' ORDER BY valid_for_date DESC LIMIT 1;
```

The first run will likely say "Quiet data day" because there's no health data yet. That's expected.

---

## Step 8 — Withings (optional)

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

## Step 9 — 8sleep (optional, may break)

Skip if the user doesn't have an 8sleep mattress. Warn them this integration is reverse-engineered and may break.

User adds `EIGHT_SLEEP_EMAIL` + `EIGHT_SLEEP_PASSWORD` (their 8sleep app login) to `perch.env`. Then:

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/.openclaw/workspace/scripts/health-integrations/eight_sleep_ingest.py
```

Should report `written=N failed=0`. Pulls the last 14 days of nightly data into `public.health_metrics`.

---

## Step 10 — 17track (optional, for shipment ETAs)

Skip if the user doesn't ship online or doesn't care about ETAs.

User signs up at https://api.17track.net/, gets an API key (free tier covers ~40 trackings/month), pastes into `perch.env` as `SEVENTEEN_TRACK_API_KEY`.

The orders skill will use it on next inbox scan.

---

## Step 11 — Cron jobs

The Perch's data pipeline runs on cron. Add these entries to `~/.openclaw/cron/jobs.json`:

```bash
# Open the file in $EDITOR — or have the user paste these in:
$EDITOR ~/.openclaw/cron/jobs.json
```

Three new entries to add (paste into the `jobs` array — match the existing shape):

```json
{
  "id": "<generate-uuid>",
  "agentId": "cron-agent",
  "name": "8sleep-ingest",
  "description": "Pull last night's 8sleep session every 30 min",
  "enabled": true,
  "schedule": { "kind": "cron", "expr": "*/30 * * * *", "tz": "Europe/Lisbon" },
  "sessionTarget": "isolated",
  "wakeMode": "now",
  "delivery": { "channel": "last", "mode": "none" },
  "payload": {
    "kind": "agentTurn",
    "message": "Run: python3 ~/.openclaw/workspace/scripts/health-integrations/eight_sleep_ingest.py. Report results.",
    "model": "minimax-portal/MiniMax-M2.7-highspeed",
    "timeoutSeconds": 300
  },
  "state": {}
},
{ "id": "<generate-uuid>", "agentId": "cron-agent", "name": "withings-ingest", "...": "same shape, schedule expr '0 * * * *', script withings_ingest.py" },
{ "id": "<generate-uuid>", "agentId": "cron-agent", "name": "biochecha-daily-insight", "...": "same shape, schedule expr '0 7 * * *', script biochecha_daily_insight.py, timeoutSeconds 600" }
```

(Tweak the user's timezone if they're not in Lisbon. Generate UUIDs via `uuidgen`.)

---

## Step 12 — LaunchAgent for 17track polling

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

## Step 13 — iOS app

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

## Step 14 — Smoke test

```bash
# Verify a few endpoints by hitting Supabase directly:
set -a && source ~/.openclaw/secrets/perch.env && set +a
curl -s "$SUPABASE_URL/rest/v1/health_metrics?select=metric&limit=1" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"
```

Should return `[]` initially (or `[{"metric":"..."}]` after the first ingest run).

Run all three ingest scripts manually so the user can see data on Today the first time they open the app:

```bash
python3 ~/.openclaw/workspace/scripts/health-integrations/withings_ingest.py
python3 ~/.openclaw/workspace/scripts/health-integrations/eight_sleep_ingest.py
python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_daily_insight.py
```

---

## Done

If you got through all 14 steps cleanly: tell the user The Perch is live, give them the next-build instructions ("bump build, run on device"), and exit. If you got stuck, tell them which step and why.

Common stumbles to watch for:

- **"Missing env" errors:** they didn't `source perch.env` in the same shell that's running the script.
- **Withings ingest writes 0:** their most recent weigh-in is older than the script's lookback window. Default is 60 days — adjust if needed.
- **8sleep "session token not supported":** 8sleep updated their auth flow again. Open an issue; we'll fix.
- **iOS app shows "BioChecha takes the morning…":** the BioChecha cron hasn't fired today yet, or the insight failed to decode. Check `agent_runs` for errors.
- **Karakeep tab shows "not configured":** expected if they didn't set `KARAKEEP_BASE_URL`. Working as intended.

---

## You — agent — should not

- Modify any of the user's existing data without explicit confirmation.
- Push any commits to the user's repo without explicit confirmation.
- Skip the rotation reminder if they've ever distributed an IPA.
- Auto-resolve "Withings ingest failed" by changing migration files. Migrations are immutable once applied.
